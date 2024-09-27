# hxFileManager

**hxFileManager** is a cross-platform file management library designed for use with Haxe associated with FileManager. It provides a simple and consistent interface for performing file operations across various platforms, making it easy for developers to manage files without dealing with platform-specific details.

## Features

- **Cross-Platform Support**: Works seamlessly across different operating systems.
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
```

## Usage

Here's a basic example of how to use `hxFileManager`:

```haxe
import hxFileManager.FileManager;

class Main {
    static function main() {
        // Example usage of the library
        FileManager.copyFile("source.txt", "destination.txt");
    }
}
```

## Contributors

- HeroEyad

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Links

- [GitHub Repository](https://github.com/HeroEyad/hxFileManager)