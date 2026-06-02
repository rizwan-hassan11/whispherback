# WhisperBack mobile — first-time / new-machine setup (Windows PowerShell).
# Usage: from repo root:  .\scripts\setup_mobile.ps1
param(
  [string]$FlutterExe = "",
  [switch]$SkipAndroidCheck
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent
$mobile = Join-Path $repoRoot "mobile"

function Resolve-Flutter {
  if ($FlutterExe -ne "" -and (Test-Path $FlutterExe)) { return $FlutterExe }
  $cmd = Get-Command flutter -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $default = Join-Path $env:LOCALAPPDATA "flutter-sdk\bin\flutter.bat"
  if (Test-Path $default) { return $default }
  throw "Flutter not found. Install from https://docs.flutter.dev/get-started/install/windows then re-run."
}

$flutter = Resolve-Flutter
Write-Host "Using Flutter: $flutter" -ForegroundColor Cyan

Push-Location $mobile

if (-not (Test-Path "android")) {
  Write-Host "Creating platform folders (android, ios, windows, ...)" -ForegroundColor Yellow
  & $flutter create . --project-name whisperback --org com.whisperback
}

Write-Host "Fetching packages..." -ForegroundColor Cyan
& $flutter pub get

Write-Host "Running analyzer..." -ForegroundColor Cyan
& $flutter analyze
if ($LASTEXITCODE -ne 0) {
  Write-Warning "Analyzer reported issues (warnings/infos). Fix errors before release."
}

Write-Host "Running unit tests..." -ForegroundColor Cyan
& $flutter test
if ($LASTEXITCODE -ne 0) { throw "Unit tests failed." }

Pop-Location

Write-Host ""
Write-Host "Mobile setup complete." -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. flutter doctor -v   (install Android Studio if Android toolchain shows X)"
Write-Host "  2. cd mobile"
Write-Host "  3. flutter run -d windows          (no Android SDK required)"
Write-Host "     .\scripts\run_android.ps1       (phone USB + hot reload — see docs/LOCAL_DEVELOPMENT.md)"
Write-Host "     flutter run -d <device>       (phone/emulator after Android Studio)"
Write-Host ""
Write-Host "Full guide: docs/INSTALLATION.md"

if (-not $SkipAndroidCheck) {
  $doctor = & $flutter doctor 2>&1 | Out-String
  if ($doctor -match "Android toolchain.*\[X\]") {
    Write-Host ""
    Write-Warning "Android SDK not configured. Install Android Studio and run SDK Manager + flutter doctor --android-licenses"
    Write-Host "See docs/INSTALLATION.md section 4 (Android)."
  }
}
