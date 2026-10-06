# Release Build Instructions for Windows and Android

This directory (`build/`) is structured to receive the compiled output binaries for Windows and Android.

## Target Output Locations:
- **Windows Executable**: `build/windows/v2raypro.exe` (with dependencies `flutter_windows.dll`, `data/`, `v2raypro_core.dll`, `xray.exe`)
- **Android APK**: `build/android/app-release.apk` (and `app-release.aab`)

---

## 1. Automated Build Scripts

### Windows Release Build:
Run from the root or `flutter/` directory:
```powershell
cd flutter
flutter pub get
flutter build windows --release
Copy-Item -Path "build\windows\x64\runner\Release\*" -Destination "..\build\windows\" -Recurse -Force
```

### Android Release APK Build:
Run from the `flutter/` directory:
```powershell
cd flutter
flutter pub get
flutter build apk --release
Copy-Item -Path "build\app\outputs\flutter-apk\app-release.apk" -Destination "..\build\android\" -Force
```

### Android App Bundle (AAB):
```powershell
cd flutter
flutter build appbundle --release
Copy-Item -Path "build\app\outputs\bundle\release\app-release.aab" -Destination "..\build\android\" -Force
```

---

## 2. Requirements & Environment Setup
If Flutter / Rust are not yet registered in your global `PATH`, ensure:
1. **Flutter SDK**: Extract Flutter to `C:\flutter` and add `C:\flutter\bin` to User `PATH`.
2. **Android SDK / Studio**: Configure `ANDROID_HOME` or Android Command Line Tools with NDK.
3. **Visual Studio C++ Build Tools**: Required for Windows Desktop runner and Rust compilation.
