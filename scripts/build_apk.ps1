# Builds a debug APK for sideloading on Android phones (testing).
# Requires Android SDK — run setup_android_sdk.ps1 first if flutter doctor shows no SDK.
param(
  [ValidateSet('debug', 'release')]
  [string]$Mode = 'debug',
  [switch]$SplitPerAbi
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$mobile = Join-Path $repoRoot 'mobile'

# JDK required by Android Gradle (winget: Microsoft.OpenJDK.17)
if (-not $env:JAVA_HOME) {
  $jdkCandidates = @(
    'C:\Program Files\Microsoft\jdk-17*',
    'C:\Program Files\Eclipse Adoptium\jdk-17*',
    'C:\Program Files\Java\jdk-17*'
  )
  foreach ($pattern in $jdkCandidates) {
    $found = Get-ChildItem $pattern -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($found) {
      $env:JAVA_HOME = $found.FullName
      $env:PATH = "$($found.FullName)\bin;$env:PATH"
      break
    }
  }
}
if (-not $env:JAVA_HOME) {
  Write-Error 'JAVA_HOME not set. Install JDK 17: winget install Microsoft.OpenJDK.17'
}

function Test-NdkInstall {
  param([string]$SdkRoot)
  $ndkRoot = Join-Path $SdkRoot 'ndk'
  if (-not (Test-Path $ndkRoot)) { return $false }
  foreach ($dir in Get-ChildItem $ndkRoot -Directory -ErrorAction SilentlyContinue) {
    if (Test-Path (Join-Path $dir.FullName 'source.properties')) { return $true }
  }
  return $false
}

function Repair-BrokenNdk {
  param([string]$SdkRoot)
  $ndkRoot = Join-Path $SdkRoot 'ndk'
  if (-not (Test-Path $ndkRoot)) { return }
  foreach ($dir in Get-ChildItem $ndkRoot -Directory -ErrorAction SilentlyContinue) {
    if (-not (Test-Path (Join-Path $dir.FullName 'source.properties'))) {
      Write-Host "Removing incomplete NDK: $($dir.Name)" -ForegroundColor Yellow
      Remove-Item $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

$sdkRoot = $env:ANDROID_HOME
if (-not $sdkRoot) { $sdkRoot = $env:ANDROID_SDK_ROOT }
if (-not $sdkRoot) { $sdkRoot = Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
$env:ANDROID_HOME = $sdkRoot
$env:ANDROID_SDK_ROOT = $sdkRoot

Repair-BrokenNdk -SdkRoot $sdkRoot
if (-not (Test-NdkInstall -SdkRoot $sdkRoot)) {
  Write-Host ''
  Write-Host 'Android NDK not installed (required once, ~500 MB download).' -ForegroundColor Yellow
  Write-Host 'Gradle will try to download it during the build — keep Wi-Fi stable and wait 10-20 min.' -ForegroundColor Yellow
  Write-Host 'If download keeps failing, run: .\scripts\install_ndk.ps1' -ForegroundColor Yellow
  Write-Host 'Or download APK from GitHub Actions (see docs/APK_TESTING.md).' -ForegroundColor Yellow
  Write-Host ''
}

Push-Location $mobile

Write-Host 'Checking Flutter...' -ForegroundColor Cyan
flutter pub get

$doctor = flutter doctor -v 2>&1 | Out-String
if ($doctor -match 'Android toolchain.*\[X\]') {
  Write-Host ''
  Write-Error @"
Android SDK not found. Install it first (one-time, ~1-2 GB):

  .\scripts\setup_android_sdk.ps1

Or install Android Studio from https://developer.android.com/studio
Then run: flutter doctor --android-licenses
"@
}

Write-Host "Building APK ($Mode)..." -ForegroundColor Cyan
$buildArgs = @('build', 'apk', '--dart-define=FLAVOR=dev')
if ($Mode -eq 'debug') {
  $buildArgs = @('build', 'apk', '--debug', '--dart-define=FLAVOR=dev')
} else {
  $buildArgs = @('build', 'apk', '--release', '--dart-define=FLAVOR=dev')
  if ($SplitPerAbi) { $buildArgs += '--split-per-abi' }
}
flutter @buildArgs
if ($Mode -eq 'debug') {
  $apk = Join-Path $mobile 'build\app\outputs\flutter-apk\app-debug.apk'
} elseif ($SplitPerAbi) {
  $apk = Join-Path $mobile 'build\app\outputs\flutter-apk\app-arm64-v8a-release.apk'
  if (-not (Test-Path $apk)) {
    $apk = Get-ChildItem (Join-Path $mobile 'build\app\outputs\flutter-apk\app-*-release.apk') |
      Sort-Object Length | Select-Object -First 1 -ExpandProperty FullName
  }
} else {
  $apk = Join-Path $mobile 'build\app\outputs\flutter-apk\app-release.apk'
}

Pop-Location

if (-not (Test-Path $apk)) {
  throw "APK not found at $apk"
}

$destDir = Join-Path $repoRoot 'dist'
New-Item -ItemType Directory -Force -Path $destDir | Out-Null
$dest = Join-Path $destDir 'whisperback-test.apk'
Copy-Item $apk $dest -Force

Write-Host ''
Write-Host 'APK ready!' -ForegroundColor Green
Write-Host "  $dest"
if ($Mode -eq 'debug') {
  Write-Host ''
  Write-Host 'Note: Debug APKs are ~150-200 MB (fat binary). For smaller client builds:' -ForegroundColor Yellow
  Write-Host '  .\scripts\build_apk.ps1 -Mode release -SplitPerAbi'
}
Write-Host ''
Write-Host 'Install on your phone:' -ForegroundColor Cyan
Write-Host '  1. Copy whisperback-test.apk to your phone (USB, email, or cloud)'
Write-Host '  2. Enable Install from unknown sources for your file app'
Write-Host '  3. Tap the APK to install'
Write-Host ''
Write-Host 'Or with USB debugging:' -ForegroundColor Cyan
Write-Host "  adb install -r `"$dest`""
