// Combo karte (Marko 2026-11-07): dvije karte koje rade i same, a odigrane za dva tvoja heroja u istom battleu
// mogu se za dodatnu energiju pretvoriti u Combo kartu. Combo je vrsta karte u istoj bazi (kod CB-001…):
// { type: 'Combo', ingredients: [id, id], extraCost: X, introducedIn: 'OP1' }. Ne ide u deck ni u pakete
// (deck i Draft primaju samo DECK_TYPES). Bez I/O, isto za app, renderer i testove.

export const COMBO = 'Combo';
export const COMBO_SET = 'CB';
export const isCombo = c => c?.type === COMBO;

// Kombinacije koje može tvoriti karta: Action, i Assist kad se igra u battleu (Equipment i ability nisu dio para).
export const INGREDIENT_TYPES = ['Action', 'Assist'];

// Combo karte koje imaju ovu kartu za sastojak.
export function combosOf(cards, id) {
  return cards.filter(c => isCombo(c) && !c.deleted && (c.ingredients ?? []).includes(id));
}

// Je li karta sastojak nekog comboa (za ikonu Combo, iskru uz kod). Izračunato, nikad ručno.
export const isIngredient = (cards, id) => combosOf(cards, id).length > 0;

// Boje comboa: boje karata sastojaka (bez colorless), redom, najviše dvije; obje iste = jedna.
// Colorless sastojci daju sivu kad nijedan nema boju.
export function comboColors(cards, combo) {
  const out = [];
  for (const id of combo.ingredients ?? []) {
    const c = cards.find(x => x.id === id);
    if (c && c.color && c.color !== 'None' && !out.includes(c.color)) out.push(c.color);
  }
  return out.length ? out.slice(0, 2) : ['None'];
}

// Karta spremna za crtanje: Combo dobiva boje i imena sastojaka, sastojak dobiva oznaku za iskru.
export function decorate(card, cards) {
  if (!card) return card;
  if (isCombo(card)) {
    const names = (card.ingredients ?? []).map(id => cards.find(x => x.id === id)?.name ?? id);
    return { ...card, comboColors: comboColors(cards, card), ingredientNames: names };
  }
  return isIngredient(cards, card.id) ? { ...card, comboMark: true } : card;
}

// Karte čija se slika mijenja kad se combo promijeni: stari i novi sastojci (iskra se pojavi ili nestane).
export function touchedIngredients(before, after) {
  return [...new Set([...(before?.ingredients ?? []), ...(after?.ingredients ?? [])])];
}

// Iduci kod u setu comboa: CB-001, CB-002…
export function nextComboId(cards) {
  const n = cards.filter(isCombo).map(c => Number(String(c.id).split('-')[1]) || 0);
  return `${COMBO_SET}-${String((n.length ? Math.max(...n) : 0) + 1).padStart(3, '0')}`;
}

// Problemi comboa za Checks: točno dva različita sastojka, Action ili Assist, X barem 0.
export function comboProblems(cards, combo) {
  const out = [];
  const ing = combo.ingredients ?? [];
  if (ing.length !== 2 || !ing[0] || !ing[1]) out.push('A combo needs exactly two cards');
  else if (ing[0] === ing[1]) out.push('The two cards must be different');
  for (const id of ing.filter(Boolean)) {
    const c = cards.find(x => x.id === id);
    if (!c) out.push(`${id} is not a card`);
    else if (!INGREDIENT_TYPES.includes(c.type)) out.push(`${c.name} is ${c.type}: only Action and Assist cards make a combo`);
  }
  if (!(Number(combo.extraCost) >= 0)) out.push('No extra cost (X)');
  return out;
}
