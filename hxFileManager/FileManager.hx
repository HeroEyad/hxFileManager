package hxFileManager;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import haxe.ds.StringMap;
import haxe.Json;
import haxe.Timer;
import sys.thread.Thread;
import sys.io.Process;
import hxFileManager.FileUtils;

class FileManager {
	public static final isAdmin:Bool = checkIfAdmin();
	public static final rootDir:String = Path.directory(Sys.programPath());

	// Create or overwrite a file
	public static function createFile(filePath:String, content:String):Void {
		try {
			File.saveContent(filePath, content);
			trace("File created at: " + filePath);
		} catch (e:Dynamic) {
			trace("Error creating file: " + e);
		}
	}

	// Deprecated synchronous file read
    @:deprecated("Use readFileAsync instead")
	public static function readFile(filePath:String):String {
		try {
            return File.getContent(filePath);
        } catch (e:Dynamic) {
			trace("Error reading file: " + e);
			return "";
		}
	}

	// Async-style read 
    public static function readFileAsync(filePath:String, ?onSuccess:String->Void = null, ?onError:Dynamic->Void = null):Void {
        Thread.create(() -> {
            try {
                var content = File.getContent(filePath);
    
                // delay callback onto main thread using haxe.Timer
                if (onSuccess != null) 
                    Timer.delay(() -> onSuccess(content), 0);
                
            } catch (e:Dynamic) {
                if (onError != null) 
                    Timer.delay(() -> onError(e), 0);
                
            }
        });
    }
    
	// Metadata info
	public static function getFileMetadata(filePath:String):StringMap<Dynamic> {
		var stat = FileSystem.stat(filePath);   
		return [
			"size" => stat.size,
			"lastModified" => stat.mtime
		];
	}

	public static function fileExists(filePath:String):Bool
		return FileSystem.exists(filePath);

	public static function folderExists(folderPath:String):Bool
		return FileSystem.isDirectory(folderPath);

	// File deletion
	public static function deleteFile(filePath:String):Void {
		if (!fileExists(filePath)) return;
		try {
			FileSystem.deleteFile(filePath);
			trace("File deleted: " + filePath);
		} catch (e:Dynamic) {
			trace("Error deleting file: " + e);
		}
	}

	// Rename/move
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

	// File ops
	public static function moveFolder(sourcePath:String, destPath:String):Void {
		try FileSystem.rename(sourcePath, destPath) catch (e:Dynamic) trace("Error moving folder: " + e);
	}

	public static function copyFile(sourcePath:String, destPath:String):Void {
		try {
			File.copy(sourcePath, destPath);
			trace("File copied from " + sourcePath + " to " + destPath);
		} catch (e:Dynamic) {
			trace("Error copying file: " + e);
		}
	}

	// List files
	public static function listFiles(folderPath:String):Array<String> {
		try { return FileSystem.readDirectory(folderPath); }
        catch (e:Dynamic) {
			trace("Error listing files: " + e);
			return [];
		}
	}

	// Folder creation
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

	// Folder deletion (shallow)
	public static function deleteFolder(folderPath:String):Void {
		if (!folderExists(folderPath)) return;
		try {
			FileSystem.deleteDirectory(folderPath);
			trace('Folder deleted: ' + folderPath);
		} catch (e:Dynamic) {
			trace("Error deleting folder: " + e);
		}
	}

	// Recursive deletion
	@:deprecated("use deletePathAsync!")
	public static function deletePath(path:String):Void {
		remove(Path.normalize(path));
	}

	public static function deletePathAsync(path:String, ?onDone:Void->Void):Void {
		Thread.create(() -> {
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

	// JSON handling
	@:deprecated("Use readJsonAsync!")
	public static function readJson(filePath:String):Dynamic {
		return Json.parse(readFile(filePath));
	}

	public static function readJsonAsync(filePath:String, onResult:Dynamic->Void, ?onError:Dynamic->Void = null):Void {
		readFileAsync(filePath, (content) -> {
			try {
				var parsed = Json.parse(content);
				onResult(parsed);
			} catch (e:Dynamic) {
				if (onError != null) onError(e);
			}
		}, onError);
	}

	@:deprecated("Use writeJsonAsync!")
	public static function writeJson(filePath:String, data:Dynamic):Void {
		createFile(filePath, Json.stringify(data));
	}

	public static function writeJsonAsync(filePath:String, data:Dynamic, ?onDone:Void->Void):Void {
		Thread.create(() -> {
			var json = Json.stringify(data);
			File.saveContent(filePath, json);
			if (onDone != null) Timer.delay(onDone, 0);
		});
	}
	

    // Get AppData path for the current game.
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
    
        // Optionally create the folder if it doesn't exist
        if (!FileSystem.exists(appDataPath)) 
            FileSystem.createDirectory(appDataPath);
        
    
        return appDataPath;
    }
    

	// Operation logger
	public static function logOperation(operation:String, path:String, success:Bool):Void {
		trace('${Date.now()}: $operation on $path ${success ? "succeeded" : "failed"}');
	}

	// Admin check
	@:noCompletion
    public static function checkIfAdmin():Bool {
        #if windows
        return FileUtils.isUserAdmin();
        #elseif linux || mac
        return Sys.getEnv("USER") == "root";
        #else
        return false;
        #end
    }
    

    // Get file extension
    public static function getFileExtension(filePath:String):String
        return Path.extension(filePath).toLowerCase();
    
    // File & Folder Search.
	public static function searchFilesAsync(folderPath:String, pattern:String, onResult:Array<String>->Void):Void {
		Thread.create(() -> {
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
	
			// Send results back to main thread safely
			Timer.delay(() -> onResult(result), 0);
		});
	}
	
    
    // Safely write a file.
    public static function safeWrite(filePath:String, content:String):Void {
        if (fileExists(filePath)) 
            File.copy(filePath, filePath + ".bak");
        File.saveContent(filePath, content);
    }
    
}
