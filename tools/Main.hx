package tools;

import hxFileManager.*;
import haxe.io.Bytes;

class Main {
    static function main() {
        trace("=== FileManager Test Started ===");
        var done = false;
        
        //trace("It's running a threadPool!");

        //trace("User is on " + FileManager.getPlatformName());

        /*if (!FileManager.isAdmin) { // try it out yourself
            trace("Not an Admin, Requesting Admin!");
            try {
            FileManager.requestAdmin(() -> {
                trace("Admin privileges granted.");
            }, (error:Dynamic) -> {
                trace("Admin privileges not granted. Error: " + error);
            });
            } catch (e:Dynamic) {
            trace("Error occurred while requesting admin: " + e);
            */

        trace("Running as admin: " + FileManager.isAdmin);

        /*var testFile = "test.txt";
        var testFolder = "testFolder";
        var renamedFile = "renamed.txt";
        var copiedFile = "copy.txt";
        var jsonPath = "data.json";

        var done = false;

        // Kick off async work
        FileManager.createFileAsync(testFile, "This is a test file.", _ -> {
            FileManager.logOperation("Create File", testFile, FileManager.fileExists(testFile));

            FileManager.renameFile(testFile, renamedFile);
            FileManager.logOperation("Rename File", renamedFile, FileManager.fileExists(renamedFile));

            FileManager.copyFile(renamedFile, copiedFile);
            FileManager.logOperation("Copy File", copiedFile, FileManager.fileExists(copiedFile));
        });

        FileManager.createFolder(testFolder);
        FileManager.logOperation("Create Folder", testFolder, FileManager.folderExists(testFolder));

        var appDataPath = FileManager.getAppDataPath("hxFileManagerTEST");
        FileManager.logOperation("Get AppData Path", appDataPath, FileManager.folderExists(appDataPath));
        trace("AppData Path: " + appDataPath);

        FileManager.writeJsonAsync(jsonPath, {msg: "Hello, JSON!"}, _ -> {
            FileManager.logOperation("Write JSON", jsonPath, FileManager.fileExists(jsonPath));
        });
        FileManager.readJsonAsync(jsonPath, json -> {
                FileManager.logOperation("Read JSON", jsonPath, json != null);
                trace("Read JSON Content: " + json);
        });
        */
        try {
            trace("Checking internet...");
            if (HttpManager.hasInternet) {
                trace("Internet is available!");
            } else {
                trace("No internet connection detected.");
            }
        } catch (e:Dynamic) {
            trace("Error checking internet: " + Std.string(e));
        }

        try {
            trace("Requesting text from http://google.com ...");
            var text:String = HttpManager.requestText("http://google.com");
            trace("Received text (first 100 chars): " + text.substr(0, Std.int(Math.min(100, text.length))));        
        } catch (e:Dynamic) {
            trace("Error fetching text: " + Std.string(e));
        }
        
        try {
            trace("Requesting a URL that redirects (http://google.com) ...");
            var redirectedText:String = HttpManager.requestText("http://google.com");
            trace("Redirect test succeeded, first 100 chars: " + redirectedText.substr(0, Std.int(Math.min(100, redirectedText.length))));
        } catch (e:Dynamic) {
            trace("Redirect test failed: " + Std.string(e));
        }

		trace("Starting download...");
		
		FileManager.downloadFile("https://i.kym-cdn.com/entries/icons/facebook/000/048/280/speed_trying_not_to_laugh.jpg",
			"plsspeedineedthis.jpg", null, function(downloaded:Int, total:Int)
		{
			trace('Downloaded $downloaded / $total bytes');
		});
		/*FileManager.safeWrite("safe.txt", "Safe write content");
		FileManager.logOperation("Safe Write", "safe.txt", FileManager.fileExists("safe.txt"));

		// unsure if this does anything
		FileManager.deleteFile(copiedFile);
		FileManager.logOperation("Delete File", copiedFile, !FileManager.fileExists(copiedFile));

		FileManager.deleteFolder(testFolder);
		FileManager.logOperation("Delete Folder", testFolder, !FileManager.folderExists(testFolder));*/
        

		trace("Download finished!");
		done = true;
        while (!done) Sys.sleep(0.1);

        trace("=== FileManager Test Complete ===");
    }
}
