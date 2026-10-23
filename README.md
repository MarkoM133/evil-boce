# Evil Boće – karte i deckovi

Web app za igru Evil Boće: uvoz Card Engine exporta u `cards.json`, pregled karata i deck builder (3 heroja, 40 karata, random deck, deck kod).

Repo ima samo kod. Karte, slike, logo i pravila nisu ovdje; app radi nad zajedničkim Drive folderom.

App: https://markom133.github.io/evil-boce/

## Dva načina rada

- **Folder (računalo, Chrome ili Edge):** otvori stranicu (gornji link ili lokalni server) i odaberi Drive folder `Evil Boce/`. Sve radi: Uvoz, Objava, Pregled, Deckovi.
- **Preko servera (npr. mobitel):** lokalni server na računalu poslužuje app, karte i deckove. App ga sam prepozna; tu su Pregled i Deckovi, bez Uvoza.

## Lokalni server

```
npm start          # http://localhost:5100/
```

Postavke u `server/config.local.json` (nije u gitu):

```json
{
  "driveFolder": "G:/My Drive/Evil Boce",
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
  data/images/       slike, ID.hash.png (original, za TTS)
  data/thumbs/       sličice 300 px, data/large/ velike slike 1000 px (JPEG, radi ih Objavi)
  data/changelog.json povijest promjena po verziji baze (piše je app)
  decks/             deckovi, ime-decka.json
  logo.jpg           logo (po želji)
```

## TTS (Tabletop Simulator)

Global skripta je `tts/global.lua`. Raspored stola (bazni save) je privatan i nije u repou.

```
npm run tts                 # bazni save + tts/global.lua -> "Evil Boce (dev).json" u TTS Saves
npm run tts -- --adopt      # save spremljen u TTS-u postaje nova baza
npm run tts -- --force      # prepiši save u TTS-u
```

Build ne prepisuje save koji je spremljen u TTS-u nakon zadnjeg builda; tada traži `--adopt` ili `--force`.

## Testovi

```
npm test
```
