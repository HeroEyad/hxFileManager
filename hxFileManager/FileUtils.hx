package hxFileManager;

@:headerCode('
    #include <windows.h>

    extern "C" bool is_user_admin();
')

@:cppFileCode('
    extern "C" bool is_user_admin() {
        BOOL fIsElevated = FALSE;
        HANDLE hToken = NULL;
        TOKEN_ELEVATION elevation;
        DWORD dwSize;

        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &hToken)) {
            return false;
        }

        if (!GetTokenInformation(hToken, TokenElevation, &elevation, sizeof(elevation), &dwSize)) {
            CloseHandle(hToken);
            return false;
        }

        fIsElevated = elevation.TokenIsElevated;
        CloseHandle(hToken);
        return fIsElevated ? true : false;
    }
')

extern class FileUtils {
    @:native("is_user_admin")
    public static function isUserAdmin():Bool;
}

