# Evil Boće – karte i deckovi

Web app za igru Evil Boće: uvoz Card Engine exporta u `cards.json`, pregled karata i deck builder (3 heroja, 40 karata, random deck, deck kod). Igra je u `game/` (Godot 4.5).

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
  data/bakugani/     biblioteka oblika bakugana: catalog.json, 3D model (.obj), siva tekstura (.jpg), sličica (.png)
  data/figures/      3D figure heroja (.glb), za igru
  data/audio/        zvukovi, za igru
  data/branding/     logo i ikona igre
  decks/             deckovi, ime-decka.json
  stats/             statistika partija (igra)
  game/              buildovi igre po verziji
  replays-shared/    replayevi koje host podijeli
  logo.jpg           logo (po želji)
```

## TTS (otpisan)

TTS mod se više ne razvija; zamjenjuje ga igra u `game/`. Kod u `tts/` i TTS dijelovi appa ostaju dok ih igra ne zamijeni.

## Testovi

```
npm test
```
