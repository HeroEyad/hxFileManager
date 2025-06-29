package hxFileManager;

@:headerCode('#include <windows.h>\nextern "C" bool is_user_admin();')
@:cppFileCode('extern "C" bool is_user_admin();')
extern class FileUtils {
    public static function isUserAdmin():Bool;
}
