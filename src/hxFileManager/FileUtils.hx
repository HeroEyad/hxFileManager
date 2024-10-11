package src.hxFileManager;

@:native("move_directory")
@:native("delete_file")
@:native("copy")
@:native("get_file_info")
@:native("rename_folder")
extern class FileUtils {
    public static function moveDirectory(sourcePath:String, destPath:String):Void;

	public static function deleteFile(filePath:String):Void;

    public static function copy(filePath:String, destPath:String):Void;

    public static function getFileInfo(filePath:String):Void;

    public static function renameFolder(folder:String,  newFolder:String):Void;

}
