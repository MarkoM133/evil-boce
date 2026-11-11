@echo off
rem Starts the game from the source (game/), the version being worked on; godot must be on PATH.
start "" godot --path "%~dp0..\game"
