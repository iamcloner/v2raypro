# Automated Build Script for V2Ray Pro
$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Building V2Ray Pro for Windows & Android " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check Flutter
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter SDK not found in PATH. Please install Flutter or add it to PATH."
}

# 1. Windows Build
Write-Host "`n[1/2] Building Windows Release..." -ForegroundColor Yellow
Set-Location -Path "$PSScriptRoot\..\flutter"
flutter pub get
flutter build windows --release

$winSource = "$PSScriptRoot\..\flutter\build\windows\x64\runner\Release\*"
$winDest = "$PSScriptRoot\windows"
Copy-Item -Path $winSource -Destination $winDest -Recurse -Force
Write-Host "? Windows release binary successfully generated in build/windows/" -ForegroundColor Green

# 2. Android Build
Write-Host "`n[2/2] Building Android Release APK..." -ForegroundColor Yellow
flutter build apk --release

$apkSource = "$PSScriptRoot\..\flutter\build\app\outputs\flutter-apk\app-release.apk"
$apkDest = "$PSScriptRoot\android\app-release.apk"
Copy-Item -Path $apkSource -Destination $apkDest -Force
Write-Host "? Android APK successfully generated in build/android/app-release.apk" -ForegroundColor Green

Write-Host "`nBuild complete! All outputs are organized in the build/ directory." -ForegroundColor Cyan
