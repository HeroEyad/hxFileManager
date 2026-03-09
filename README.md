# hxFileManager

<p align="center">
    <img src="hxfilemanagerlogo.png" alt="hxFileManager Logo" width="200" />
</p>

<p align="center">
    <img src="https://img.shields.io/github/repo-size/HeroEyad/hxFileManager" alt="Repository Size" />
    <img src="https://badgen.net/github/stars/HeroEyad/hxFileManager" alt="GitHub Stars" />
    <img src="https://badgen.net/badge/license/MIT/green" alt="License" />
    <img src="https://badgen.net/badge/haxelib/1.4.0/orange" alt="Version" />
    <img src="https://badgen.net/badge/platform/Windows%20%7C%20Linux%20%7C%20Mac/blue" alt="Platforms" />
</p>

**hxFileManager** is a cross-platform file management library for Haxe built on a native worker thread pool. It wraps `sys.FileSystem` and `sys.io.File` behind a clean async API so file I/O never blocks your main thread. Every operation has a callback-based async counterpart, and the library ships with JSON helpers, file watching, MD5/SHA-256 hashing, HTTP downloads, and batch operations out of the box.

---

## Features

- **Async thread pool** — `init()` starts N worker threads; all `*Async` methods run off the main thread and return results via callbacks.
- **Full file I/O** — read, write, append, prepend, truncate, safe atomic write, raw bytes, Base64, and line-by-line helpers.
- **JSON** — read, write (with pretty-print), and patch-in-place with a transform function.
- **Folder operations** — create, copy, move, delete, recursive listing, subdirectory listing, file count, and empty-folder cleanup.
- **Search** — find files by name pattern, extension, or content substring.
- **File watching** — poll-based `watchFile` / `watchFolder` with configurable intervals and cancellation.
- **Hashing & comparison** — async MD5, SHA-256, and byte-for-byte file comparison.
- **Batch operations** — read, write, copy, move, and delete multiple paths in a single async call.
- **HTTP** — `HttpManager` provides GET, POST, PUT, PATCH, DELETE, JSON helpers, redirect following, retry logic, progress callbacks, and internet detection.
- **Platform utilities** — `getAppDataPath`, `getPlatformName`, `requestAdmin`, `generateUniqueFileNameAsync`, temp file/folder creation.
- **Metadata** — size, last-modified date, extension, filename, and parent directory helpers.
- **Backwards compatible** — deprecated sync shims kept under `@:deprecated @:noCompletion` for smooth migration.

---

## Installation

```bash
haxelib install hxFileManager
```

Or add it to your `haxelib.json` dependencies:

```json
{
    "dependencies": {
        "hxFileManager": "1.4.0"
    }
}
```

---

## Quick Start

```haxe
import hxFileManager.FileManager;
import hxFileManager.HttpManager;

class Main {
    static function main() {
        // Start the thread pool (required before any async call)
        FileManager.init();

        // Write a file asynchronously
        FileManager.writeFileAsync("hello.txt", "Hello, world!", elapsed -> {
            trace("Written in " + elapsed + "s");
        });

        // Read it back
        FileManager.readFileAsync("hello.txt", content -> {
            trace(content);
        });

        // Read and modify a JSON file in one step
        FileManager.patchJsonAsync("config.json", data -> {
            data.version = "1.4.0";
            return data;
        });

        // Download a file with progress
        FileManager.downloadFileAsync(
            "https://example.com/asset.zip",
            "downloads/asset.zip",
            null,
            (received, total) -> trace('$received / $total bytes'),
            () -> trace("Download complete!")
        );

        // Watch a folder for changes
        var watchId = FileManager.watchFolder("assets", () -> {
            trace("assets folder changed!");
        });

        // Stop watching later
        FileManager.stopWatcher(watchId);

        // Shut down cleanly when done
        FileManager.dispose();
    }
}
```

---

## HttpManager

`HttpManager` is a standalone HTTP client. All methods are synchronous — wrap them in `FileManager.enqueueAsync` for non-blocking use.

