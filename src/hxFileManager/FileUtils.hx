package src.hxFileManager;

@:native("move_directory")
@:native("delete_file")
@:native("copy_file")
@:native("get_file_info")
extern class FileUtils {
    public static function moveDirectory(sourcePath:String, destPath:String):Void;

	public static function deleteFile(filePath:String):Void;

    public static function copy(filePath:String, destPath:String):Void;

    public static function getFileInfo(filePath:String):Void;
}
