package src.hxFileManager;

import haxe.display.Display.Package;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import haxe.ds.StringMap;
import haxe.Json;
import src.hxFileManager.FileUtils;

class FileManager {
	public static var isAdmin:Bool = checkIfAdmin();
    public static var rootDir:String = Path.directory( Sys.programPath() );

	public function new() {
        trace("Root Directory: "+ rootDir);
        trace("Is Admin: " + isAdmin);
	}

    // Create a new file with content
    public function createFile(filePath:String, content:String):Void {
        try {
            File.saveContent(filePath, content);
            trace("File created at: " + filePath);
        } catch (e:Dynamic) {
            trace("Error creating file: " + e);
        }
    }

    // Read the content of a file (DEPRECATED!!!)
    public function readFile(filePath:String):String {
        try {
            return File.getContent(filePath);
        } catch (e:Dynamic) {
            trace("Error reading file: " + e);
            return "";
        }
    }
    

	// More Optmizied ReadFile!
    public function readFileAsync(filePath:String, onSuccess:String->Void, onError:Dynamic->Void):Void {
		try {
			var content = File.getContent(filePath);
			onSuccess(content);
		} catch (e:Dynamic) {
			onError(e);
		}
	}

	// Get the File Metadata
    public function getFileMetadata(filePath:String):StringMap<Dynamic> {
		var info = new StringMap<Dynamic>();
		info.set("size", FileSystem.stat(filePath).size);
		info.set("lastModified", FileSystem.stat(filePath).mtime);
		return info;
	}


	public function deleteFile(filePath:String):Void {
        if (fileExists(filePath)) {
			try {
				FileUtils.deleteFile(filePath);
				trace("File deleted: " + filePath);
			} catch (e:Dynamic) {
				trace("Error deleting file: " + e);
			}
        }
	}

    // Check if the Folder does Exist or not
    public function folderExists(folderPath:String):Bool {
        if (FileSystem.isDirectory(folderPath)) {
            return true;
        } else {
            return false;
        }
    }

    // Delete a Folder
    public function deleteFolder(folderPath:String):Void {
        try {
			if (folderExists(folderPath)) {
				FileSystem.deleteDirectory(folderPath);
				trace('Folder Successfully deleted: ' + folderPath);
			}
        } catch (e:Dynamic) {
            trace("Error deleting folder: " + e);
        }
    }

	public function renameFolder(folder:String, newFolder:String) {
		if (fileExists(folder)) {
			try {
				FileUtils.renameFolder(folder, newFolder);
				trace("Folder renamed: " + folder + " to " + newFolder);
			} catch (e:Dynamic) {
				trace("Error renaming folder: " + e);
			}
		}
	}

    // List files in a folder
    public function listFiles(folderPath:String):Array<String> {
        try {
            return FileSystem.readDirectory(folderPath);
        } catch (e:Dynamic) {
            trace("Error listing files: " + e);
            return [];
        }
    }

    // Check if a file exists
    public function fileExists(filePath:String):Bool {
        return FileSystem.exists(filePath);
    }

    // Move a file
    public function moveFolder(sourcePath:String, destPath:String):Void {
        try {
            FileUtils.moveDirectory(sourcePath, destPath);
        } catch (e:Dynamic) {
            trace("Error moving folder: " + e);
        }
    }

    // Copy a file
    public function copyFile(sourcePath:String, destPath:String):Void {
        try {
            FileUtils.copy(sourcePath, destPath);
            trace("File copied from " + sourcePath + " to " + destPath);
        } catch (e:Dynamic) {
            trace("Error copying file: " + e);
        }
    }

    // Rename a file
    public function renameFile(oldPath:String, newPath:String):Void {
        try {
            FileSystem.rename(oldPath, newPath);
            trace("File renamed from " + oldPath + " to " + newPath);
        } catch (e:Dynamic) {
            trace("Error renaming file: " + e);
        }
    }

    // Create a new folder
	public function createFolder(folderPath:String):Void {
		if (!FileSystem.exists(folderPath)) {
			try {
				FileSystem.createDirectory(folderPath);
				trace("Folder created at: " + folderPath);
			} catch (e:Dynamic) {
				trace("Error creating folder: " + e);
			}
		} else {
			trace("Folder already exists: " + folderPath);
		}
	}


    // Delete a folder
    public static function deletePath(path:String):Void {
        remove(Path.normalize(path));
    }

    static function remove(path:String):Void {
        if (FileSystem.isDirectory(path)) {
            var list = FileSystem.readDirectory(path);
            for (it in list) {
                remove(Path.join([path, it]));
            }
            FileSystem.deleteDirectory(path);
            trace("Deleted directory: " + path);
        } else {
            FileSystem.deleteFile(path);
            trace("Deleted file: " + path);
        }
    }

    // Get the AppData folder path
	public function getAppDataPath():String {
		#if windows
		return Path.join([Sys.getEnv("APPDATA"), "YourAppName"]);
		#elseif linux
		return Path.join([Sys.getEnv("HOME"), ".yourappname"]);
		#elseif mac
		return Path.join([Sys.getEnv("HOME"), "Library/Application Support", "YourAppName"]);
		#else
        throw 'Unsupported Platform!';
        #end
	}

	public function logOperation(operation:String, path:String, success:Bool):Void {
		var logMessage = Date.now().toString() + ": " + operation + " on " + path + (success ? " succeeded" : " failed");
		trace(logMessage);
	}


    // Read a JSON file and return a dynamic object
    public function readJson(filePath:String):Dynamic {
        var content = readFile(filePath);
        return Json.parse(content);
    }

    // Write or update a JSON file
    public function writeJson(filePath:String, data:Dynamic):Void {
        var jsonData = Json.stringify(data);
        createFile(filePath, jsonData);
    }

	public static function checkIfAdmin():Bool {
		#if windows
		try {
			var proc = new Process("cmd", ["/C", "net", "session"]);
			proc.exitCode();
			return true;
		} catch (e:Dynamic) {
			return false;
		} #elseif linux || mac // Check if the current user is root (user ID 0).
		return Sys.getEnv("USER") == "root";
		#else
		return false;
		#end
	}

}
