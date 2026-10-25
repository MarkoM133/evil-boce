# Evil Boće – game (Godot)

- This folder is the Godot 4.x game (GDScript, Windows). It replaces the Tabletop Simulator mod.
- **TTS is deprecated.** Ignore TTS code, docs and terms (Lua, steam-urls, baked textures, Bakugan OBJ shapes) unless a task explicitly says otherwise. Do not port TTS logic; the rules come from the design doc.
- Source of truth: `docs/private/Evil Boce - dizajn igre.md` (GDD) and `docs/private/Evil Boce - handoff igra (Claude Code).md`. Both are private and gitignored, so never copy their contents into committed files.
- Game data (cards.json, sprites, figures, audio, branding) lives in the Syncthing folder, never in git. Its path is a game setting.
- `rules/` is pure logic with tests; no scene or Node code there.
- Unclear rule → write it into `game/docs/pitanja.md` and ask Marko; do not invent rules.
- Code and commits in English; talk to Marko in Croatian, briefly.
- Build, tests and tools: `game/docs/BUILD.md`. Hex conventions: `game/docs/hex.md`. Ids of slots, heroes, cores and stages: `game/docs/ids.md`. Physics numbers only in `game/sim/physics_tuning.tres`.
- The sim only reports facts (`RollResult`, gathered per Roll into `RollOutcome` by `RollRunner`); it never decides rules. Terrain is data (`TerrainMap`) owned by whoever runs the game; the arena only draws it.
