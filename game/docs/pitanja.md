# Pitanja za Marka

Otvorena pitanja o pravilima i brojevima. Kad odgovoriš, stavka se briše, a odluka ide u GDD.

## Sandbox (korak 1a)

1. **Ring-out na traku.** Sad je ring-out kad **bilo koja** kuglica s mape uđe na **bilo koju**
   startnu traku, i na svoju (kako piše u GDD-u). Handoff spominje samo tuđu kuglicu.
   Vrijedi li i za vlastitu traku?
2. **Preslabo bacanje sa trake.** Ako kuglica bačena sa svoje trake stane na traci i ne uđe u mapu,
   sad samo ostane na traci (nije ring-out). Je li to propušten Roll, ili nešto drugo?
3. **Dva cilja za sudar se tuku.** Uz biljarsku fiziku ne mogu oba biti potpuno ispunjena:
   - WT3 u mirnu WT1: WT1 odleti ~16 hexova, WT3 nastavi ~1,7 (cilj ispunjen);
   - WT1 u mirnu WT3: WT3 ode ~4,6 hexa, WT1 se odbije ~1,7 natrag ("WT3 jedva mrdne" nije baš).
   Veći omjer masa (`mass_by_wt` u `sim/physics_tuning.tres`) smanji drugo, ali onda WT3 nakon
   udarca u WT1 ide dalje. Što ti je važnije? Brojke daje `tools/measure_throws.gd`.
