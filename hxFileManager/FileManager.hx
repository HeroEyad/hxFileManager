package hxFileManager;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import haxe.ds.StringMap;
import haxe.Json;
import haxe.Timer;
import sys.thread.Thread;
import sys.io.Process;
#if cpp
import sys.thread.Mutex;
#end

class FileManager {
	#if (windows || mac || linux)
	public static final rootDir:String = Path.directory(Sys.programPath());
	#else
	public static final rootDir:String = ""; // or safe fallback
	#end
	public static var isAdmin(default, null):Bool = #if windows FileUtils.isUserAdmin() #elseif (linux || mac) Sys.command("id", ["-u"]) == 0 #else false #end;

	static var exePath = Sys.programPath();
	static var watchIdCounter:Int = 0;
    static var activeWatchers:Map<Int, Bool> = new Map();

	// === Thread Pool ===
	static var workers:Array<Thread> = [];
	static var numThreads:Int = 4;
	static var initialized = false;

	public static function initThreadPool():Void {
		if (initialized) return;
		initialized = true;

		for (i in 0...numThreads) {
			var thread = Thread.create(() -> {
				Thread.runWithEventLoop(() -> {
					var msg = Thread.readMessage(true);
					if (Std.is(msg, Task)) {
						try cast(msg, Task).run() catch (e) trace("Task error: " + e);
					}
				});
			});
			workers.push(thread);
		}
	}
	static var roundRobinIndex = 0;

	public static function enqueueAsync(fn:Void->Void):Void {
		if (workers.length == 0) {
			trace("No worker threads! Did you forget initThreadPool?");
			return;
		}
		var task = new Task(fn);
		var thread = workers[roundRobinIndex];
		roundRobinIndex = (roundRobinIndex + 1) % workers.length;
		thread.sendMessage(task);
	}

	// === File Operations ===

	public static function createFile(filePath:String, content:String):Void {
		try {
			File.saveContent(filePath, content);
			trace("File created at: " + filePath);
		} catch (e:Dynamic) {
			trace("Error creating file: " + e);
		}
	}

	@:deprecated("Use readFileAsync instead")
	public static function readFile(filePath:String):String {
		try return File.getContent(filePath) catch (e:Dynamic) {
			trace("Error reading file: " + e);
			return "";
		}
	}

	public static function stopWatchingFolder(watchId:Int):Void {
		if (activeWatchers.exists(watchId)) {
			activeWatchers.set(watchId, false); // polling loop will see this and exit
			trace('Requested stop for watch ID $watchId');
		}
	}
	
	public static function watchFolder(path:String, onChange:Void->Void, intervalMs:Int = 1000):Int {
		var watchId = watchIdCounter++;
		var prevHash = getFolderHash(path);
		activeWatchers.set(watchId, true);

		function poll():Void {
			enqueueAsync(() -> {
				Sys.sleep(intervalMs / 1000);

				if (!activeWatchers.exists(watchId) || !activeWatchers.get(watchId)) {
					trace('Stopped watching folder: $path');
					activeWatchers.remove(watchId);
					return;
				}

				var newHash = getFolderHash(path);
				if (newHash != prevHash) {
					prevHash = newHash;
					Timer.delay(onChange, 0); // safely call on main thread
				}

				poll(); // re-arm next check
			});
		}

		poll();
		trace('Started watching folder: $path (ID $watchId)');
		return watchId;
	}
	
	static function getFolderHash(path:String):Int {
		var hash = 0;
		if (!folderExists(path)) return 0;
		for (file in FileSystem.readDirectory(path)) {
			var full = Path.join([path, file]);
			if (!FileSystem.isDirectory(full)) {
				hash += Std.int(FileSystem.stat(full).mtime.getTime());
			}
		}
		return hash;
	}

	public static function getFileSize(filePath:String, onResult:Int->Void, ?onError:Dynamic->Void):Void {
		enqueueAsync(() -> {
			try {
				var size = fileExists(filePath) ? FileSystem.stat(filePath).size : 0;
				Timer.delay(() -> onResult(size), 0);
			} catch (e:Dynamic) {
				if (onError != null) Timer.delay(() -> onError(e), 0);
			}
		});
	}

