# Pitanja za Marka

Otvorena pitanja o pravilima i brojevima. Kad odgovoriš, stavka se briše, a odluka ide u GDD.

1. **Šest stageova ne stane na 15×15 i 17×17** po pravilu "srednja trećina, najmanje 3 polja
   između rubova". Srednja trećina 17×17 ima 7 redova, a dva reda stageova s razmakom 3 traže
   9. U jednom redu stanu najviše 3 stagea. Na 23×23 stane (2 reda × 4). Što od ovog:
   (a) manji razmak na manjim mapama (npr. 1), (b) manje stageova po igraču na manjim mapama
   (npr. 2), (c) srednja *polovica* umjesto trećine, (d) nešto četvrto?
   Engine zasad pri automatskom postavljanju smanjuje razmak dok ne stane i to zabilježi u log
   (`setup_gap_relaxed`); ručno postavljanje drži pravilo i igrač bi zapeo.

Pretpostavke koje je engine morao napraviti sam su u `rules.md`, odjeljak "Assumptions";
precrtaj što ne valja.
