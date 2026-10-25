// Statistika odigranih partija za karticu Balance. Igra nakon svake partije zapiše sažetak u
// stats/<datum>_<naslov>.json (MatchRecord.summary u igri): pobjednik, razlog, turni, battlei,
// po igraču heroji, stageovi, KO-ovi, ring-outovi, claimovi, i koliko je puta odigrana koja karta.
// Ovdje se ti sažeci samo zbrajaju; ništa se ne piše.

export const RESULTS = { ko: 'All heroes KO', stages: 'Stages claimed', deckout: 'Deck-out', surrender: 'Surrender', draw: 'Draw' };

// Sažeci koji prolaze filter: bez partija protiv bota ako withBots = false, samo jedna verzija
// baze karata ako je cardsVersion zadan (0 = sve).
export function filterMatches(matches, { withBots = true, cardsVersion = 0 } = {}) {
  return matches.filter(m => m && Array.isArray(m.players)
    && (withBots || !m.players.some(p => p.bot))
    && (!cardsVersion || m.cards_version === cardsVersion));
}

const pct = (n, d) => (d ? Math.round((100 * n) / d) : null);

// Zbroj partija: { matches, turns, battles, results, heroes, cards, stages, decks, bots }.
// heroes/stages/decks: { id: { picks, wins, rate } } (rate = postotak pobjeda, null bez partija);
// cards: { id: { plays, matches, perMatch } }; bots: { picks, wins, rate } za bot slotove.
export function aggregate(matches) {
  const out = { matches: matches.length, turns: 0, battles: 0, results: {}, heroes: {}, cards: {}, stages: {}, decks: {}, bots: { picks: 0, wins: 0 } };
  const bump = (table, id, won) => {
    const row = table[id] ??= { picks: 0, wins: 0 };
    row.picks += 1;
    if (won) row.wins += 1;
  };
  for (const m of matches) {
    out.turns += m.turns ?? 0;
    out.battles += m.battles ?? 0;
    out.results[m.result ?? '?'] = (out.results[m.result ?? '?'] ?? 0) + 1;
    for (const p of m.players) {
      const won = m.winner >= 0 && p.slot === m.winner;
      // Isti heroj dvaput u jednoj partiji (oba igrača) broji se za svakog igrača.
      for (const id of p.heroes ?? []) bump(out.heroes, id, won);
      for (const id of p.stages ?? []) bump(out.stages, id, won);
      if (p.deck_name && !String(p.deck_name).startsWith('Random')) bump(out.decks, p.deck_name, won);
      if (p.bot) {
        out.bots.picks += 1;
        if (won) out.bots.wins += 1;
      }
    }
    for (const [id, n] of Object.entries(m.cards_played ?? {})) {
      const row = out.cards[id] ??= { plays: 0, matches: 0 };
      row.plays += n;
      row.matches += 1;
    }
  }
  for (const table of [out.heroes, out.stages, out.decks]) {
    for (const row of Object.values(table)) row.rate = pct(row.wins, row.picks);
  }
  out.bots.rate = pct(out.bots.wins, out.bots.picks);
  for (const row of Object.values(out.cards)) row.perMatch = out.matches ? row.plays / out.matches : 0;
  out.avgTurns = out.matches ? out.turns / out.matches : 0;
  out.avgBattles = out.matches ? out.battles / out.matches : 0;
  return out;
}

// Retci tablice poredani: najviše odabira prvo, pa veći postotak pobjeda, pa id.
export function ranked(table, key = 'picks') {
  return Object.entries(table)
    .map(([id, row]) => ({ id, ...row }))
    .sort((a, b) => (b[key] - a[key]) || ((b.rate ?? -1) - (a.rate ?? -1)) || a.id.localeCompare(b.id));
}

// Verzije baze karata koje se pojavljuju u sažecima, najnovija prvo.
export function cardsVersions(matches) {
  return [...new Set(matches.map(m => m.cards_version).filter(v => Number.isInteger(v)))].sort((a, b) => b - a);
}
