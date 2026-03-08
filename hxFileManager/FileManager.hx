package hxFileManager;

import haxe.io.Bytes;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import haxe.ds.StringMap;
import haxe.Json;
import haxe.Timer;
import sys.thread.Thread;
import sys.thread.Mutex;
import sys.thread.Deque;
import hxFileManager.HttpManager;
import hxFileManager.utils.*;

using StringTools;

private class Task {
	public final fn:Void->Void;
	public function new(fn:Void->Void) this.fn = fn;
	public inline function run():Void fn();
}

enum Result<T> {
	Ok(value:T);
	Err(reason:String);
}

class FileManager {

	#if (windows || mac || linux)
	public static final rootDir:String = Path.directory(Sys.programPath());
	#else
	public static final rootDir:String = "";
	#end

	public static var isAdmin(default, null):Bool =
		#if windows   FileUtils.isUserAdmin()
		#elseif (linux || mac) Sys.command("id", ["-u"]) == 0
		#else false #end;

	static final exePath:String = Sys.programPath();
	static final queue:Deque<Task> = new Deque();
	static var workers:Array<Thread> = [];
	static var running:Bool = false;

	/**
	 * Initialise the worker-thread pool. Must be called before any async method. Safe to call multiple times.
	 * @param numThreads Number of worker threads (default 4).
	 */
	public static function init(numThreads:Int = 4):Void {
		if (running) return;
		running = true;
		for (_ in 0...numThreads) workers.push(Thread.create(workerLoop));
	}

	/**
	 * Drain the queue and stop all worker threads.
	 */
	public static function dispose():Void {
		if (!running) return;
		running = false;
		for (_ in workers) queue.add(new Task(() -> {}));
		workers = [];
	}

	static function workerLoop():Void {
		while (running) {
			var task = queue.pop(true);
			if (task == null || !running) break;
			try task.run() catch (e) trace("FileManager worker error: " + e);
		}
	}

	/**
	 * Enqueue arbitrary work onto the shared thread pool.
	 * @param fn Function to execute on a worker thread.
	 */
	public static inline function enqueueAsync(fn:Void->Void):Void {
		#if debug
		if (!running) throw "FileManager not initialised — call FileManager.init() first";
		#end
		queue.add(new Task(fn));
	}

	static inline function mainThread(fn:Void->Void):Void
		Timer.delay(fn, 0);

	/**
	 * Returns true if the path exists and is a file.
	 * @param filePath Path to check.
	 */
	public static inline function fileExists(filePath:String):Bool
		return FileSystem.exists(filePath) && !FileSystem.isDirectory(filePath);

	/**
	 * Returns true if the path exists and is a directory.
	 * @param folderPath Path to check.
	 */
	public static inline function folderExists(folderPath:String):Bool
		return FileSystem.exists(folderPath) && FileSystem.isDirectory(folderPath);

	/**
	 * Async version of fileExists.
	 * @param filePath Path to check.
	 * @param onResult Callback with result.
	 */
	public static function fileExistsAsync(filePath:String, onResult:Bool->Void):Void
		enqueueAsync(() -> mainThread(() -> onResult(fileExists(filePath))));

	/**
	 * Async version of folderExists.
	 * @param folderPath Path to check.
	 * @param onResult Callback with result.
	 */
	public static function folderExistsAsync(folderPath:String, onResult:Bool->Void):Void
		enqueueAsync(() -> mainThread(() -> onResult(folderExists(folderPath))));

