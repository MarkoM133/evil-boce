# Evil Boće

- Igra je u `game/` (Godot 4.5, vidi `game/CLAUDE.md`). Web app je studio za karte: uvoz i objava karata, pregled (kartice Effect i Look), deck builder.
- Nakon svake Objave karata pokreni `godot_console --headless --path game -s res://tools/fx_proposals.gd`: osvježi `data/fx-proposals.json` za karticu Effect (GDD 14: Claude predlaže fx, Marko potvrđuje).
- **Claude prijedlozi fx-a** (`server/fx-claude.mjs`, ključ samo u `server/config.local.json` kao `anthropicApiKey`): Card Studio piše zahtjeve u `data/fx-requests/` zajedničkog foldera, odgovori idu u `data/fx-claude/`, a riječi koje fx jeziku fale u `data/fx-wishlist.json`. Gumb **Check text** ide istim putem (`data/text-requests/` → `data/text-claude/`): Claude čita tekst po vodiču za tekst iz `docs/private/` i pravilima Card Studija, predloži prijepis, a pitanja o značenju ostavi autoru.
- **"Napravi wishlist"**: za otvorene stavke vrste verb, condition i target ugradi riječ u igru (`game/rules/fx_effect.gd` i `fx_runtime.gd`), dopuni `game/docs/fx-keywords.md` i `js/fx-grammar.js` (ista gramatika), dodaj GUT scenarij i test u `test/fx-grammar.test.mjs`, pa stavci postavi `status: "done"`. Stavke vrste rule su pitanja za Marka (`game/docs/pitanja.md`), ne zadaci. To je posao za Fable.
- **Card Studio na mobitelu** radi preko servera na Markovom računalu: sve pisanje ide kroz `api/fs` (`server/fs-api.mjs`, popis dopuštenih putanja). Nova funkcija koja sprema u novu putanju mora tu dobiti svoje pravilo i test u `test/fs-api.test.mjs`. Publish i Import ostaju samo na računalu s otvorenim folderom. Nakon promjene servera ga restartaj (Scheduled Task "Evil Boce server").
- **Dizajnerski chat** (Claude u chatu, skill evil-boce-dizajn) čita tri datoteke u `docs/private/`. Nakon svake Objave i na kraju sesije: `npm run design-pack` osvježi `dizajn-paket.md` (karte i brojke za balans iz objavljene baze; sažetak pravila između oznaka RUCNO je ručni i mijenja se kad se pravilo promijeni) i ažuriraj `brief-za-chat.md` (verzija, novosti, otvorene odluke). Na početku sesije pročitaj `inbox-iz-chata.md`: dogovore provedi (karte kao nacrti, pravila u GDD) i premjesti ih pod Obrađeno.
- **Pravila za igrače** su `data/rules/rules.md` u zajedničkom folderu (engleski): igra ih pokazuje pod RULES u meniju pauze, Card Studio na stranici Rules. Kad se pravilo promijeni (GDD), ažuriraj i tu datoteku.
- Promjene karata koje mora napraviti autor karata idu u dokument s promjenama karata u `docs/private/`.
- Privatni docs su u `docs/private/` (gitignore): GDD, handoff igre, predev, plan karata, vodič za tekst karata. Stare stvari su u `docs/private/archive/`.
- Repo je javan: u git ide samo kod. Karte, slike, logo, pravila i Tailscale adrese ne idu.
- Podaci (karte, slike, spriteovi, deckovi, branding) su u zajedničkom Syncthing folderu; put je u `server/config.local.json` (`driveFolder`).
- Format deck koda: `docs/deck-code.md`.
- Testovi: `npm test`.
