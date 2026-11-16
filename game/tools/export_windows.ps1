# Builds game/build/EvilBoce.exe (single exe, data stays in the shared folder).
# The exe icon comes from <data folder>/data/branding/evil-boce.ico; it is copied into
# game/.branding/ (git-ignored) because the logo must not go into the public repo.
#   powershell -File game/tools/export_windows.ps1 [-Data <shared folder>] [-Debug] [-Publish [-Force]]
# -Publish also copies the exe to <shared folder>/game/<version>/ and points
# <shared folder>/game/Evil Boce.cmd at it, so Syncthing hands it to the other players. The
# .cmd starts the game with the shared folder it sits in, wherever that is on their computer.
# It keeps the new build and the one before it; older version folders go to the Recycle Bin.
# An existing version folder is never overwritten without -Force (raise config/version in
# project.godot instead: online play checks that both sides run the same version).
param(
    [string]$Data = "$env:USERPROFILE\Documents\Other\TTS_Custom\EvilBoce",
    [switch]$Debug,
    [switch]$Publish,
    [switch]$Force
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
# Godot: $env:GODOT if set, else godot_console / godot on PATH.
$godot = $env:GODOT
if (-not $godot) { $godot = (Get-Command godot_console -ErrorAction SilentlyContinue).Source }
if (-not $godot) { $godot = (Get-Command godot -ErrorAction Stop).Source }
$mode = if ($Debug) { "--export-debug" } else { "--export-release" }
& $godot --headless --path $game $mode "Windows Desktop" "build/EvilBoce.exe"
if ($LASTEXITCODE -ne 0) { throw "Export failed ($LASTEXITCODE)" }
$exe = Join-Path $game "build\EvilBoce.exe"
Write-Host "Built $exe"

if ($Publish) {
    $line = Select-String -Path (Join-Path $game "project.godot") -Pattern '^config/version="(.+)"' | Select-Object -First 1
    if (-not $line) { throw "No config/version in project.godot" }
    $version = $line.Matches[0].Groups[1].Value
    $dest = Join-Path $Data "game\$version"
    if ((Test-Path (Join-Path $dest "EvilBoce.exe")) -and -not $Force) {
        throw "$dest already has a build; raise config/version or pass -Force"
    }
    New-Item -ItemType Directory -Force $dest | Out-Null
    Copy-Item $exe (Join-Path $dest "EvilBoce.exe") -Force
    $cmd = @"
@echo off
rem Starts Evil Boce $version with the shared folder this file sits in.
for %%I in ("%~dp0..") do set "EB_DATA=%%~fI"
start "" "%~dp0$version\EvilBoce.exe" -- --data="%EB_DATA%"
"@
    Set-Content -Path (Join-Path $Data "game\Evil Boce.cmd") -Value $cmd -Encoding ascii
    Write-Host "Published $version to $dest (and game\Evil Boce.cmd)"
    # Old builds (Marko 2026-11-16): the new one and the one before it stay (a fallback if the new one
    # misbehaves); older version folders go to the Recycle Bin, so Syncthing drops them for everyone.
    $versions = Get-ChildItem (Join-Path $Data "game") -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' -and (Test-Path (Join-Path $_.FullName "EvilBoce.exe")) } |
        Sort-Object { [version]$_.Name } -Descending
    $old = $versions | Where-Object { [version]$_.Name -lt [version]$version } | Select-Object -Skip 1
    if ($old) {
        Add-Type -AssemblyName Microsoft.VisualBasic
        foreach ($o in $old) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($o.FullName, 'OnlyErrorDialogs', 'SendToRecycleBin')
            Write-Host "Old build $($o.Name) went to the Recycle Bin"
        }
    }
}
