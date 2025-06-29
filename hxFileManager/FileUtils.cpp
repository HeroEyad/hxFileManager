#include <windows.h>
#include <shellapi.h>
#include <iostream>
extern "C" {
    BOOL IsProcessElevated() {
        BOOL fIsElevated = FALSE;
        HANDLE hToken = NULL;
        TOKEN_ELEVATION elevation;
        DWORD dwSize;
    
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &hToken)) {
            // Handle error: Failed to get process token
            return FALSE;
        }
    
        if (!GetTokenInformation(hToken, TokenElevation, &elevation, sizeof(elevation), &dwSize)) {
            // Handle error: Failed to get token information
            CloseHandle(hToken);
            return FALSE;
        }
    
        fIsElevated = elevation.TokenIsElevated;
    
        CloseHandle(hToken);
        return fIsElevated;
    }
}