	public static function getFolderSize(folderPath:String, onResult:Int->Void, ?onError:Dynamic->Void):Void {
		enqueueAsync(() -> {
			var totalSize = 0;

			function scan(dir:String):Void {
				if (!folderExists(dir)) return;
				for (item in FileSystem.readDirectory(dir)) {
					var fullPath = Path.join([dir, item]);
					if (FileSystem.isDirectory(fullPath)) {
						scan(fullPath);
					} else {
						totalSize += fileExists(fullPath) ? FileSystem.stat(fullPath).size : 0;
					}
				}
			}

			try {
				scan(folderPath);
				Timer.delay(() -> onResult(totalSize), 0);
			} catch (e:Dynamic) {
				if (onError != null) Timer.delay(() -> onError(e), 0);
			}
		});
	}

	public static function generateUniqueFileName(basePath:String, onResult:String->Void):Void {
		enqueueAsync(() -> {
			var dir = Path.directory(basePath);
			var name = Path.withoutExtension(Path.withoutDirectory(basePath));
			var ext = Path.extension(basePath);
			var counter = 1;

			while (FileSystem.exists(basePath)) {
				basePath = Path.join([dir, name + " (" + counter++ + ")." + ext]);
			}

			Timer.delay(() -> onResult(basePath), 0);
		});
	}
	
	public static function readFileAsync(filePath:String, ?onSuccess:String->Void = null, ?onError:Dynamic->Void = null):Void {
		enqueueAsync(() -> {
			try {
				var content = File.getContent(filePath);
				if (onSuccess != null) Timer.delay(() -> onSuccess(content), 0);
			} catch (e:Dynamic) {
				if (onError != null) Timer.delay(() -> onError(e), 0);
			}
		});
	}

	public static function getFileMetadata(filePath:String):StringMap<Dynamic> {
		var stat = FileSystem.stat(filePath);   
		return ["size" => stat.size, "lastModified" => stat.mtime];
	}

	public static function fileExists(filePath:String):Bool
		return FileSystem.exists(filePath);

	public static function folderExists(folderPath:String):Bool
		return FileSystem.isDirectory(folderPath);

	public static function deleteFile(filePath:String):Void {
		if (!fileExists(filePath)) return;
		try {
			FileSystem.deleteFile(filePath);
			trace("File deleted: " + filePath);
		} catch (e:Dynamic) {
			trace("Error deleting file: " + e);
		}
	}

	public static function renameFile(oldPath:String, newPath:String):Void {
		try {
			FileSystem.rename(oldPath, newPath);
			trace("File renamed from " + oldPath + " to " + newPath);
		} catch (e:Dynamic) {
			trace("Error renaming file: " + e);
		}
	}

	public static function renameFolder(folder:String, newFolder:String):Void {
		if (!fileExists(folder)) return;
		try {
			FileSystem.rename(folder, newFolder);
			trace("Folder renamed: " + folder + " to " + newFolder);
		} catch (e:Dynamic) {
			trace("Error renaming folder: " + e);
		}
	}

	public static function moveFolder(sourcePath:String, destPath:String):Void {
		try FileSystem.rename(sourcePath, destPath) catch (e:Dynamic) trace("Error moving folder: " + e);
	}
	
	public static function copyFolderRecursive(source:String, dest:String, ?onDone:Void->Void, ?onError:Dynamic->Void):Void {
		enqueueAsync(() -> {
			try {
				if (!folderExists(source)) {
					trace("Source folder does not exist: " + source);
					if (onError != null) Timer.delay(() -> onError("Source folder does not exist"), 0);
					return;
				}

				if (!folderExists(dest))
					FileSystem.createDirectory(dest);

				function copyRecursive(src:String, dst:String):Void {
					for (item in FileSystem.readDirectory(src)) {
						var srcPath = Path.join([src, item]);
						var dstPath = Path.join([dst, item]);

						if (FileSystem.isDirectory(srcPath)) {
							if (!folderExists(dstPath))
								FileSystem.createDirectory(dstPath);
							copyRecursive(srcPath, dstPath);
						} else {
							try {
								File.copy(srcPath, dstPath);
							} catch (e:Dynamic) {
								trace("Failed to copy file: " + srcPath + " -> " + dstPath + " | " + e);
								if (onError != null) Timer.delay(() -> onError(e), 0);
							}
						}
					}
				}

				copyRecursive(source, dest);
				if (onDone != null) Timer.delay(onDone, 0);
			} catch (e:Dynamic) {
				trace("Error copying folder: " + e);
				if (onError != null) Timer.delay(() -> onError(e), 0);
			}
		});
	}

	
	public static function copyFile(sourcePath:String, destPath:String):Void {
		try {
			File.copy(sourcePath, destPath);
			trace("File copied from " + sourcePath + " to " + destPath);
		} catch (e:Dynamic) {
			trace("Error copying file: " + e);
		}
	}