	/**
	 * Read a text file asynchronously.
	 * @param filePath Path to read.
	 * @param onSuccess Callback with file content.
	 * @param onError Optional error callback.
	 */
	public static function readFileAsync(filePath:String, onSuccess:String->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try mainThread(() -> onSuccess(File.getContent(filePath)))
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * Read a file as raw bytes asynchronously.
	 * @param filePath Path to read.
	 * @param onSuccess Callback with bytes.
	 * @param onError Optional error callback.
	 */
	public static function readFileBytesAsync(filePath:String, onSuccess:Bytes->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try mainThread(() -> onSuccess(File.getBytes(filePath)))
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * Write a text file asynchronously, creating parent directories as needed.
	 * @param filePath Destination path.
	 * @param content Content to write.
	 * @param onSuccess Optional callback with elapsed seconds.
	 * @param onError Optional error callback.
	 */
	public static function writeFileAsync(filePath:String, content:String, ?onSuccess:Float->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			var t = haxe.Timer.stamp();
			try {
				ensureParentDir(filePath);
				File.saveContent(filePath, content);
				var elapsed = haxe.Timer.stamp() - t;
				if (onSuccess != null) mainThread(() -> onSuccess(elapsed));
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Write raw bytes to a file asynchronously.
	 * @param filePath Destination path.
	 * @param bytes Bytes to write.
	 * @param onSuccess Optional callback with elapsed seconds.
	 * @param onError Optional error callback.
	 */
	public static function writeBytesAsync(filePath:String, bytes:Bytes, ?onSuccess:Float->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			var t = haxe.Timer.stamp();
			try {
				ensureParentDir(filePath);
				File.saveBytes(filePath, bytes);
				var elapsed = haxe.Timer.stamp() - t;
				if (onSuccess != null) mainThread(() -> onSuccess(elapsed));
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Alias for writeFileAsync kept for API compatibility.
	 * @param filePath Destination path.
	 * @param content Content to write.
	 * @param onSuccess Optional callback with elapsed seconds.
	 * @param onError Optional error callback.
	 */
	public static inline function createFileAsync(filePath:String, content:String, ?onSuccess:Float->Void, ?onError:String->Void):Void
		writeFileAsync(filePath, content, onSuccess, onError);

	/**
	 * Append text to a file asynchronously, creating the file if it does not exist.
	 * @param filePath Target file path.
	 * @param content Content to append.
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function appendFileAsync(filePath:String, content:String, ?onDone:Void->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try {
				ensureParentDir(filePath);
				var out = sys.io.File.append(filePath, false);
				out.writeString(content);
				out.close();
				if (onDone != null) mainThread(onDone);
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Prepend text to a file asynchronously. Reads the existing content and rewrites with the new content at the front.
	 * @param filePath Target file path.
	 * @param content Content to prepend.
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function prependFileAsync(filePath:String, content:String, ?onDone:Void->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try {
				var existing = fileExists(filePath) ? File.getContent(filePath) : "";
				File.saveContent(filePath, content + existing);
				if (onDone != null) mainThread(onDone);
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Atomically write a file by backing up the existing content first. Restores the backup if the write fails.
	 * @param filePath Target file path.
	 * @param content Content to write.
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function safeWriteAsync(filePath:String, content:String, ?onDone:Void->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			var backup = filePath + ".bak";
			try {
				if (fileExists(filePath)) File.copy(filePath, backup);
				File.saveContent(filePath, content);
				if (fileExists(backup)) FileSystem.deleteFile(backup);
				if (onDone != null) mainThread(onDone);
			} catch (e:Dynamic) {
				if (fileExists(backup)) try File.copy(backup, filePath) catch (_) {}
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Read a file and split it into lines asynchronously.
	 * @param filePath Path to read.
	 * @param onSuccess Callback with array of lines.
	 * @param onError Optional error callback.
	 */
	public static function readLinesAsync(filePath:String, onSuccess:Array<String>->Void, ?onError:String->Void):Void
		readFileAsync(filePath, content -> onSuccess(content.split("\n")), onError);

	/**
	 * Write an array of strings to a file joined by newlines asynchronously.
	 * @param filePath Destination path.
	 * @param lines Lines to write.
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function writeLinesAsync(filePath:String, lines:Array<String>, ?onDone:Void->Void, ?onError:String->Void):Void
		writeFileAsync(filePath, lines.join("\n"), _ -> if (onDone != null) onDone(), onError);

	/**
	 * Erase all content from a file without deleting it.
	 * @param filePath Path to truncate.
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function truncateFileAsync(filePath:String, ?onDone:Void->Void, ?onError:String->Void):Void
		writeFileAsync(filePath, "", _ -> if (onDone != null) onDone(), onError);

	/**
	 * Read and parse a JSON file asynchronously.
	 * @param filePath Path to JSON file.
	 * @param onResult Callback with parsed data.
	 * @param onError Optional error callback.
	 */
	public static function readJsonAsync(filePath:String, onResult:Dynamic->Void, ?onError:String->Void):Void {
		readFileAsync(filePath, content -> {
			try onResult(Json.parse(content))
			catch (e:Dynamic) if (onError != null) onError(Std.string(e));
		}, onError);
	}

	/**
	 * Serialise data to JSON and write asynchronously.
	 * @param filePath Destination path.
	 * @param data Data to serialise.
	 * @param onDone Optional callback with elapsed seconds.
	 * @param onError Optional error callback.
	 * @param pretty Whether to pretty-print the JSON (default false).
	 */
	public static function writeJsonAsync(filePath:String, data:Dynamic, ?onDone:Float->Void, ?onError:String->Void, pretty:Bool = false):Void {
		enqueueAsync(() -> {
			var t = haxe.Timer.stamp();
			try {
				var json = pretty ? Json.stringify(data, null, "  ") : Json.stringify(data);
				ensureParentDir(filePath);
				File.saveContent(filePath, json);
				var elapsed = haxe.Timer.stamp() - t;
				if (onDone != null) mainThread(() -> onDone(elapsed));
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Read a JSON file, pass it through a transform function, and write it back.
	 * @param filePath Path to JSON file.
	 * @param patchFn Function that receives the parsed data and returns the modified data.
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function patchJsonAsync(filePath:String, patchFn:Dynamic->Dynamic, ?onDone:Void->Void, ?onError:String->Void):Void {
		readJsonAsync(filePath, data -> {
			try {
				var patched = patchFn(data);
				writeJsonAsync(filePath, patched, _ -> if (onDone != null) onDone(), onError);
			} catch (e:Dynamic) {
				if (onError != null) onError(Std.string(e));
			}
		}, onError);
	}

	/**
	 * Get file metadata asynchronously.
	 * @param filePath Path to the file.
	 * @param onResult Callback with a StringMap containing "size" and "lastModified".
	 * @param onError Optional error callback.
	 */
	public static function getFileMetadataAsync(filePath:String, onResult:StringMap<Dynamic>->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try {
				var stat = FileSystem.stat(filePath);
				var map:StringMap<Dynamic> = new StringMap();
				map.set("size", stat.size);
				map.set("lastModified", stat.mtime);
				mainThread(() -> onResult(map));
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Get file size in bytes asynchronously.
	 * @param filePath Path to the file.
	 * @param onResult Callback with size in bytes.
	 * @param onError Optional error callback.
	 */
	public static function getFileSizeAsync(filePath:String, onResult:Int->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try mainThread(() -> onResult(fileExists(filePath) ? FileSystem.stat(filePath).size : 0))
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * Get total size of a folder recursively asynchronously.
	 * @param folderPath Path to the folder.
	 * @param onResult Callback with total size in bytes.
	 * @param onError Optional error callback.
	 */
	public static function getFolderSizeAsync(folderPath:String, onResult:Int->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			var total = 0;
			function scan(dir:String):Void {
				if (!folderExists(dir)) return;
				for (item in FileSystem.readDirectory(dir)) {
					var full = Path.join([dir, item]);
					if (FileSystem.isDirectory(full)) scan(full);
					else total += FileSystem.stat(full).size;
				}
			}
			try { scan(folderPath); mainThread(() -> onResult(total)); }
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * Get last modified date of a file asynchronously.
	 * @param filePath Path to the file.
	 * @param onResult Callback with the modification Date.
	 * @param onError Optional error callback.
	 */
	public static function getLastModifiedAsync(filePath:String, onResult:Date->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try mainThread(() -> onResult(FileSystem.stat(filePath).mtime))
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * Returns the lowercase file extension without the leading dot.
	 * @param filePath Path to the file.
	 */
	public static inline function getFileExtension(filePath:String):String
		return Path.extension(filePath).toLowerCase();

	/**
	 * Returns the file name including extension.
	 * @param filePath Path to the file.
	 */
	public static inline function getFileName(filePath:String):String
		return Path.withoutDirectory(filePath);

	/**
	 * Returns the file name without its extension.
	 * @param filePath Path to the file.
	 */
	public static inline function getFileNameWithoutExt(filePath:String):String
		return Path.withoutExtension(Path.withoutDirectory(filePath));

	/**
	 * Returns the parent directory of a path.
	 * @param filePath Path to the file.
	 */
	public static inline function getParentDir(filePath:String):String
		return Path.directory(filePath);

	/**
	 * Copy a single file asynchronously.
	 * @param sourcePath Source file path.
	 * @param destPath Destination file path.
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function copyFileAsync(sourcePath:String, destPath:String, ?onDone:Void->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try {
				ensureParentDir(destPath);
				File.copy(sourcePath, destPath);
				if (onDone != null) mainThread(onDone);
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Copy a folder and its entire contents asynchronously.
	 * @param source Source folder path.
	 * @param dest Destination folder path.
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function copyFolderAsync(source:String, dest:String, ?onDone:Void->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			function rec(src:String, dst:String):Void {
				if (!FileSystem.exists(dst)) FileSystem.createDirectory(dst);
				for (item in FileSystem.readDirectory(src)) {
					var s = Path.join([src, item]);
					var d = Path.join([dst, item]);
					if (FileSystem.isDirectory(s)) rec(s, d);
					else File.copy(s, d);
				}
			}
			try {
				if (!folderExists(source)) throw "Source does not exist: " + source;
				rec(source, dest);
				if (onDone != null) mainThread(onDone);
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Move a file asynchronously.
	 * @param oldPath Current file path.
	 * @param newPath New file path.
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function moveFileAsync(oldPath:String, newPath:String, ?onDone:Void->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try {
				ensureParentDir(newPath);
				FileSystem.rename(oldPath, newPath);
				if (onDone != null) mainThread(onDone);
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Move a folder asynchronously.
	 * @param sourcePath Current folder path.
	 * @param destPath New folder path.
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function moveFolderAsync(sourcePath:String, destPath:String, ?onDone:Void->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try { FileSystem.rename(sourcePath, destPath); if (onDone != null) mainThread(onDone); }
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * Delete a file or directory tree asynchronously.
	 * @param path Path to delete.
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function deletePathAsync(path:String, ?onDone:Void->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try { removePath(Path.normalize(path)); if (onDone != null) mainThread(onDone); }
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * Copy a file next to itself with a suffix appended to its name.
	 * @param filePath Source file path.
	 * @param suffix Suffix to append before the extension (default "_copy").
	 * @param onDone Optional callback with the new file path.
	 * @param onError Optional error callback.
	 */
	public static function duplicateFileAsync(filePath:String, ?suffix:String = "_copy", ?onDone:String->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try {
				var dir    = Path.directory(filePath);
				var name   = Path.withoutExtension(Path.withoutDirectory(filePath));
				var ext    = Path.extension(filePath);
				var dotExt = ext == "" ? "" : "." + ext;
				var dest   = Path.join([dir, name + suffix + dotExt]);
				File.copy(filePath, dest);
				if (onDone != null) mainThread(() -> onDone(dest));
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	static function removePath(path:String):Void {
		if (!FileSystem.exists(path)) return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path)) removePath(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	/**
	 * Create a directory and any missing parent directories asynchronously.
	 * @param folderPath Path to create.
	 * @param onSuccess Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function createFolderAsync(folderPath:String, ?onSuccess:Void->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try { createDirRecursive(folderPath); if (onSuccess != null) mainThread(onSuccess); }
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * List the immediate contents of a folder asynchronously.
	 * @param folderPath Folder to list.
	 * @param onResult Callback with array of entry names.
	 * @param onError Optional error callback.
	 */
	public static function listFilesAsync(folderPath:String, onResult:Array<String>->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try mainThread(() -> onResult(FileSystem.readDirectory(folderPath)))
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * Recursively list all file paths under a folder asynchronously.
	 * @param folderPath Root folder to scan.
	 * @param onResult Callback with array of full file paths.
	 * @param onError Optional error callback.
	 */
	public static function listFilesDeepAsync(folderPath:String, onResult:Array<String>->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			var result:Array<String> = [];
			function rec(dir:String):Void {
				if (!folderExists(dir)) return;
				for (item in FileSystem.readDirectory(dir)) {
					var full = Path.join([dir, item]);
					if (FileSystem.isDirectory(full)) rec(full);
					else result.push(full);
				}
			}
			try { rec(folderPath); mainThread(() -> onResult(result)); }
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * List only subdirectory names in a folder asynchronously.
	 * @param folderPath Folder to list.
	 * @param onResult Callback with array of directory names.
	 * @param onError Optional error callback.
	 */
	public static function listFoldersAsync(folderPath:String, onResult:Array<String>->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try {
				var dirs = FileSystem.readDirectory(folderPath)
					.filter(item -> FileSystem.isDirectory(Path.join([folderPath, item])));
				mainThread(() -> onResult(dirs));
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Count files in a folder asynchronously.
	 * @param folderPath Folder to count files in.
	 * @param onResult Callback with count.
	 * @param recursive Whether to count recursively (default false).
	 * @param onError Optional error callback.
	 */
	public static function countFilesAsync(folderPath:String, onResult:Int->Void, recursive:Bool = false, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			var count = 0;
			function scan(dir:String):Void {
				if (!folderExists(dir)) return;
				for (item in FileSystem.readDirectory(dir)) {
					var full = Path.join([dir, item]);
					if (FileSystem.isDirectory(full)) { if (recursive) scan(full); }
					else count++;
				}
			}
			try { scan(folderPath); mainThread(() -> onResult(count)); }
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * Search for files whose name contains a pattern, recursively.
	 * @param folderPath Root folder to search.
	 * @param pattern Substring to match against file names.
	 * @param onResult Callback with array of matching full paths.
	 * @param onError Optional error callback.
	 */
	public static function searchFilesAsync(folderPath:String, pattern:String, onResult:Array<String>->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			var result:Array<String> = [];
			function recurse(folder:String):Void {
				if (!folderExists(folder)) return;
				for (item in FileSystem.readDirectory(folder)) {
					var full = Path.join([folder, item]);
					if (FileSystem.isDirectory(full)) recurse(full);
					else if (item.indexOf(pattern) != -1) result.push(full);
				}
			}
			try { recurse(folderPath); mainThread(() -> onResult(result)); }
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * Search for files by extension recursively.
	 * @param folderPath Root folder to search.
	 * @param ext File extension to match, with or without leading dot (e.g. "txt" or ".txt").
	 * @param onResult Callback with array of matching full paths.
	 * @param onError Optional error callback.
	 */
	public static function searchByExtensionAsync(folderPath:String, ext:String, onResult:Array<String>->Void, ?onError:String->Void):Void {
		var normalised = ext.toLowerCase().replace(".", "");
		searchFilesAsync(folderPath, "." + normalised, onResult, onError);
	}

	/**
	 * Search for files whose content contains a substring, recursively.
	 * @param folderPath Root folder to search.
	 * @param needle Substring to search for inside each file.
	 * @param onResult Callback with array of matching full paths.
	 * @param onError Optional error callback.
	 */
	public static function searchByContentAsync(folderPath:String, needle:String, onResult:Array<String>->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			var matches:Array<String> = [];
			function rec(dir:String):Void {
				if (!folderExists(dir)) return;
				for (item in FileSystem.readDirectory(dir)) {
					var full = Path.join([dir, item]);
					if (FileSystem.isDirectory(full)) rec(full);
					else try { if (File.getContent(full).indexOf(needle) != -1) matches.push(full); } catch (_) {}
				}
			}
			try { rec(folderPath); mainThread(() -> onResult(matches)); }
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * Remove all empty subdirectories under a folder asynchronously.
	 * @param folderPath Root folder to clean.
	 * @param onDone Optional callback with the number of removed directories.
	 * @param onError Optional error callback.
	 */
	public static function cleanEmptyFoldersAsync(folderPath:String, ?onDone:Int->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			var removed = 0;
			function rec(dir:String):Bool {
				if (!folderExists(dir)) return false;
				var empty = true;
				for (item in FileSystem.readDirectory(dir)) {
					var full = Path.join([dir, item]);
					if (FileSystem.isDirectory(full)) { if (!rec(full)) empty = false; }
					else empty = false;
				}
				if (empty && dir != folderPath) { FileSystem.deleteDirectory(dir); removed++; return true; }
				return false;
			}
			try { rec(folderPath); mainThread(() -> if (onDone != null) onDone(removed)); }
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	static var watchIdCounter:Int = 0;
	static var activeWatchers:Map<Int, Bool> = new Map();
	static final watchMutex:Mutex = new Mutex();

	/**
	 * Watch a folder for changes using mtime-hash polling. Returns a watch ID to pass to stopWatcher.
	 * @param path Folder path to watch.
	 * @param onChange Callback invoked on the main thread when a change is detected.
	 * @param intervalMs Polling interval in milliseconds (default 1000).
	 */
	public static function watchFolder(path:String, onChange:Void->Void, intervalMs:Int = 1000):Int {
		watchMutex.acquire();
		var id = watchIdCounter++;
		activeWatchers.set(id, true);
		watchMutex.release();

		var prevHash = computeFolderHash(path);

		enqueueAsync(function poll():Void {
			Sys.sleep(intervalMs / 1000.0);
			watchMutex.acquire();
			var alive = activeWatchers.exists(id) && activeWatchers.get(id);
			watchMutex.release();
			if (!alive) { watchMutex.acquire(); activeWatchers.remove(id); watchMutex.release(); return; }
			var newHash = computeFolderHash(path);
			if (newHash != prevHash) { prevHash = newHash; mainThread(onChange); }
			enqueueAsync(poll);
		});

		return id;
	}

	/**
	 * Watch a single file for modifications using mtime polling. Returns a watch ID to pass to stopWatcher.
	 * @param filePath File path to watch.
	 * @param onChange Callback invoked on the main thread when the file changes.
	 * @param intervalMs Polling interval in milliseconds (default 500).
	 */
	public static function watchFile(filePath:String, onChange:Void->Void, intervalMs:Int = 500):Int {
		watchMutex.acquire();
		var id = watchIdCounter++;
		activeWatchers.set(id, true);
		watchMutex.release();

		var prevMtime:Float = fileExists(filePath) ? FileSystem.stat(filePath).mtime.getTime() : 0;

		enqueueAsync(function poll():Void {
			Sys.sleep(intervalMs / 1000.0);
			watchMutex.acquire();
			var alive = activeWatchers.exists(id) && activeWatchers.get(id);
			watchMutex.release();
			if (!alive) { watchMutex.acquire(); activeWatchers.remove(id); watchMutex.release(); return; }
			var mtime:Float = fileExists(filePath) ? FileSystem.stat(filePath).mtime.getTime() : 0;
			if (mtime != prevMtime) { prevMtime = mtime; mainThread(onChange); }
			enqueueAsync(poll);
		});

		return id;
	}

	/**
	 * Stop a running file or folder watcher.
	 * @param watchId ID returned by watchFolder or watchFile.
	 */
	public static function stopWatcher(watchId:Int):Void {
		watchMutex.acquire();
		activeWatchers.set(watchId, false);
		watchMutex.release();
	}

	/** @deprecated Use stopWatcher instead. */
	public static inline function stopWatchingFolder(watchId:Int):Void
		stopWatcher(watchId);

	static function computeFolderHash(path:String):Float {
		var hash:Float = 0;
		if (!folderExists(path)) return 0;
		for (file in FileSystem.readDirectory(path)) {
			var full = Path.join([path, file]);
			if (!FileSystem.isDirectory(full)) hash += FileSystem.stat(full).mtime.getTime();
		}
		return hash;
	}

	/**
	 * Generate a unique file path by appending an incrementing counter if the path already exists.
	 * @param basePath The preferred file path.
	 * @param onResult Callback with the unique path.
	 */
	public static function generateUniqueFileNameAsync(basePath:String, onResult:String->Void):Void {
		enqueueAsync(() -> {
			var dir    = Path.directory(basePath);
			var name   = Path.withoutExtension(Path.withoutDirectory(basePath));
			var ext    = Path.extension(basePath);
			var dotExt = ext == "" ? "" : "." + ext;
			var result = basePath;
			var counter = 1;
			while (FileSystem.exists(result))
				result = Path.join([dir, '$name ($counter$dotExt)']);
			mainThread(() -> onResult(result));
		});
	}

	/**
	 * Create an empty temporary file and return its path asynchronously.
	 * @param onResult Callback with the temp file path.
	 * @param prefix Optional filename prefix (default "tmp_").
	 * @param suffix Optional filename suffix.
	 */
	public static function createTempFileAsync(onResult:String->Void, prefix:String = "tmp_", suffix:String = ""):Void {
		enqueueAsync(() -> {
			var path = buildTempPath(prefix, suffix);
			try { File.saveContent(path, ""); mainThread(() -> onResult(path)); }
			catch (e:Dynamic) trace("createTempFileAsync error: " + e);
		});
	}

	/**
	 * Create a temporary directory and return its path asynchronously.
	 * @param onResult Callback with the temp folder path.
	 * @param prefix Optional folder name prefix (default "tmp_").
	 */
	public static function createTempFolderAsync(onResult:String->Void, prefix:String = "tmp_"):Void {
		enqueueAsync(() -> {
			var path = buildTempPath(prefix, "");
			try { FileSystem.createDirectory(path); mainThread(() -> onResult(path)); }
			catch (e:Dynamic) trace("createTempFolderAsync error: " + e);
		});
	}

	static function buildTempPath(prefix:String, suffix:String):String {
		var base = Sys.getEnv("TMPDIR");
		if (base == null) {
			#if windows base = Sys.getEnv("TEMP");
			#else base = "/tmp"; #end
		}
		return Path.join([base, prefix + Std.string(Date.now().getTime()) + "_" + Std.string(Std.random(0xFFFF)) + suffix]);
	}

	/**
	 * Download a file from a URL asynchronously with retry logic.
	 * @param url Remote URL to download.
	 * @param savePath Local path to save to.
	 * @param headers Optional HTTP headers map.
	 * @param onProgress Optional progress callback receiving (bytesReceived, totalBytes).
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 * @param retries Number of attempts before failing (default 3).
	 */
	public static function downloadFileAsync(url:String, savePath:String, ?headers:Map<String, String>, ?onProgress:(Int, Int)->Void, ?onDone:Void->Void, ?onError:String->Void, retries:Int = 3):Void {
		enqueueAsync(() -> {
			var lastErr:String = "";
			for (attempt in 0...retries) {
				try {
					var bytes = HttpManager.requestBytes(url, headers, 5, onProgress);
					ensureParentDir(savePath);
					File.saveBytes(savePath, bytes);
					if (onDone != null) mainThread(onDone);
					return;
				} catch (e:Dynamic) {
					lastErr = Std.string(e);
					trace('Download attempt ${attempt + 1}/$retries failed: $lastErr');
				}
			}
			if (onError != null) mainThread(() -> onError(lastErr));
		});
	}

	/**
	 * Compute the MD5 hash of a file asynchronously.
	 * @param filePath Path to the file.
	 * @param onResult Callback with the hex hash string.
	 * @param onError Optional error callback.
	 */
	public static function hashFileMd5Async(filePath:String, onResult:String->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try mainThread(() -> onResult(haxe.crypto.Md5.make(File.getBytes(filePath)).toHex()))
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * Compute the SHA-256 hash of a file asynchronously.
	 * @param filePath Path to the file.
	 * @param onResult Callback with the hex hash string.
	 * @param onError Optional error callback.
	 */
	public static function hashFileSha256Async(filePath:String, onResult:String->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try mainThread(() -> onResult(haxe.crypto.Sha256.make(File.getBytes(filePath)).toHex()))
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * Compare two files byte-for-byte asynchronously.
	 * @param pathA First file path.
	 * @param pathB Second file path.
	 * @param onResult Callback with true if files are identical.
	 * @param onError Optional error callback.
	 */
	public static function compareFilesAsync(pathA:String, pathB:String, onResult:Bool->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try mainThread(() -> onResult(File.getBytes(pathA).compare(File.getBytes(pathB)) == 0))
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * Read a file and return its content as a Base64 string asynchronously.
	 * @param filePath Path to the file.
	 * @param onSuccess Callback with the Base64 string.
	 * @param onError Optional error callback.
	 */
	public static function readFileBase64Async(filePath:String, onSuccess:String->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try mainThread(() -> onSuccess(haxe.crypto.Base64.encode(File.getBytes(filePath))))
			catch (e:Dynamic) if (onError != null) mainThread(() -> onError(Std.string(e)));
		});
	}

	/**
	 * Decode a Base64 string and write it to a file asynchronously.
	 * @param filePath Destination path.
	 * @param base64 Base64-encoded content to write.
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function writeFileBase64Async(filePath:String, base64:String, ?onDone:Void->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try {
				ensureParentDir(filePath);
				File.saveBytes(filePath, haxe.crypto.Base64.decode(base64));
				if (onDone != null) mainThread(onDone);
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Delete multiple paths in a single async operation.
	 * @param paths Array of file or directory paths to delete.
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function batchDeleteAsync(paths:Array<String>, ?onDone:Void->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try {
				for (p in paths) removePath(Path.normalize(p));
				if (onDone != null) mainThread(onDone);
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Copy multiple file pairs in a single async operation.
	 * @param pairs Array of {src, dst} objects.
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function batchCopyAsync(pairs:Array<{src:String, dst:String}>, ?onDone:Void->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try {
				for (pair in pairs) { ensureParentDir(pair.dst); File.copy(pair.src, pair.dst); }
				if (onDone != null) mainThread(onDone);
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Move multiple file pairs in a single async operation.
	 * @param pairs Array of {src, dst} objects.
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function batchMoveAsync(pairs:Array<{src:String, dst:String}>, ?onDone:Void->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try {
				for (pair in pairs) { ensureParentDir(pair.dst); FileSystem.rename(pair.src, pair.dst); }
				if (onDone != null) mainThread(onDone);
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Read multiple files in a single async operation.
	 * @param paths Array of file paths to read.
	 * @param onResult Callback with a Map of path to content.
	 * @param onError Optional error callback.
	 */
	public static function batchReadAsync(paths:Array<String>, onResult:Map<String, String>->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			var results:Map<String, String> = new Map();
			try {
				for (p in paths) results.set(p, File.getContent(p));
				mainThread(() -> onResult(results));
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Write multiple files in a single async operation.
	 * @param entries Map of path to content.
	 * @param onDone Optional completion callback.
	 * @param onError Optional error callback.
	 */
	public static function batchWriteAsync(entries:Map<String, String>, ?onDone:Void->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try {
				for (path => content in entries) { ensureParentDir(path); File.saveContent(path, content); }
				if (onDone != null) mainThread(onDone);
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Request administrator or elevated privileges, re-launching the process if needed. Only works on native cpp targets.
	 * @param onSuccess Optional callback on success.
	 * @param onError Optional error callback.
	 */
	public static function requestAdmin(?onSuccess:Void->Void, ?onError:String->Void):Void {
		enqueueAsync(() -> {
			try {
				#if cpp
					#if windows
					FileUtils.requestAdmin();
					#elseif linux
					try Sys.command("pkexec", [exePath]) catch (_)
						try Sys.command("gksudo", [exePath]) catch (e2:Dynamic)
							throw "Could not elevate: " + e2;
					#elseif mac
					Sys.command("osascript", ["-e", 'do shell script "$exePath" with administrator privileges']);
					#else throw "Unsupported platform"; #end
				#else
				throw "Elevation only works on native (cpp) targets";
				#end
				if (onSuccess != null) mainThread(onSuccess);
			} catch (e:Dynamic) {
				if (onError != null) mainThread(() -> onError(Std.string(e)));
			}
		});
	}

	/**
	 * Returns the current platform name: "Windows", "Mac", "Linux", or "unknown".
	 */
	public static function getPlatformName():String {
		#if (windows || mac || linux) return Sys.systemName();
		#else return "unknown"; #end
	}

	/**
	 * Returns the OS-appropriate application data path for the given app name, creating it if it does not exist.
	 * @param appName Application name used as the directory name.
	 */
	public static function getAppDataPath(appName:String):String {
		var base:String;
		#if windows base = Sys.getEnv("APPDATA");
		#elseif mac base = Path.join([Sys.getEnv("HOME"), "Library", "Application Support"]);
		#elseif linux base = Sys.getEnv("XDG_DATA_HOME") ?? Path.join([Sys.getEnv("HOME"), ".local", "share"]);
		#else throw "Unsupported platform"; #end
		if (base == null) throw "Could not determine AppData path";
		var appPath = Path.join([base, appName]);
		createDirRecursive(appPath);
		return appPath;
	}

	/** 
	 * Trace a timestamped log entry for a file operation.
	 * @param operation Operation name.
	 * @param path Path involved.
	 * @param success Whether it succeeded.
	 */
	public static function logOperation(operation:String, path:String, success:Bool):Void
	{
		var timestamp:String = Date.now().toString();
		var status:String = success ? "succeeded" : "failed";
		
		trace('[$timestamp] File operation "$operation" on "$path" $status.');
	}

	static function ensureParentDir(filePath:String):Void {
		var dir = Path.directory(filePath);
		if (dir != "" && dir != ".") createDirRecursive(dir);
	}

	static function createDirRecursive(path:String):Void {
		if (FileSystem.exists(path)) return;
		var parent = Path.directory(path);
		if (parent != "" && parent != path) createDirRecursive(parent);
		FileSystem.createDirectory(path);
	}

	@:deprecated("Use writeFileAsync") @:noCompletion
	public static inline function createFile(filePath:String, content:String):Void
		File.saveContent(filePath, content);

	@:deprecated("Use readFileAsync") @:noCompletion
	public static inline function readFile(filePath:String):String
		return try File.getContent(filePath) catch (_) "";

	@:deprecated("Use readJsonAsync") @:noCompletion
	public static inline function readJson(filePath:String):Dynamic
		return Json.parse(readFile(filePath));

	@:deprecated("Use writeJsonAsync") @:noCompletion
	public static inline function writeJson(filePath:String, data:Dynamic):Void
		File.saveContent(filePath, Json.stringify(data));

	@:deprecated("Use deletePathAsync") @:noCompletion
	public static inline function deletePath(path:String):Void
		removePath(Path.normalize(path));

	@:deprecated("Use safeWriteAsync") @:noCompletion
	public static function safeWrite(filePath:String, content:String):Void {
		if (fileExists(filePath)) File.copy(filePath, filePath + ".bak");
		File.saveContent(filePath, content);
	}

	@:deprecated("Use copyFolderAsync") @:noCompletion
	public static inline function copyFolderRecursive(source:String, dest:String, ?onDone:Void->Void, ?onError:Dynamic->Void):Void
		copyFolderAsync(source, dest, onDone, e -> if (onError != null) onError(e));

	@:deprecated("Use getFileSizeAsync") @:noCompletion
	public static inline function getFileSize(filePath:String, onResult:Int->Void, ?onError:Dynamic->Void):Void
		getFileSizeAsync(filePath, onResult, e -> if (onError != null) onError(e));

	@:deprecated("Use getFolderSizeAsync") @:noCompletion
	public static inline function getFolderSize(folderPath:String, onResult:Int->Void, ?onError:Dynamic->Void):Void
		getFolderSizeAsync(folderPath, onResult, e -> if (onError != null) onError(e));

	@:deprecated("Use listFilesAsync") @:noCompletion
	public static inline function listFiles(folderPath:String):Array<String>
		return try FileSystem.readDirectory(folderPath) catch (_) [];

	@:deprecated("Use copyFileAsync") @:noCompletion
	public static inline function copyFile(sourcePath:String, destPath:String):Void
		File.copy(sourcePath, destPath);

	@:deprecated("Use moveFolderAsync") @:noCompletion
	public static inline function moveFolder(sourcePath:String, destPath:String):Void
		FileSystem.rename(sourcePath, destPath);

	@:deprecated("Use moveFileAsync") @:noCompletion
	public static inline function renameFile(oldPath:String, newPath:String):Void
		FileSystem.rename(oldPath, newPath);

	@:deprecated("Use moveFolderAsync") @:noCompletion
	public static inline function renameFolder(folder:String, newFolder:String):Void
		if (FileSystem.exists(folder)) FileSystem.rename(folder, newFolder);

	@:deprecated("Use deletePathAsync") @:noCompletion
	public static inline function deleteFile(filePath:String):Void
		if (fileExists(filePath)) FileSystem.deleteFile(filePath);

	@:deprecated("Use deletePathAsync") @:noCompletion
	public static inline function deleteFolder(folderPath:String):Void
		if (folderExists(folderPath)) FileSystem.deleteDirectory(folderPath);

	@:deprecated("Use createFolderAsync") @:noCompletion
	public static inline function createFolder(folderPath:String):Void
		createDirRecursive(folderPath);

	@:deprecated("Use generateUniqueFileNameAsync") @:noCompletion
	public static inline function generateUniqueFileName(basePath:String, onResult:String->Void):Void
		generateUniqueFileNameAsync(basePath, onResult);

	@:deprecated("Use getFileMetadataAsync") @:noCompletion
	public static function getFileMetadata(filePath:String):StringMap<Dynamic> {
		var stat = FileSystem.stat(filePath);
		var m:StringMap<Dynamic> = new StringMap();
		m.set("size", stat.size); m.set("lastModified", stat.mtime);
		return m;
	}
}
