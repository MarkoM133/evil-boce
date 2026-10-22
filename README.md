# Evil Boće – karte

Web app za bazu karata igre Evil Boće: uvoz Card Engine exporta u `cards.json`, pregled karata i app polja. Deck builder i katalog dolaze kasnije.

Repo ima samo kod. Karte, slike i pravila nisu ovdje; app radi nad zajedničkim Drive folderom koji odabereš u pregledniku.

## Pokretanje

Statična stranica bez builda (GitHub Pages ili bilo koji lokalni server), u Chromeu ili Edgeu (File System Access API).

```
npx serve .        # ili bilo koji statični server
```

Otvori stranicu, odaberi folder `Evil Boce/` (s `export/` i `data/`), pa **Uvezi** i **Objavi**.

## Folder

```
Evil Boce/
  export/            Card Engine exporti: XML-ovi bilo kojeg imena + PNG po karti (ime PNG-a = ime karte)
  data/cards.json    baza karata (piše je app)
  data/images/       slike, ID.hash.png
```

## Testovi

```
npm test
```
