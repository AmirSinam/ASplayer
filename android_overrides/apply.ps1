# Copies the two Android files that `flutter create` overwrites.
# Run from the asplayer directory, every time after `flutter create`.
#
# Keep this file ASCII-only: Windows PowerShell 5.1 reads scripts as ANSI and
# mangles UTF-8 text, which breaks parsing.

$ErrorActionPreference = "Stop"

if (-not (Test-Path "android")) {
    Write-Error "No android/ folder. Run this first: flutter create --org ir.aspoormehr --project-name asplayer --platforms=android,ios ."
}

$activityDir = "android\app\src\main\kotlin\ir\aspoormehr\asplayer"

Copy-Item "android_overrides\AndroidManifest.xml" "android\app\src\main\AndroidManifest.xml" -Force
New-Item -ItemType Directory -Force $activityDir | Out-Null
Copy-Item "android_overrides\MainActivity.kt" "$activityDir\MainActivity.kt" -Force

Write-Host "Android overrides applied."