	public static function listFiles(folderPath:String):Array<String> {
		try return FileSystem.readDirectory(folderPath) catch (e:Dynamic) {
			trace("Error listing files: " + e);
			return [];
		}
	}

	public static function createFolder(folderPath:String):Void {
		if (FileSystem.exists(folderPath)) {
			trace("Folder already exists: " + folderPath);
			return;
		}
		try {
			FileSystem.createDirectory(folderPath);
			trace("Folder created at: " + folderPath);
		} catch (e:Dynamic) {
			trace("Error creating folder: " + e);
		}
	}

	public static function deleteFolder(folderPath:String):Void {
		if (!folderExists(folderPath)) return;
		try {
			FileSystem.deleteDirectory(folderPath);
			trace('Folder deleted: ' + folderPath);
		} catch (e:Dynamic) {
			trace("Error deleting folder: " + e);
		}
	}

	@:deprecated("Use deletePathAsync!")
	public static function deletePath(path:String):Void {
		remove(Path.normalize(path));
	}

	public static function deletePathAsync(path:String, ?onDone:Void->Void):Void {
		enqueueAsync(() -> {
			deletePath(path);
			if (onDone != null) Timer.delay(onDone, 0);
		});
	}

	static function remove(path:String):Void {
		try {
			if (FileSystem.isDirectory(path)) {
				for (entry in FileSystem.readDirectory(path))
					remove(Path.join([path, entry]));
				FileSystem.deleteDirectory(path);
				trace("Deleted directory: " + path);
			} else {
				FileSystem.deleteFile(path);
				trace("Deleted file: " + path);
			}
		} catch (e:Dynamic) {
			trace("Error deleting path: " + e);
		}
	}

	@:deprecated("Use readJsonAsync!")
	public static function readJson(filePath:String):Dynamic {
		var startTime = Timer.stamp();
		var result = Json.parse(readFile(filePath));
		var elapsedTime = Timer.stamp() - startTime;
		trace("JSON read from: " + filePath + " in " + elapsedTime + " seconds");
		return result;
	}

	public static function readJsonAsync(filePath:String, onResult:Dynamic->Void, ?onError:Dynamic->Void = null):Void {
		readFileAsync(filePath, (content) -> {
			try {
				var startTime = Timer.stamp();
				var parsed = Json.parse(content);
				var elapsedTime = Timer.stamp() - startTime;
				trace("JSON read from: " + filePath + " in " + elapsedTime + " seconds");
				onResult(parsed);
			} catch (e:Dynamic) {
				if (onError != null) onError(e);
			}
		}, onError);
	}

	@:deprecated("Use writeJsonAsync!")
	public static function writeJson(filePath:String, data:Dynamic):Void {
		var startTime = Timer.stamp();
		createFile(filePath, Json.stringify(data));
		var elapsedTime = Timer.stamp() - startTime;
		trace("JSON written to: " + filePath + " in " + elapsedTime + " seconds");
	}

	public static function writeJsonAsync(filePath:String, data:Dynamic, ?onDone:Float->Void):Void {
		enqueueAsync(() -> {
			var startTime = Timer.stamp();
			var json = Json.stringify(data);
			File.saveContent(filePath, json);
			var elapsedTime = Timer.stamp() - startTime;
			trace("JSON written to: " + filePath + " in " + elapsedTime + " seconds");
			if (onDone != null) Timer.delay(() -> onDone(elapsedTime), 0);
		});
	}

