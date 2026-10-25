# Deck kod

Deck kod je jedan redak teksta koji web app (deck builder) i igra razmjenjuju. Kod u appu: `encodeDeck` i `decodeDeck` u `js/deck.js`. Igra čita isti format; novi se ne izmišlja.

## Format

```
EB1|v<verzija>|<heroj>,<heroj>,<heroj>|<kod>*<broj>,<kod>*<broj>,...
```

Četiri dijela odvojena s `|`:

| # | Dio | Značenje |
|---|---|---|
| 1 | `EB1` | oznaka i verzija formata; drugačija oznaka znači da kod nije deck kod |
| 2 | `v<N>` | verzija baze karata (`version` u `cards.json`) s kojom je deck složen |
| 3 | heroji | kodovi heroja odvojeni zarezom, redom kako su odabrani (u ispravnom decku točno 3) |
| 4 | karte | `kod*broj` odvojeni zarezom; samo karte s brojem većim od 0, sortirane po kodu (numerički) |

Primjer s izmišljenim kodovima:

```
EB1|v6|XX1-001,XX1-002,XX1-003|XX1-010*4,XX1-011*2,XX1-020*4
```

## Čitanje

- Razmaci na početku i kraju se ignoriraju.
- Kod mora imati točno 4 dijela, a prvi mora biti `EB1`; inače je neispravan.
- Verzija mora biti `v` i cijeli broj.
- Prazan treći ili četvrti dio znači da nema heroja ili karata.
- Karta koja se ponavlja zbraja se (`A*2,A*1` je `A*3`).
- Kodovi karata imaju oblik `SET-001` (npr. `OP1-001`, `JO1-012`, `CR1-001`, `Stage-001`); uz dekodiranje se ne provjeravaju, nego tek uz provjeru decka.

## Verzija baze

- Ako je verzija u kodu **novija** od lokalne baze, javi da treba novija baza (neke karte možda nedostaju).
- Ako je **starija**, deck i dalje radi; karte se nikad ne brišu iz baze, samo dobiju `deleted: true`. Promjene karata od te verzije su u `data/changelog.json`.

## Provjera decka (isto pravilo kao u appu, `checkDeck`)

- 3 različita heroja (tip `Hero`).
- 40 karata, samo tipovi Evolution, Action, Equipment i Assist.
- Svaka karta u boji jednog od heroja; Evolution samo za heroja iz decka (polje `hero` = ime heroja).
- Najviše kopija: Action 4, Equipment 4, Assist 2, Evolution 2.
- Ako bazen karata tih heroja nema 40 karata, deck s manje karata je upozorenje, ne greška.

## Spremljeni deck (`decks/<ime>.json`)

Zajednički folder čuva deckove kao JSON, isti podaci kao kod:

```json
{
  "name": "Ime decka",
  "heroes": ["XX1-001", "XX1-002", "XX1-003"],
  "cards": { "XX1-010": 4, "XX1-011": 2 },
  "catalogVersion": 6,
  "rev": 1,
  "updated": "2026-10-25T08:00:00.000Z"
}
```

`rev` raste sa svakim spremanjem (zaštita od prepisivanja s drugog uređaja). Ime filea je ime decka malim slovima, bez dijakritika, s crticama.
