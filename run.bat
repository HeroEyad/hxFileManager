@echo off
setlocal

set ZIP_NAME=hxFileManager.zip

if exist %ZIP_NAME% del %ZIP_NAME%

echo Creating ZIP for hxFileManager: %ZIP_NAME%
powershell -Command "Compress-Archive -Path * -DestinationPath %ZIP_NAME%"

echo Installing to haxelib...
haxelib install %ZIP_NAME% --skip-dependencies
if exist %ZIP_NAME% del %ZIP_NAME%