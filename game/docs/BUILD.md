# Build and run

Godot **4.5** (Jolt physics, GDScript). On Windows use `godot_console` for anything that
prints (tests, tools); `godot` opens the editor. Commands below run from the repo root.

## Data folder

The game reads cards, sprites and branding straight from the shared Syncthing folder
(the one that holds `data/cards.json`). Default:
`%USERPROFILE%\Documents\Other\TTS_Custom\EvilBoce`.

- Override for one run: `godot -- --data=D:/path/to/EvilBoce`
- Override for good: `[data] path="D:/path/to/EvilBoce"` in
  `%APPDATA%\EvilBoce\settings.cfg`.

The main menu footer shows which folder and `cards.json` version it found.

## Run

- Editor: `godot -e --path game`
- Game: `godot --path game`

## Tests

```
godot_console --headless --path game --import        # first time, or after adding classes
godot_console --headless --path game -s addons/gut/gut_cmdln.gd
```

GUT settings are in `game/.gutconfig.json` (tests in `game/tests/`, `test_*.gd`).

## Tools

- **Throw ranges** (headless, prints a table):
  `godot_console --headless --path game --fixed-fps 120 -s res://tools/measure_throws.gd`
  Physics numbers live in `game/sim/physics_tuning.tres`.
- **Screenshot** (needs a window; saves to `game/.shots/`):
  `godot_console --path game -s res://tools/screenshot.gd -- --scene=res://scenes/sandbox/sandbox.tscn --call=demo_setup,demo_closeup --out=closeup.png`
  Sandbox helpers for `--call`: `demo_setup`, `demo_closeup`, `demo_aim`, `demo_throw`,
  `demo_ringout`, `debug_dump`.

## Windows build

```
powershell -File game/tools/export_windows.ps1            # release
powershell -File game/tools/export_windows.ps1 -Debug     # with console wrapper
```

Output: `game/build/EvilBoce.exe` (one file, data stays in the shared folder). The script
copies `data/branding/evil-boce.ico` into `game/.branding/` for the exe icon; both
folders are git-ignored. Export templates 4.5.2 must be installed
(Editor → Manage Export Templates).
