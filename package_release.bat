@echo off
setlocal
cd /d "%~dp0"

echo ========================================================
echo   V2RayPro Windows Release Packager
echo ========================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0package_release.ps1"

echo.
pause
