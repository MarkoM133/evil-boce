# Builds game/build/EvilBoce.exe (single exe, data stays in the shared folder).
# The exe icon comes from <data folder>/data/branding/evil-boce.ico; it is copied into
# game/.branding/ (git-ignored) because the logo must not go into the public repo.
#   powershell -File game/tools/export_windows.ps1 [-Data <shared folder>] [-Debug]
param(
    [string]$Data = "$env:USERPROFILE\Documents\Other\TTS_Custom\EvilBoce",
    [switch]$Debug
)
$ErrorActionPreference = "Stop"
$game = Split-Path -Parent $PSScriptRoot
$ico = Join-Path $Data "data\branding\evil-boce.ico"
$brand = Join-Path $game ".branding"
New-Item -ItemType Directory -Force $brand | Out-Null
if (Test-Path $ico) {
    Copy-Item $ico (Join-Path $brand "evil-boce.ico") -Force
} else {
    Write-Warning "No icon at $ico; the exe gets the default icon."
}
New-Item -ItemType Directory -Force (Join-Path $game "build") | Out-Null
$godot = (Get-Command godot_console -ErrorAction SilentlyContinue).Source
if (-not $godot) { $godot = (Get-Command godot -ErrorAction Stop).Source }
$mode = if ($Debug) { "--export-debug" } else { "--export-release" }
& $godot --headless --path $game $mode "Windows Desktop" "build/EvilBoce.exe"
if ($LASTEXITCODE -ne 0) { throw "Export failed ($LASTEXITCODE)" }
Write-Host "Built $(Join-Path $game 'build\EvilBoce.exe')"
