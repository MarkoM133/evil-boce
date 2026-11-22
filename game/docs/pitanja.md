# Pitanja za Marka

Otvorena pitanja o pravilima i brojevima. Kad odgovoriš, stavka se briše, a odluka ide u GDD.
Pretpostavke koje je engine morao napraviti sam su u `rules.md`, odjeljak "Assumptions";
precrtaj što ne valja.

## Stage claim na energiju (varijanta na testu, 2026-11-02)

Ostale pretpostavke Marko je odlučio 2026-11-02 (u `rules.md`, odjeljak Energy claim variant). Otvoreno, za kasnije:

- **2v2:** vodi li energiju i suigračev heroj, i čini li suigračev heroj stage spornim. Engine zasad: samo vlastiti heroj, a sporan je stage tek s protivničkim timom.

## DQ1 fx: pretpostavke za potvrdu (2026-11-22)

Odluke iz GDD-a su ugrađene kako pišu. Ovo su mjesta gdje tekst karte ne kaže dovoljno, pa je engine uzeo najbliže čitanje. Reci ako neko ne valja.

- **Fire i claim:** šteta od terena Fire pada na početku End faze, prije claimova. Heroj kojeg vatra sruši ne claima.
- **"The first {Mage} card you play in a turn" uz "Battle Phase:"** (Magical Booster Staff, Magic Stick): broji se prva {Mage} karta odigrana u Battle fazi tog turna. {Mage} karta iz Preroll ili Postroll faze (npr. Zoom) ne troši bonus.
- **Hyunckel, Dark Armor:** "If an Opponent's Hero is in Range, your Opponent's cards give 2000 less Power" čitam po heroju: karta odigrana za protivnikovog heroja koji je u Hyunckelovom dometu daje 2000 manje. Karta nikad ne daje manje od nule (+1000 postane +0).
- **Matoriv:** combo s cijenom 1 ili 2 uz Matoriva košta 0 (pravilo "popust ne ide ispod 1" vrijedi za karte, ne za combo).
- **Justice Itself is my Enemy:** na dno decka idu tri najnovije {Avan Style} karte iz groba. Igrač zasad ne bira koje.
- **A Warrior's Will to Fight:** "falls below 4 HP" gleda HP nakon battlea. Heroj koji je već prije bio ispod 4 i izgubi također okida kartu, i KO se broji.
- **Moruge:** "If an Opponent's Hero is ringed out in this Battle Phase, draw 1 card" čitam kao dio žrtvovanja: vučeš samo ako si Morugea taj turn stavio u graveyard. Druga mogućnost je da vrijedi stalno dok je Moruge u igri.
- **Bartos:** pitanje "staviti Bartosa u graveyard umjesto štete" dolazi samo za udarac iz battlea od 5 ili manje, prije nego što bi šteta pala. Šteta od efekata karata (npr. Fugo) ga ne nudi.
- **Legions of the Dark Army:** plaćaju svi tvoji {Dark Army} heroji u tom battleu koji imaju više od 1 HP, odjednom. Nema izbora po heroju.
- **"Your Hero" na Assistu** (Baduck, Maam): to je tvoj heroj u battleu koji se igra, a izvan battlea aktivirani heroj. Ako su dva tvoja heroja u istom battleu, uzima se prvi; izbor još ne postoji.
- **Return of the Beast King:** heroj se vraća na mjesto i ako je u međuvremenu izbačen u startnu zonu. Ako je KO, ne vraća se. Ako je mjesto zauzeto, stane na najbliže slobodno.
- **Flazzard, Shadow Legion Armor:** KO dolazi kad evoluciju skine karta. Ako Flazzard dobije novu, višu evoluciju, ova ostaje ispod i ništa se ne događa.
- **Chimaera Wing u timskom battleu:** strana s herojem koji bježi ne može pobijediti battle, pa i suborac u istom battleu gubi (on prima udarac kao inače).
- **Deck builder i dobiveni tagovi:** u partiji dobiveni tag vrijedi za igranje karata. Pravilo "u deck smije ako deck ima kartu koja daje taj tag" još nije ugrađeno u provjeru decka (ni u igri ni u Card Studiju).
