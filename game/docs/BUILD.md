# Build and run

Godot **4.5** (Jolt physics, GDScript). On Windows use `godot_console` for anything that
prints (tests, tools); `godot` opens the editor. Commands below run from the repo root.

## Data folder

The game reads cards, sprites and branding straight from the shared Syncthing folder
(the one that holds `data/cards.json`). Default:
`%USERPROFILE%\Documents\Other\TTS_Custom\EvilBoce`.

- Override for one run: `godot -- --data=D:/path/to/EvilBoce`
- Override for good: main menu → Settings → Shared folder, stored as `[data] path` (next to
  the display, sound and key settings) in
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

GUT settings are in `game/.gutconfig.json` (tests in `game/tests/`, `test_*.gd`). Rules
scenarios live in `game/tests/scenarios/*.json` (format in `rules.md`).

GUT does not report parse errors in scripts the tests never load (and warnings are errors in
this project), so after touching scene or tool scripts also run:

```
godot_console --headless --path game -s res://tools/check_scripts.gd
```

## Tools

- **Online smoke test** (headless; host, guest and the match scene in both roles over
  127.0.0.1): `godot_console --headless --path game -s res://tools/net_smoke.gd`

- **Throw ranges** (headless, prints a table):
  `godot_console --headless --path game --fixed-fps 120 -s res://tools/measure_throws.gd`
  Physics numbers live in `game/sim/physics_tuning.tres`.
- **Screenshot** (needs a window; saves to `game/.shots/`):
  `godot_console --path game -s res://tools/screenshot.gd -- --scene=res://scenes/sandbox/sandbox.tscn --call=demo_setup,demo_closeup --out=closeup.png`
  Sandbox helpers for `--call`: `demo_setup`, `demo_closeup`, `demo_aim`, `demo_throw`,
  `demo_ringout`, `demo_strip`, `demo_big`, `debug_dump`. Use `--wait=240` or more after a
  throw so the roll has finished before the next call.
  Match helpers (`--scene=res://scenes/match/match.tscn`, random decks, bot as player 2):
  `demo_step` (one local move as if clicked; at the aim it draws the slingshot and stops),
  `demo_autoplay` (bots play both sides; give it `--wait=3600` for about a minute),
  `debug_dump` (turn, phase, heroes, last log lines).

## Match

Main menu → Play → pick decks (saved decks from `decks/` in the shared folder, or random),
player 2 (bot Easy / Hard or a second local player) and the map. The match scene
(`scenes/match/`) only draws the `GameState`, turns clicks into moves and runs the physics for
the Roll phase; the rules are in `rules/` (see `rules.md`). `bot/bot.gd` is the bot.
"Online…" opens the lobby (`scenes/net/`): host on port 7777 or join a Tailscale address;
protocol and roles in `net.md`.

## Windows build

```
powershell -File game/tools/export_windows.ps1            # release
powershell -File game/tools/export_windows.ps1 -Debug     # with console wrapper
powershell -File game/tools/export_windows.ps1 -Publish   # also hand it out through Syncthing
```

Godot comes from `$env:GODOT` if set, else `godot_console` / `godot` on PATH.

`-Publish` copies the exe to `<shared folder>/game/<version>/EvilBoce.exe` (version =
`config/version` in `project.godot`) and rewrites `<shared folder>/game/Evil Boce.cmd`, which
starts that version with the shared folder it sits in (`-- --data=...`), so the other player
needs no settings. An existing version folder is kept unless `-Force`; raise the version
instead, because online play refuses a guest whose game version differs from the host's.

Output: `game/build/EvilBoce.exe` (one file, data stays in the shared folder). The script
copies `data/branding/evil-boce.ico` into `game/.branding/` for the exe icon; both
folders are git-ignored. Export templates 4.5.2 must be installed
(Editor → Manage Export Templates).

## fx report for the web app

After every Publish of cards, refresh the report the web app's Effect tab reads:

```
godot_console --headless --path game -s res://tools/fx_proposals.gd
```

It writes `data/fx-proposals.json` into the shared folder: per card, what the game reads from the
text, the sentences it does not understand, a proposed fx (the line from
`game/data/placeholders/card_fx.json` when there is one) and errors in an existing `fx`.
Cards whose fx Marko confirmed carry it in `cards.json`; the placeholder line is then ignored.
