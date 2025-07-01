package tools;

import hxFileManager.FileManager;

class Main {
    static function main() {
        trace("=== FileManager Test Started ===");

        FileManager.initThreadPool();
        trace("It's running a threadPool!");

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
            }
        }*/
        trace("Running as admin: " + FileManager.isAdmin);

        var testFile = "test.txt";
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
            FileManager.readJsonAsync(jsonPath, json -> {
                FileManager.logOperation("Read JSON", jsonPath, json != null);
                trace("Read JSON Content: " + json);

                FileManager.searchFilesAsync(".", ".txt", results -> {
                    FileManager.logOperation("Search Files", ".", results.length > 0);
                    trace("Search Results: " + results);

                    // Safe write
                    FileManager.safeWrite("safe.txt", "Safe write content");
                    FileManager.logOperation("Safe Write", "safe.txt", FileManager.fileExists("safe.txt"));

                    // Clean up
                    FileManager.deleteFile(copiedFile);
                    FileManager.logOperation("Delete File", copiedFile, !FileManager.fileExists(copiedFile));

                    FileManager.deleteFolder(testFolder);
                    FileManager.logOperation("Delete Folder", testFolder, !FileManager.folderExists(testFolder));

                    done = true;
                });
            });
        });

        while (!done) Sys.sleep(0.1);

        trace("=== FileManager Test Complete ===");
    }
}
