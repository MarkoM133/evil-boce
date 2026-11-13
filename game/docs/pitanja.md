# Pitanja za Marka

Otvorena pitanja o pravilima i brojevima. Kad odgovoriš, stavka se briše, a odluka ide u GDD.
Pretpostavke koje je engine morao napraviti sam su u `rules.md`, odjeljak "Assumptions";
precrtaj što ne valja.

## Stage claim na energiju (varijanta na testu, 2026-11-02)

Ostale pretpostavke Marko je odlučio 2026-11-02 (u `rules.md`, odjeljak Energy claim variant). Otvoreno, za kasnije:

- **2v2:** vodi li energiju i suigračev heroj, i čini li suigračev heroj stage spornim. Engine zasad: samo vlastiti heroj, a sporan je stage tek s protivničkim timom.

## Pregled koda (2026-11-13)

Dva mjesta gdje se dizajn i engine ne slažu; engine zasad ostaje kako je.

- **Samo Pass nakon što aktivirani heroj ispadne:** dizajn dopušta karte koje ne trebaju heroja, a engine tom igraču do kraja turna odbija svaku kartu. Koje karte smiju (Assist? Action bez mete?), ili ostaje strogo samo Pass?
- **KO od cijene ring-outa:** heroj s 1 HP koji plati ring-out štetom padne u KO, a engine taj KO broji za pobjedu kao svaki drugi. Rečenica u dizajnu da se ring-out "ne broji kao KO za pobjedu" odnosi se na sam ring-out, ili i na taj KO?