```haxe
import hxFileManager.HttpManager;

// GET
var html  = HttpManager.requestText("https://example.com");
var bytes = HttpManager.requestBytes("https://example.com/file.zip");

// POST JSON
HttpManager.postJson("https://api.example.com/scores",
    {player: "Hero", score: 9999},
    null,
    resp -> trace(resp)
);

// PUT / PATCH / DELETE
HttpManager.putJson("https://api.example.com/user/1", {name: "Hero"});
HttpManager.patchJson("https://api.example.com/user/1", {score: 100});
HttpManager.delete("https://api.example.com/user/1");

// Retry + internet check
var bytes = HttpManager.requestWithRetry("https://example.com/file.zip", 5, 1000);
HttpManager.checkInternetAsync(online -> trace(online ? "online" : "offline"));
```

---

## API Overview

### FileManager

| Category | Methods |
|---|---|
| Thread Pool | `init`, `dispose`, `enqueueAsync` |
| Existence | `fileExists`, `folderExists`, `fileExistsAsync`, `folderExistsAsync` |
| Read / Write | `readFileAsync`, `readFileBytesAsync`, `writeFileAsync`, `writeBytesAsync`, `appendFileAsync`, `prependFileAsync`, `truncateFileAsync`, `safeWriteAsync`, `readLinesAsync`, `writeLinesAsync`, `readFileBase64Async`, `writeFileBase64Async` |
| JSON | `readJsonAsync`, `writeJsonAsync`, `patchJsonAsync` |
| Metadata | `getFileMetadataAsync`, `getFileSizeAsync`, `getFolderSizeAsync`, `getLastModifiedAsync` |
| Path Helpers | `getFileExtension`, `getFileName`, `getFileNameWithoutExt`, `getParentDir` |
| Copy / Move / Delete | `copyFileAsync`, `copyFolderAsync`, `moveFileAsync`, `moveFolderAsync`, `deletePathAsync`, `duplicateFileAsync` |
| Folder Ops | `createFolderAsync`, `listFilesAsync`, `listFilesDeepAsync`, `listFoldersAsync`, `countFilesAsync`, `cleanEmptyFoldersAsync` |
| Search | `searchFilesAsync`, `searchByExtensionAsync`, `searchByContentAsync` |
| Watchers | `watchFolder`, `watchFile`, `stopWatcher` |
| Hashing | `hashFileMd5Async`, `hashFileSha256Async`, `compareFilesAsync` |
| Batch | `batchReadAsync`, `batchWriteAsync`, `batchCopyAsync`, `batchMoveAsync`, `batchDeleteAsync` |
| Utilities | `downloadFileAsync`, `generateUniqueFileNameAsync`, `createTempFileAsync`, `createTempFolderAsync`, `requestAdmin`, `getPlatformName`, `getAppDataPath`, `logOperation` |

### HttpManager

| Category | Methods |
|---|---|
| GET | `requestText`, `requestBytes`, `getJson`, `getStatusCode`, `getResponseHeaders`, `hasBytes` |
| POST / PUT / PATCH / DELETE | `postJson`, `postForm`, `putJson`, `patchJson`, `delete` |
| Utilities | `downloadTo`, `requestWithRetry`, `checkInternet`, `checkInternetAsync` |

---

## Migration from older versions

Sync methods from earlier versions (`createFile`, `readFile`, `copyFile`, etc.) are still present under `@:deprecated @:noCompletion` so existing code compiles without changes. They will be removed in a future major version. Replace them with their `*Async` equivalents when possible.

---

## Contributors

- [HeroEyad](https://github.com/HeroEyad)

---

## License

MIT — see [LICENSE](LICENSE) for details.

---

## Links

- [GitHub Repository](https://github.com/HeroEyad/hxFileManager)
- [Haxelib Page](https://lib.haxe.org/p/hxFileManager/)
- [API Documentation](https://heroeyad.github.io/hxFileManagerAPI/)