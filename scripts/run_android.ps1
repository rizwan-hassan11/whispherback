# Run WhisperBack on a connected Android phone or emulator with hot reload.
# Usage (repo root):
#   .\scripts\run_android.ps1              # pick first Android device
#   .\scripts\run_android.ps1 -ListDevices
#   .\scripts\run_android.ps1 -DeviceId abc123
param(
  [string]$DeviceId = "",
  [switch]$ListDevices,
  [switch]$Release
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$mobile = Join-Path $repoRoot 'mobile'

if (-not $env:JAVA_HOME) {
  $jdk = Get-ChildItem 'C:\Program Files\Microsoft\jdk-17*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
  if ($jdk) {
    $env:JAVA_HOME = $jdk.FullName
    $env:PATH = "$($jdk.FullName)\bin;$env:PATH"
  }
}

Push-Location $mobile
flutter pub get

if ($ListDevices) {
  Write-Host 'Available devices:' -ForegroundColor Cyan
  flutter devices
  Pop-Location
  exit 0
}

if ($DeviceId -eq '') {
  $lines = flutter devices 2>&1 | Out-String
  $android = [regex]::Matches($lines, '(?m)^\s+\S+\s+•\s+(\S+)\s+•\s+android') | ForEach-Object { $_.Groups[1].Value }
  if ($android.Count -eq 0) {
    Pop-Location
    Write-Error @"
No Android device found.

1. Phone: Settings → Developer options → USB debugging ON
2. Connect USB, accept the trust prompt on the phone
3. Run: adb devices   (should list your phone)
4. Or start an emulator in Android Studio → Device Manager

Then: .\scripts\run_android.ps1 -ListDevices
"@
  }
  $DeviceId = $android[0]
  Write-Host "Using device: $DeviceId" -ForegroundColor Green
}

$mode = if ($Release) { '--release' } else { '--debug' }
Write-Host ''
Write-Host 'Hot reload: press r  |  Hot restart: R  |  Quit: q' -ForegroundColor Cyan
Write-Host ''

flutter run -d $DeviceId $mode --dart-define=FLAVOR=dev
Pop-Location
