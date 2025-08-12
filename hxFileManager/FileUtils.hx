package hxFileManager;

#if windows

@:buildXml('
<target id="haxe">
    <lib name="advapi32.lib" />
    <lib name="shell32.lib" />
</target>
')

#if cpp
@:headerCode('
    #include <windows.h>
    #include <shellapi.h>
    extern "C" void run_as_admin(const char* exePath);
    extern "C" bool is_user_elevated();
')
@:cppFileCode('
    extern "C" bool is_user_elevated() {
        HANDLE hToken;
        TOKEN_ELEVATION elevation;
        DWORD dwSize;
        if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &hToken)) {
            if (GetTokenInformation(hToken, TokenElevation, &elevation, sizeof(elevation), &dwSize)) {
                CloseHandle(hToken);
                return elevation.TokenIsElevated;
            }
            CloseHandle(hToken);
        }
        return false;
    }

    extern "C" void run_as_admin(const char* exePath) {
        ShellExecuteA(NULL, "runas", exePath, NULL, NULL, SW_SHOWNORMAL);
    }
')
#end

class FileUtils {
  public static function isUserAdmin():Bool {
    #if cpp
    return untyped __cpp__("is_user_elevated()");
    #else
    return false;
    #end
  }

  public static function requestAdmin():Void {
    #if cpp
    var exePath = Sys.executablePath();
    untyped __cpp__('run_as_admin({0}.c_str())', exePath);
    #end
  }
}

#end
