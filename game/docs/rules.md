# Rules engine (`rules/`)

Pure logic, no scene, no physics. The GDD is the source of truth; this file says how the
engine is shaped and which gaps it had to fill on its own (see **Assumptions**).

## Shape

- `GameState` is the whole match as data (`to_dict`/`from_dict`): players, heroes, cores,
  stages, walls, the phase, whose turn it is in a card round, pending decisions, log.
  Ids follow `ids.md`.
- `RulesEngine.apply(state, move)` applies one `Move` and returns `""` or a reason for
  refusal (the state is untouched then). After every accepted move the engine runs all
  automatic steps until it needs input again.
- `RulesEngine.apply_roll(state, outcome)` feeds the physics result (`RollOutcome`) while
  `state.awaiting_roll` is true. Results whose `ball` is a hero id move that hero; anything
  else is ignored.
- `state.pending` lists decisions the engine waits for before anything else:
  `damage` (loser picks `"deck"` or a hero among `targets`) and `return_core`.
- Nothing in `rules/` touches Node, FileAccess or randomness outside `state.random_int()`
  (seeded, stored in the state, so replays and the host/client agree).

## Phases and moves

| Phase | Accepted moves | Ends when |
|---|---|---|
| `setup_stages` | `place_stage` by `setup_turn` | all stages placed |
| `setup_cores` | `place_core` by `setup_turn` | all cores placed (hands dealt) |
| `mulligan` | `mulligan {keep}` | both decided → turn 1 |
| `draw` | — (automatic) | draw 1, energy = min(turn, 8) |
| `select` | `select {hero}` (`""` only when none can be activated) | all selected |
| `preroll` | `pass`, `choice {roll}`, (`play_card`) | round passed and all choices in |
| `roll` | `aim {dir, power}`, then the sim's `apply_roll`, then `pass` | round passed |
| `postroll` | `pass`, (`play_card`) | round passed |
| `battle` | per battle: `pass` round, then `damage_to` decisions | last battle done |
| `end` | — (automatic) | claims, status timers, win check, next turn |
| `over` | nothing | — |

`surrender` is accepted at any time. Card rounds alternate from the initiative player and end
when every player has passed in a row.

## Scenario tests

`tests/test_scenarios.gd` runs every `tests/scenarios/*.json` against the fixture catalog
`tests/fixtures/cards.json`. A scenario is `{"name": ..., "steps": [...]}`; each step is one of:

- `{"setup": {"seed": 1, "decks": [...], "settings": {...}}}` – `decks` and `settings` are
  optional (defaults: two fixture decks, automatic placement).
- `{"set": {"heroes.p0:TA-001.hex": [4, 8], ...}}` – rewrites state fields by path.
- `{"move": {...}}` – must be accepted; add `"error": "substring"` when it must be refused.
- `{"roll": {RollOutcome dict}}`
- `{"pass_round": true}` – everyone passes until the round is over.
- `{"expect": {"path": value, "list": {"$size": n}, "list": {"$has": x}}}`.

Paths use the JSON form of the state: `players.p0.hand`, `heroes.<id>.hp`, `cores.<id>.place`,
`stages.<id>.claimed_by`, `pending.0.type`, `battles.0.winner_team`.

## Assumptions

Things the GDD does not spell out; each is one line to confirm or veto.

1. **Knockback direction** is the hex direction (one of six) closest to the line from the
   nearest winning hero that reaches the loser to the loser. Leaving the map by knockback is a
   ring-out.
2. **Knockback amount** is the highest KB on the winning side; only losers that at least one
   winner reaches are knocked back (and hit).
3. **Hits:** every winner that reaches a loser hits once with its own DMG; the owner of the
   first reachable loser chooses hero or deck. Deck damage takes cards from the top of the
   deck; with an empty deck from the hand (last drawn first); with an empty hand the player
   loses.
4. **Battle order:** locked (tied) groups first, then the battle with the initiative player's
   activated hero, the other activated hero, then the rest in initiative order.
5. **Second tie:** each hero flies straight towards its own strip (team 0 → +z, team 1 → −z)
   for the other side's highest KB.
6. **Setup** places stages then cores alternately, starting with the initiative player,
   which is rolled before setup. `manual_setup = false` places everything at random with the
   same constraints (stage edges ≥ 3 apart in the middle third; cores in the opponent's half,
   ≥ 3 from other cores and stage edges, never on a stage).
7. **Cores off a KO'd or ringed-out hero** go to their owner's inventory and come back
   anywhere free in the owner's own half, not on a stage. Cores that overflowed a hero's three
   slots come back within that hero's range (or the owner's half if the hero is gone).
   Inventory cores are queued at the next phase change; until they are placed the owner can
   do nothing else.
8. **Core pick-up order** within one roll follows the order of results in the outcome
   (thrower first); the sim will stamp exact times later if that ever matters.
9. **Stage reveal** happens when a hero's centre hex ends inside the stage's 7 hexes.
   Terrain applies from then until the turn after a claim.
10. **"Two heroes on a stage, no battle"** means no battle this turn involved any hero
    standing on that stage.
11. A hero in the start zone can be activated at any time, and a stunned or locked hero
    cannot; `select ""` is only legal when nothing can be activated.
12. Equipment, evolutions, assists and card effects are not playable yet (`play_card`
    is refused with "not ready"); the state already carries them.
