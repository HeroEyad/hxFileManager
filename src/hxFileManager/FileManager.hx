package src.hxFileManager;

import haxe.display.Display.Package;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import haxe.ds.StringMap;
import haxe.Json;
import src.hxFileManager.FileUtils;

class FileManager {
    public function new() {}

    // Create a new file with content
    public function createFile(filePath:String, content:String):Void {
        try {
            File.saveContent(filePath, content);
            trace("File created at: " + filePath);
        } catch (e:Dynamic) {
            trace("Error creating file: " + e);
        }
    }

    // Read the content of a file
    public function readFile(filePath:String):String {
        try {
            return File.getContent(filePath);
        } catch (e:Dynamic) {
            trace("Error reading file: " + e);
            return "";
        }
    }

	public function deleteFile(filePath:String):Void {
		try {
			FileUtils.deleteFile(filePath);
			trace("File deleted: " + filePath);
		} catch (e:Dynamic) {
			trace("Error deleting file: " + e);
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
        try {
            FileSystem.createDirectory(folderPath);
            trace("Folder created at: " + folderPath);
        } catch (e:Dynamic) {
            trace("Error creating folder: " + e);
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
        return Path.join([Sys.getEnv("APPDATA"), "YourAppName"]);
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
}
