// Izgled heroja u igri: kuglica (tijelo i akcent) i figurina (sprite).
// Boje su iste kao u igri (game/ui/palette.gd), da pregled u appu izgleda kao kuglica na stolu.

export const BALL_COLORS = { Red: '#e23b2e', Cyan: '#35c9d6', Blue: '#3c7df0', Green: '#4fb858', Purple: '#9a5bd6', Yellow: '#f2c330' };
// Akcent kad nije odabran (donja polovica kuglice), kao Palette.DEFAULT_ACCENT u igri.
export const DEFAULT_ACCENT = '#2a2622';

export function heroDefaultColor(card) {
  return BALL_COLORS[card.color] ?? '#b8ab98';
}

// Boje kuglice kako ih igra čita: ballColor / ballColor2, inače stara TTS polja bakuganColor / bakuganColor2,
// inače boja heroja i zadani akcent. accent = null znači zadani akcent.
export function ballColors(card) {
  return {
    body: card.ballColor ?? card.bakuganColor ?? heroDefaultColor(card),
    accent: card.ballColor2 ?? card.bakuganColor2 ?? null,
  };
}
