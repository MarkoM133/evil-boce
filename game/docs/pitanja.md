# Pitanja za Marka

Otvorena pitanja o pravilima i brojevima. Kad odgovoriš, stavka se briše, a odluka ide u GDD.
Pretpostavke koje je engine morao napraviti sam su u `rules.md`, odjeljak "Assumptions";
precrtaj što ne valja.

## Token karte (2026-11-14)

Pravila su u engineu (`rules.md`, odjeljak Token cards). Otvoreno:

- **Besplatno igranje (FREE_PLAY, npr. Zoro):** smije li efekt "play a card from your hand for free" odigrati token? Engine zasad: ne, jer token nije karta u ruci.
- **Tekst na karti:** kako karta kaže da stvara token (npr. "Create a Spark Token.")? Parser teksta tu rečenicu još ne čita; takva karta zasad treba potvrđen fx (`PREROLL: TOKEN ME DQ1-010-1`).
- **Token protivniku:** fx zna i `TOKEN OPP …` (token dobije protivnik). Ako takvih karata neće biti, riječ ostaje neiskorištena.

## Stage claim na energiju (varijanta na testu, 2026-11-02)

Ostale pretpostavke Marko je odlučio 2026-11-02 (u `rules.md`, odjeljak Energy claim variant). Otvoreno, za kasnije:

- **2v2:** vodi li energiju i suigračev heroj, i čini li suigračev heroj stage spornim. Engine zasad: samo vlastiti heroj, a sporan je stage tek s protivničkim timom.

