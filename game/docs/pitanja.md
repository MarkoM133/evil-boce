# Pitanja za Marka

Otvorena pitanja o pravilima i brojevima. Kad odgovoriš, stavka se briše, a odluka ide u GDD.
Pretpostavke koje je engine morao napraviti sam su u `rules.md`, odjeljak "Assumptions";
precrtaj što ne valja.

## Privremena evolucija (2026-11-15)

Ugrađeno po odluci od 15.11.; dvije stvari engine radi kao kod svake evolucije, a kod privremene možda ne želite:

- **Oprema koja traži trait.** Dok privremena traje, heroj ima njezine traitove, pa oprema čiji prvi tag heroj više ne zadovoljava **padne u graveyard** (npr. Avan s opremom za Brave Hero postane Avan, Dragon s traitovima Dragon i Mage). Kad privremena istekne, oprema se ne vraća. Treba li oprema ostati dok traje privremena evolucija?
- **HP kad istekne.** Vrijedi isto kao za Remove Evolution: HP se samo spusti na novi max. Ako je privremena imala **manji** max HP od razine ispod (heroj 10/12, privremena max 8 → 6/8), nakon isteka ostaje 6/12, tj. heroj je trajno izgubio 4 HP. Ako je imala **veći** max, višak štete se "oprosti" (9/12 → 8/8). Treba li se umjesto toga pamtiti šteta (10/12 → 6/8 → natrag 10/12)?

## Stage claim na energiju (varijanta na testu, 2026-11-02)

Ostale pretpostavke Marko je odlučio 2026-11-02 (u `rules.md`, odjeljak Energy claim variant). Otvoreno, za kasnije:

- **2v2:** vodi li energiju i suigračev heroj, i čini li suigračev heroj stage spornim. Engine zasad: samo vlastiti heroj, a sporan je stage tek s protivničkim timom.

