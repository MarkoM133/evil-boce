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

## Decided with Marko (now in the GDD)

- Knockback: the highest KB on the winning side, from the nearest winner that reaches the
  loser, rounded to one of the six hex directions; off the map is a ring-out. Only losers
  that some winner reaches are hit and knocked back.
- Stage gap is 1 on maps up to 17 wide and 3 on 23×23 (`MatchSettings.effective_stage_gap`).
- Cores off a ringed-out hero are thrown by the game onto random free hexes (not on a
  stage), keeping their face state. Cores off a KO'd hero go to the core owner's inventory
  and come back anywhere free in the owner's own half.

## Assumptions

Things the GDD does not spell out; each is one line to confirm or veto.

1. **Hits:** every winner that reaches a loser hits once with its own DMG; the owner of the
   first reachable loser chooses hero or deck. Deck damage takes cards from the top of the
   deck; with an empty deck from the hand (last drawn first); with an empty hand the player
   loses.
2. **Battle order:** locked (tied) groups first, then the battle with the initiative player's
   activated hero, the other activated hero, then the rest in initiative order.
3. **Second tie:** each hero flies straight towards its own strip (team 0 → +z, team 1 → −z)
   for the other side's highest KB.
4. **Setup** places stages then cores alternately, starting with the initiative player,
   which is rolled before setup. `manual_setup = false` places everything at random with the
   same constraints (cores in the opponent's half, ≥ 3 from other cores and stage edges,
   never on a stage). If something still does not fit, the gap shrinks for the rest and the
   log says `setup_gap_relaxed`.
5. **Overflow cores** (a hero already holding three) come back within that hero's range, or
   anywhere in the owner's half if the hero is gone. Inventory cores are queued at the next
   phase change; until they are placed the owner can do nothing else.
6. **Core pick-up order** within one roll follows the order of results in the outcome
   (thrower first); the sim will stamp exact times later if that ever matters.
7. **Stage reveal** happens when a hero's centre hex ends inside the stage's 7 hexes.
   Terrain applies from then until the turn after a claim.
8. **"Two heroes on a stage, no battle"** means no battle this turn involved any hero
   standing on that stage.
9. A hero in the start zone can be activated at any time, and a stunned or locked hero
   cannot; `select ""` is only legal when nothing can be activated.
10. Equipment, evolutions, assists and card effects are not playable yet (`play_card`
    is refused with "not ready"); the state already carries them.
