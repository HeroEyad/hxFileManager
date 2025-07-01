# hxFileManager

<p align="center">
  <img src="hxfilemanagerlogo.png" width="256" />
</p>

<p align="center">
  <img src="https://img.shields.io/github/repo-size/HeroEyad/hxFileManager" />
  <img src="https://badgen.net/github/stars/HeroEyad/hxFileManager" />
  <img src="https://badgen.net/badge/license/MIT/green" />
</p>

**hxFileManager** is a file management library designed for use with Haxe, associated with `sys.FileSystem` and `sys.io.File`. It provides a simple and consistent interface for performing file operations across various platforms, making it easy for developers to manage files without dealing with platform-specific details.

## Features

- **Simple API**: Intuitive and straightforward methods for common file management tasks.
- **Lightweight**: Minimal overhead, focusing on essential file operations.

## Installation

To include `hxFileManager` in your Haxe project, add it to your project dependencies:

```json
{
  "dependencies": {
    "hxFileManager": "1.0.0"
  }
}
````

## Usage

Here's a basic example of how to use `hxFileManager`:

```haxe
import hxFileManager.FileManager;

class Main {
    static function main() {
        // Example usage of the library
        FileManager.initThreadPool(); // VERY IMPORTANT!!
        FileManager.copyFile("source.txt", "destination");
        FileManager.copyFolder("folder", "destination");
        FileManager.deleteFile("testfolder/test.html");
    }
}
```

## Contributors

* HeroEyad

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Links

* [GitHub Repository](https://github.com/HeroEyad/hxFileManager)
* [Haxelib Library](https://lib.haxe.org/p/hxFileManager/)
* [API Documentation](https://www.heroeyad.xyz/hxFileManagerAPI/)

```