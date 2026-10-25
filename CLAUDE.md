# Evil Boće

- **TTS je otpisan i obrisan (10/2026).** Igra je u `game/` (Godot 4.5, vidi `game/CLAUDE.md`). Web app je studio za karte: uvoz i objava karata, pregled (kartice Effect i Look), deck builder.
- Nakon svake Objave karata pokreni `godot_console --headless --path game -s res://tools/fx_proposals.gd`: osvježi `data/fx-proposals.json` za karticu Effect (GDD 14: Claude predlaže fx, Marko potvrđuje).
- Promjene karata koje mora napraviti autor karata idu u dokument s promjenama karata u `docs/private/`.
- Privatni docs su u `docs/private/` (gitignore): GDD, handoff igre, predev, plan karata, vodič za tekst karata. Stare stvari su u `docs/private/archive/`.
- Repo je javan: u git ide samo kod. Karte, slike, logo, pravila i Tailscale adrese ne idu.
- Podaci (karte, slike, spriteovi, deckovi, branding) su u zajedničkom Syncthing folderu; put je u `server/config.local.json` (`driveFolder`).
- Format deck koda: `docs/deck-code.md`.
- Testovi: `npm test`.
