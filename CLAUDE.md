# Evil Boće

- **TTS je otpisan (10/2026).** Igra je u `game/` (Godot 4.5, vidi `game/CLAUDE.md`). Web app je studio za karte: uvoz i objava karata, pregled, deck builder.
- TTS kod (`tts/`, `js/tts.js`, `/api/tts`, Sync, `steam-urls.json`) ostaje dok igra ne dođe do koraka 2, a onda se briše. Ne razvija se dalje.
- Privatni docs su u `docs/private/` (gitignore): GDD, handoff igre, predev, plan karata, vodič za tekst karata. Stare stvari su u `docs/private/archive/`.
- Repo je javan: u git ide samo kod. Karte, slike, logo, pravila i Tailscale adrese ne idu.
- Podaci (karte, slike, spriteovi, deckovi, branding) su u zajedničkom Syncthing folderu; put je u `server/config.local.json` (`driveFolder`).
- Format deck koda: `docs/deck-code.md`.
- Testovi: `npm test`.
