# Pitanja za Marka

Otvorena pitanja o pravilima i brojevima. Kad odgovoriš, stavka se briše, a odluka ide u GDD.
Pretpostavke koje je engine morao napraviti sam su u `rules.md`, odjeljak "Assumptions";
precrtaj što ne valja.

## Teren Wind: u kojem smjeru puše? (2026-10-25)

GDD kaže samo "gura u smjeru". Fizika je gotova (gura kuglice dok se kotrljaju, slabije od
trenja, pa svaka stane; probaj u Sandboxu: Terrain → Wind, strelica bira smjer).
U meču zasad puše **poprijeko** (smjer 0, s lijeva na desno gledano s tvoje strane), da ne
pomaže nijednoj strani. Opcije:

1. poprijeko, uvijek isto (sada);
2. smjer ovisi o stage karti (novi zapis, npr. `Terrain: Wind →`, za autora karata);
3. slučajno od 6 smjerova kad se stage otkrije (ide u stanje igre i replay);
4. prema protivniku vlasnika stagea.

## Teren Ramp: brdo ili kosina? (2026-10-25)

Napravljeno je **brdo** na 7 hexova: uz brdo kuglica usporava, niz brdo ubrzava, a stati može
samo blizu vrha (do ~1,2 hexa od sredine). Kosina (rampa u jednom smjeru) je moguća, ali onda
treba i smjer, kao za Wind. Je li brdo dobro?