	public static function createFileAsync(filePath:String, content:String, ?onSuccess:Float->Void, ?onError:Dynamic->Void):Void {
		enqueueAsync(() -> {
			var startTime = Timer.stamp();
			try {
				File.saveContent(filePath, content);
				var elapsedTime = Timer.stamp() - startTime;
				trace("File created at: " + filePath + " in " + elapsedTime + " seconds");
				if (onSuccess != null) Timer.delay(() -> onSuccess(elapsedTime), 0);
			} catch (e:Dynamic) {
				trace("Error creating file: " + e);
				if (onError != null) Timer.delay(() -> onError(e), 0);
			}
		});
	}

	public static function getAppDataPath(appName:String):String {
		var base:String;
		#if windows
		base = Sys.getEnv("APPDATA");
		#elseif mac
		base = Path.join([Sys.getEnv("HOME"), "Library", "Application Support"]);
		#elseif linux
		base = Sys.getEnv("HOME");
		#else
		throw "Unsupported platform";
		#end
	
		if (base == null) throw "Could not determine AppData path";
	
		var appDataPath = Path.join([base, appName]);
		if (!FileSystem.exists(appDataPath))
			FileSystem.createDirectory(appDataPath);
	
		return appDataPath;
	}
	
	
	public static function logOperation(operation:String, path:String, success:Bool):Void {
		trace('${Date.now()}: $operation on $path ${success ? "succeeded" : "failed"}');
	}

	public static function getFileExtension(filePath:String):String
		return Path.extension(filePath).toLowerCase();

	public static function searchFilesAsync(folderPath:String, pattern:String, onResult:Array<String>->Void):Void {
		enqueueAsync(() -> {
			var result:Array<String> = [];

			function recurse(folder:String):Void {
				if (!folderExists(folder)) return;
				for (item in FileSystem.readDirectory(folder)) {
					var fullPath = Path.join([folder, item]);
					if (FileSystem.isDirectory(fullPath)) {
						recurse(fullPath);
					} else if (item.indexOf(pattern) != -1) {
						result.push(fullPath);
					}
				}
			}

			recurse(folderPath);
			Timer.delay(() -> onResult(result), 0);
		});
	}

	public static function safeWrite(filePath:String, content:String):Void {
		var startTime = Timer.stamp();
		if (fileExists(filePath)) 
			File.copy(filePath, filePath + ".bak");
		File.saveContent(filePath, content);
		var elapsedTime = Timer.stamp() - startTime;
		trace("File safely written to: " + filePath + " in " + elapsedTime + " seconds");
	}

	public static function requestAdmin(?onSuccess:Void->Void, ?onError:Dynamic->Void):Void {
		enqueueAsync(() -> {
			try {
				#if cpp			
					#if windows
					FileUtils.requestAdmin();
					#elseif linux
						try {
							Sys.command("pkexec", [exePath]);
						} catch (e:Dynamic) {
							try {
								Sys.command("gksudo", [exePath]);
							} catch (e2:Dynamic) {
								Sys.println("[requestAdmin] Could not elevate. Please run with sudo.");
								if (onError != null) Timer.delay(() -> onError(e2), 0);
								return;
							}
						}
					#elseif mac
						var script = 'do shell script "' + exePath + '" with administrator privileges';
						Sys.command("osascript", ["-e", script]);
					#else
						trace("[requestAdmin] Platform not supported.");
						if (onError != null) Timer.delay(() -> onError("Platform not supported"), 0);
						return;
					#end
				#else
					trace("[requestAdmin] Elevation only works on native targets.");
					if (onError != null) Timer.delay(() -> onError("Elevation only works on native targets"), 0);
					return;
				#end

				Timer.delay(onSuccess, 0);
			} catch (e:Dynamic) {
				trace("[requestAdmin] Error: " + e);
				if (onError != null) Timer.delay(() -> onError(e), 0);
			}
		});
	}

	public static function getPlatformName():String {
		#if (windows || mac || linux)
		return Sys.systemName();
		#else
		return "unknown";
		#end
	}
}
