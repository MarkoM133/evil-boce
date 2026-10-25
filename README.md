# Evil Boće – karte i deckovi

Web app za igru Evil Boće: uvoz Card Engine exporta u `cards.json`, pregled karata (s karticama Effect i Look za igru) i deck builder (3 heroja, 40 karata, random deck, deck kod). Igra je u `game/` (Godot 4.5).

Repo ima samo kod. Karte, slike, logo i pravila nisu ovdje; app i igra rade nad zajedničkim Syncthing folderom.

App: https://markom133.github.io/evil-boce/

## Dva načina rada

- **Folder (računalo, Chrome ili Edge):** otvori stranicu (gornji link ili lokalni server) i odaberi zajednički folder. Sve radi: Uvoz, Objava, Pregled, Deckovi.
- **Preko servera (npr. mobitel):** lokalni server na računalu poslužuje app, karte i deckove. App ga sam prepozna; tu su Pregled i Deckovi, bez Uvoza.

## Lokalni server

```
npm start          # http://localhost:5100/
```

Postavke u `server/config.local.json` (nije u gitu):

```json
{
  "driveFolder": "C:/put/do/EvilBoce",
  "port": 5100,
  "hosts": ["127.0.0.1", "100.x.y.z"]
}
```

`hosts` su adrese na kojima server sluša (npr. Tailscale adresa računala za mobitel). Pokretanje s Windowsima: `powershell -ExecutionPolicy Bypass -File server\autostart.ps1` (ukloni s `-Remove`).

## Folder

```
Evil Boce/
  export/            sanduče za Card Engine exporte: XML-ovi bilo kojeg imena + PNG po karti ("OP1-012 Ime karte.png", stari oblik "Ime karte.png" i dalje radi)
  export/objavljeno/ nakon Objave app ovamo premjesti pročitane exporte (podfolder po datumu); Uvoz ga preskače
  data/cards.json    baza karata (piše je app)
  data/images/       slike, ID.hash.png (original)
  data/sprites/      spriteovi heroja i evolucija (figurina), ID.hash.png; u export/ kao "KOD Ime Sprite.png"
  data/thumbs/       sličice 300 px, data/large/ velike slike 1000 px (JPEG, radi ih Objavi)
  data/changelog.json povijest promjena po verziji baze (piše je app)
  data/fx-proposals.json kako igra čita tekst karata (piše ga game/tools/fx_proposals.gd), za karticu Effect
  data/figures/      3D figure heroja (.glb), možda kasnije; zasad su heroji 2D pixel art (spriteovi)
  data/audio/        zvukovi, za igru
  data/branding/     logo i ikona igre
  decks/             deckovi, ime-decka.json
  library/           izvorni art za spriteove (npr. one-piece-treasure-cruise/: spritesheetovi likova i efekata); igra ga ne čita izravno
  stats/             statistika partija (igra)
  game/              buildovi igre po verziji
  replays-shared/    replayevi koje host podijeli
  logo.jpg           logo (po želji)
```

## Kartice Effect i Look

- **Effect:** tekst karte, kako ga igra čita, što ne razumije i prijedlog `fx` (jezik efekata: `game/docs/fx-keywords.md`). **Confirm** sprema `fx` u kartu; prazan `fx` znači da igra čita tekst sama. Filter **Needs fx** pokazuje karte koje igra ne razumije, a nemaju potvrđen fx; **Check fx** one kojima se tekst promijenio nakon fx-a. Podatke daje izvještaj igre `data/fx-proposals.json`; nakon Objave ga osvježi: `godot_console --headless --path game -s res://tools/fx_proposals.gd`.
- **Look:** boja kuglice heroja (tijelo i akcent, u bojama igre), težina (WT) i figurina (sprite).

TTS mod je otpisan i njegov kod je obrisan (10/2026); igra je u `game/`.

## Testovi

```
npm test
```
