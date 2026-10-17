# ========================================================
#   V2RayPro Release Packaging Script
# ========================================================
$ErrorActionPreference = 'Stop'

$rootDir = $PSScriptRoot
if (-not $rootDir) {
    $rootDir = Get-Location
}

# 1. Locate and parse version from version.ini
$iniPath = $null
$candidateInis = @(
    (Join-Path $rootDir "build\windows\version.ini"),
    (Join-Path $rootDir "version.ini")
)

foreach ($c in $candidateInis) {
    if (Test-Path $c) {
        $iniPath = $c
        break
    }
}

$version = $null
if ($iniPath) {
    Write-Host "[*] Reading version from $iniPath..." -ForegroundColor Cyan
    Get-Content $iniPath | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^version\s*=\s*(.+)$') {
            $version = $matches[1].Trim().Trim('"').Trim("'")
        }
    }
}

if (-not $version) {
    $version = "1.4.0"
    Write-Host "[!] Version not found in ini file. Defaulting to: $version" -ForegroundColor Yellow
} else {
    Write-Host "[+] Target release version: $version" -ForegroundColor Green
}

# 2. Source directories
$srcDir = Join-Path $rootDir "build\windows"
if (-not (Test-Path $srcDir)) {
    throw "Source directory '$srcDir' does not exist. Please run flutter build windows first."
}

# Sync latest build if runner Release folder is newer
$flutterRunnerRelease = Join-Path $rootDir "flutter\build\windows\x64\runner\Release"
if (Test-Path (Join-Path $flutterRunnerRelease "v2raypro.exe")) {
    Write-Host "[*] Syncing latest compiled runner binaries..." -ForegroundColor Cyan
    Copy-Item -Path "$flutterRunnerRelease\*" -Destination $srcDir -Recurse -Force
}

# Ensure dedicated subdirectories (xray/)
$xrayDir = Join-Path $srcDir "xray"
if (-not (Test-Path $xrayDir)) {
    New-Item -ItemType Directory -Force -Path $xrayDir | Out-Null
}
$xrayFiles = @('xray.exe', 'wintun.dll', 'geoip.dat', 'geosite.dat')
foreach ($item in $xrayFiles) {
    $srcItem = Join-Path $srcDir $item
    if (Test-Path $srcItem) {
        Move-Item -Path $srcItem -Destination (Join-Path $xrayDir $item) -Force
    }
}

# Ensure app_icon.png exists in data assets
$flutterAssetIcon = Join-Path $rootDir "flutter\assets\app_icon.png"
$destAssetIcon = Join-Path $srcDir "data\flutter_assets\assets\app_icon.png"
if (Test-Path $flutterAssetIcon) {
    $destAssetDir = Split-Path $destAssetIcon -Parent
    if (-not (Test-Path $destAssetDir)) {
        New-Item -ItemType Directory -Force -Path $destAssetDir | Out-Null
    }
    Copy-Item -Path $flutterAssetIcon -Destination $destAssetIcon -Force
}

# 3. Create staging directory with root 'v2raypro' folder
$staging = Join-Path $rootDir "dist\staging"
$packageDir = Join-Path $staging "v2raypro"

if (Test-Path $staging) {
    Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $packageDir | Out-Null

Write-Host "[*] Staging release files into '$packageDir'..." -ForegroundColor Cyan
Copy-Item -Path "$srcDir\*" -Destination $packageDir -Recurse -Force

# 4. EXCLUDE user configs and subscriptions so existing user configs are never overwritten
Write-Host "[*] Purging user data and subscription configs from release package..." -ForegroundColor Cyan

# Remove config folder & files if present
$stageConfigDir = Join-Path $packageDir "config"
if (Test-Path $stageConfigDir) {
    Remove-Item -Recurse -Force $stageConfigDir -ErrorAction SilentlyContinue
}

# Remove any root user data or test json/log files
$sensitiveFiles = @(
    'v2raypro_nodes.json',
    'v2raypro_subs.json',
    'v2raypro_free_configs.json',
    'v2raypro_cf_ranges.json',
    'v2raypro_active_config.json',
    'test_tun.json',
    'test_generated_tun.json'
)
foreach ($f in $sensitiveFiles) {
    $target = Join-Path $packageDir $f
    if (Test-Path $target) {
        Remove-Item -Force $target -ErrorAction SilentlyContinue
    }
}

# Remove logs
Get-ChildItem -Path $packageDir -Filter "*.log" -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -Force $_.FullName -ErrorAction SilentlyContinue
}

# Ensure version.ini is inside the release package
$pkgIni = Join-Path $packageDir "version.ini"
if (-not (Test-Path $pkgIni) -and $iniPath) {
    Copy-Item -Path $iniPath -Destination $pkgIni -Force
}

# 5. Output zip package
$zipFileName = "v2raypro-windows-$version.zip"
$zipPath = Join-Path $rootDir $zipFileName

if (Test-Path $zipPath) {
    Write-Host "[*] Removing previous archive '$zipFileName'..." -ForegroundColor Cyan
    try {
        Remove-Item -Force $zipPath -ErrorAction Stop
    } catch {
        Write-Host "[!] Warning: $zipFileName is locked (possibly by OneDrive or Explorer). Trying fallback name..." -ForegroundColor Yellow
        $zipFileName = "v2raypro-windows-$version-new.zip"
        $zipPath = Join-Path $rootDir $zipFileName
        if (Test-Path $zipPath) {
            Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "[*] Compressing release package to '$zipFileName'..." -ForegroundColor Cyan
Compress-Archive -Path $packageDir -DestinationPath $zipPath -CompressionLevel Optimal

# 6. Clean up staging folder
Remove-Item -Recurse -Force $staging -ErrorAction SilentlyContinue

# 7. Verification
if (Test-Path $zipPath) {
    $zipItem = Get-Item $zipPath
    $sizeMb = [math]::Round($zipItem.Length / 1MB, 2)
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host "  RELEASE CREATED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "========================================================" -ForegroundColor Green
    Write-Host "  File Name : $($zipItem.Name)" -ForegroundColor White
    Write-Host "  File Path : $($zipItem.FullName)" -ForegroundColor White
    Write-Host "  File Size : $sizeMb MB" -ForegroundColor White
    Write-Host "  Version   : $version" -ForegroundColor White
    Write-Host "  Contents  : Root folder 'v2raypro/' (configs & subs excluded)" -ForegroundColor White
    Write-Host "========================================================" -ForegroundColor Green
} else {
    throw "Failed to create archive at $zipPath"
}
