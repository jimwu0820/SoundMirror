@echo off
title Build SoundMirror.exe
cd /d "%~dp0"

set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (
    echo [ERROR] C# compiler not found. .NET Framework 4 is required.
    pause
    exit /b 1
)

echo Building SoundMirror.exe ...
echo.

"%CSC%" /nologo /codepage:65001 /target:winexe /platform:anycpu /optimize+ /out:"%~dp0SoundMirror.exe" /win32icon:"%~dp0app.ico" /r:System.dll /r:System.Windows.Forms.dll /r:System.Drawing.dll "%~dp0src\SoundMirrorLauncher.cs"

if errorlevel 1 (
    echo.
    echo [FAILED] Compilation error. Please copy the message above.
    pause
    exit /b 1
)

echo.
echo [OK] SoundMirror.exe has been created next to this script.
echo.
pause
