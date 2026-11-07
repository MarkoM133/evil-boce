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
  `damage` (the loser answers `damage_to {target: a hero among targets, cards: [hand card ids]}`:
  at least `min_hero` = ⌈amount/2⌉ lands on the hero, each card takes 1 DMG of the rest) and `return_core`.
- Nothing in `rules/` touches Node, FileAccess or randomness outside `state.random_int()`
  (seeded, stored in the state, so replays and the host/client agree).

## Phases and moves

| Phase | Accepted moves | Ends when |
|---|---|---|
| `setup_stages` | `place_stage` by `setup_turn` | all stages placed |
| `setup_cores` | `place_core` by `setup_turn` | all cores placed (hands dealt) |
| `mulligan` | `mulligan {keep}` | both decided → turn 1 |
| `start` | `select {hero, roll}` (`hero ""` only when none can be activated; `roll` false = Stay, refused for a hero in the start zone) | all selected; draw 1 and energy = min(turn, 8) happened on entering |
| `preroll` | `pass`, (`play_card`) | round passed |
| `roll` | `aim {dir, power}` (or `aim {skip: true}`: a missed roll, the hero stays put), then the sim's `apply_roll`; then a `roll_offer` decision per player with a "Roll Phase:" option (`use_ability`, `play_card` or `pass`) | aims in, balls stopped, offers answered |
| `postroll` | `pass`, (`play_card`) | round passed |
| `battle` | per battle: `pass` round, then `damage_to` decisions | last battle done |
| `end` | — (automatic); with energy claims a `stage_energy {split}` decision when a player's heroes stand on more than one open stage | claims (or energy into stages), status timers, win check, next turn |
| `over` | nothing | — |

`surrender` is accepted at any time. Card rounds alternate from the initiative player and end
when every player has passed in a row; playing a card hands the turn to the next player and
resets the passes.

## Energy claims (`MatchSettings.stage_claim = "energy"`, the default)

From Marko (2026-11-02); the default of Standard and every mode since 2026-11-02, with the
Stay claims still offered in the rules panel. `MatchSettings.new()` keeps Stay, which the
scenario tests use. `stage_goal` (default 14) is the energy a stage needs. The GDD still
describes energy claims as the rule since 2026-11-04 (final); Stay stays an option.

- No Stay claim and no battle claim. Energy is as always: +1 a turn up to `max_energy`, and
  what is left at the end of the turn does not carry over.
- End phase (`_bank_energy`, once a turn, `GameState.energy_banked`): each player's energy left
  goes into the unclaimed stage(s) one of its own heroes stands on (`energy_stages`). One stage
  takes it all; more than one gives a `stage_energy` decision `{"energy", "stages", "goal"}`,
  answered by `stage_energy {"split": {stage id: n}}` adding up to all of it.
- Contested (`contested`): heroes of two teams on a stage, so nobody's energy goes in
  (event `stage_contested`).
- Progress is per player and per stage (`StageState.progress`, slot -> energy). Reaching the
  goal claims the stage at once (event `stage_claimed` with `energy`); energy over the goal is
  lost (`stage_energy.wasted`).
- Knocked off (`begin_move` / `end_move`): a hero that leaves an unclaimed stage through the
  other side's doing costs its player half the energy in that stage, rounded down (event
  `stage_knocked_off {hero, stage, player, lost, progress, goal, by_team}`). Leaving by its own
  roll costs nothing, and so does it while another of the player's heroes still stands there
  (`lost` 0): only the last one off halves it. Who did it: a battle knockback, the winners; a roll, the thrower whose
  ball touched it, directly or through other balls (`roll_causes`; without touches reported,
  another team that threw); a KO, whoever dealt the damage; a card's move or knockback, the
  card's player; a physics knockback, each knocked hero's own (a tie-break sends each side back
  by the other's), and a ball one of them touches the same. Only a hero's outermost move counts.
- Decided with Marko (2026-11-02; final and in the GDD since 2026-11-04): a KO by
  the other side on a stage counts as being knocked off; a card of the other side that moves or
  knocks the hero off counts too; energy may go into any unclaimed stage, whoever placed it; a
  "cannot claim" effect lets the energy go in but holds the claim back until a later End phase;
  energy over the goal is lost; the goal is 14 unless set.
- 2v2 is left for later (`pitanja.md`). For now only the player's own heroes count, and a
  teammate's hero does not contest.
- The move timer's safe move puts it all into the stage with the most energy already in it.
- **Tie-break** (Marko 2026-11-04): when every winning side reaches its stages in the same End phase, the side that put more energy into stages over the whole match wins (`PlayerState.energy_invested`: everything banked into stages, over the goal and later lost included; result `stages_energy`, event `tie_broken {by, totals, winner_team}`); equal totals, or a win by KO at the same time, stay a draw. With Stay claims a simultaneous win stays a draw.

## Playing cards (`play_card {"card", "hero"?, "replace"?}`)

- Costs energy (`PlayerState.energy`, refilled to min(turn, 8) every Draw).
- Played in the colour of the **context heroes**: outside a battle the activated hero; in a
  battle your heroes taking part in it. `hero` picks one when several fit. A colorless card
  (`color: "None"`, 2026-11-01) goes to a context hero of any colour; its price and its
  `BONUS` effects depend on that hero (`card_cost(s, p, card, hero)`; with no hero, the
  cheapest of the heroes it could go to, which is what the hand shows).
- **Equipment**: on a context hero, at most `equipment_limit` (3), the same card once per
  hero. Its `bonus` (`{"pwr": 1000, "hp": 2}` from the web app) counts while equipped.
- **Evolution**: on a context hero that is on the map, `hero` name must match, level
  `evo` must be the next one. Stats come from the evolution card; damage carries over
  (new max − damage taken). `remove_evolution()` drops HP only down to the new max.
- **Assist**: at most `assist_limit` (3) per player, the same card once; a fourth needs
  `replace` (an assist in play that goes to the graveyard).
- **Action**: only cards whose whole effect is a `bonus` (e.g. "+2000 Power"); the bonus
  lasts until the end of the phase (`HeroState.phase_bonus`). Anything else is refused with
  "not ready" until step 2c (parser + fx).
- `RulesEngine.stat()` = card (or top evolution) + equipment bonuses + bonuses of the cores in
  the hero's slots (`CardDef.bonus` of a Core; a Debuff core is a trap for whoever picks it
  up) + phase and turn bonuses + passive fx, never below 0. `DeckCode` decodes, encodes and checks deck codes exactly like the web app.
- Text effects run through the fx layer: format, parser, verbs and choices are in
  `fx-keywords.md`. Moves: `use_ability {hero, card, index}` for "may" abilities,
  `choose {value}` for a pending `choose` decision.

## Combo cards (decided 2026-11-07, built the same day)

- Data: `type: "Combo"` in `cards.json` with `ingredients: [id, id]` (exactly two Action or Assist cards),
  `extraCost` (X) and `introducedIn` (a set code). Combo cards are never in a deck, a pack or Draft
  (`DeckCode.DECK_TYPES` already leaves them out). The web app helpers are in `js/combo.js`.
- The battle being fought remembers what its card round played (`battles[i].played`: player, card, hero,
  the stat bonus it put on the hero, used). A played Assist has no hero.
- When: in a battle's card round, `play_card` of the second card of a combo's pair, when the first one was
  played this battle by the same player and for a different hero of theirs (an Assist pairs with any), the
  player has two or more heroes in the battle, the card itself would be legal (tried on a copy) and the
  player can pay its cost + X: the move puts `combo_offer {player, card, hero, cost, replace, combos: [{id,
  with, with_hero, extra}]}` on `pending` and the turn passes; the card stays in the hand until answered.
- `choose {value: combo id}` accepts: cost + X is paid, the second card goes to the graveyard without
  resolving, the first card's stat bonus comes off its hero and its waiting "If you win" effects are dropped
  (an effect of it that already ran, a knockback say, stays), the record is marked used, event `combo`, and
  the combo's effects run (`BATTLE:` lines like an Action's; its stat boxes go on the second card's hero).
  `choose {value: ""}` or `pass` declines: the card is played as it would have been.
- Same combo again: any time the condition holds. A card may be in several combos; all that fit are offered.
- `ALL_FRIENDLY_IN_BATTLE`: every hero of the card's player in the battle the context names, else the one
  being fought. Scenarios 57 and 58; the bot takes the first combo on offer.
- Match scene (no rules): the offer dialog shows the combo card above its buttons. Event `combo` shows the
  combo card over the screen (`MatchHud._combo_show`, queued with the bands; a click or Enter skips it).
  The pause menu's right side has tabs MATCH LOG and COMBO LIST (when there are combos); COMBO LIST shows the
  pictures of each combo and its two cards, and the combos this screen's deck can make, or every combo (ALL); it reads
  the deck from the match record, or the deck an online guest sent (`NetClient.my_deck`), never the
  opponent's.

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
- Stage gap is 1 on maps up to 17 wide and 3 on 23×23 (`MatchSettings.effective_stage_gap`);
  core gap is 2 on maps up to 17 wide and 3 on 23×23 (`effective_core_gap`).
- Cores off a ringed-out hero are thrown by the game onto random free hexes (not on a
  stage), keeping their face state. Cores off a KO'd hero go to the core owner's inventory
  and come back anywhere free in the owner's own half.
- Ring-out (Marko 2026-11-07, in place of the wall damage, which is gone with its MATCH RULES
  setting): every ring-out costs the hero 1 DMG (`RulesEngine.RING_OUT_DAMAGE`; a hero at 1 HP
  is knocked out by it), whoever caused it, the strips included. With a card in the hand the
  player gets the usual damage decision (`damage` with `ring_out: true`, `by: "ring_out"`,
  `min_hero` 0) and may discard one card instead; with none it lands at once. The hit's
  `damage` / `hand_damage` events carry `by: "ring_out"`.

## Assumptions

Things the GDD does not spell out; each is one line to confirm or veto.

1. **Hits:** (confirmed 2026-10-26) every winner that reaches a loser hits once with its own DMG; the owner of the
   first reachable loser chooses which reachable hero takes it. A winner that reaches no loser deals nothing; the engine logs
   `out_of_reach {hero, losers}` so the win does not look like a skipped step (playtest 2026-11-06). (Marko, 2026-11-02:)
   at least half of the hit, rounded up, lands on that hero; for the rest the loser may discard
   cards from the hand, 1 card per DMG (the player picks which), or take it on the hero too. With
   no cards in the hand it all lands on the hero. The deck never takes damage and there is no
   deck-out win any more (an empty deck only means no draw). A hit that knocks the hero out takes
   it out of the hits still waiting; a hit with nobody left to take it is wasted (`hit_wasted
   {hero, targets}`; online playtest 2026-11-07). Scenario 60. Damage from cards ("take 3 DMG")
   is not a battle hit and goes where the card says. Event `hand_damage` {player, cards, amount,
   hand, by}; `deck_damage` / `deck_out` / result `deckout` live on only in old replays.
2. **Battle order:** (confirmed 2026-10-26) locked (tied) groups first, then the battle with the initiative player's
   activated hero, the other activated hero, then the rest in initiative order.
3. **Second tie:** (confirmed 2026-10-26) each hero flies straight towards its own strip (team 0 → +z, team 1 → −z)
   for the other side's highest KB.
4. **Setup** (confirmed 2026-10-26) places stages then cores alternately, starting with the initiative player,
   which is rolled before setup. `manual_setup = false` places everything at random with the
   same constraints (cores in the opponent's half, ≥ 3 from other cores and stage edges,
   never on a stage). If something still does not fit, the gap shrinks for the rest and the
   log says `setup_gap_relaxed`.
5. **Overflow cores** (confirmed 2026-10-26) (a hero already holding three) come back within that hero's range, or
   anywhere in the owner's half if the hero is gone. Inventory cores are queued at the next
   phase change; until they are placed the owner can do nothing else. A core an ability or a card
   deactivates is asked for at once, in the same phase, right after that effect's own choices
   (Marko 2026-11-07: Zoro's core waited for a Battle phase with no battle; scenario 61).
6. **Core pick-up order** (confirmed 2026-10-26) within one roll follows the order of results in the outcome
   (thrower first); the sim will stamp exact times later if that ever matters.
7. **Stage reveal** (confirmed 2026-10-26) happens when a hero's centre hex ends inside the stage's 7 hexes.
   Terrain applies from then until the turn after a claim.
8. **"Two heroes on a stage, no battle"** (confirmed 2026-10-26) means no battle this turn involved any hero
   standing on that stage.
9. (2026-10-26) The turn has six phases: Start (draw + hero + Roll/Stay in one `select` move, all
   revealed together), Preroll (cards), Roll (aims and throws only; "Roll Phase:" cards and
   abilities come as one `roll_offer` per player whose hero rolled (a hero that stayed has
   nothing to roll again, Marko 2026-11-02) and stop, options or none, so nobody can
   read "has a Roll Phase card" off who is asked; the offers of one stop are answered in any
   order; a roll again brings a new stop and new offers), Postroll, Battle, End. Declining an
   empty offer after a fixed wait is the client's job (auto-pass), not a rule. A hero's own
   non-optional effect that fires (a Hero or Evolution card) logs `triggered` {hero, card, index}
   first, so the HUD can show the ability's name. An offer lists
   only cards the first tag lets the activated hero play, and carries `at` (the log size at the
   stop) so a clock keyed on it is not restarted by the other player's answer. The decisions
   an answer asks for (a choice) go to the front of `pending`, before the other offers of the
   stop, so the answering player is not kept waiting.
9b. (2026-10-26) The move timer is not a rule: `MatchClock` (rules/) only says whom the game waits
   for, what for (`wait_key`) and the safe move when the time runs out (pass, keep, the marked
   or a random hero that stays when it may, a missed roll, a random legal placement, all the
   damage on the first hero offered, the gentlest choice). The match scene keeps the clocks locally and as the host;
   guests only show them. `timer_seconds` 0 = off.
   `deck_size` below the deck's cards (the Fast mode, GDD 13) plays the first that many of the
9c. (2026-10-26) Knockback mode `knockback`: "physics" (the game, 2026-10-26: every
   knockback is a real hit; the word on the cards stays Knockback) or "grid" (hex by hex, as
   above: the engine on its own, as in the scenario tests; not offered in MATCH RULES). A physics knockback is not applied by the
   engine: it waits in `GameState.pending_knockbacks` ({hero, dir, steps}), `_continue` stops
   and every move is refused with "waiting for the knockback" until the scene runs the sim
   (hit along the hex direction, power = steps / full-power hexes of the WT) and brings the
   `RollOutcome` to `apply_knockback`. The outcome lands every moved ball as a roll does
   (cores, stages, ring-outs); the balls and walls it hit are counted (`knockback.hits`) but cost
   nothing (Marko 2026-11-07: no wall damage any more; a ring-out costs 1 DMG, see below). The
9d. (2026-10-26) `series_wins` > 1 is a series (`MatchSeries`, not a rule: the scene and the host
   keep it); `first_initiative` names who starts (the last loser), -1 draws lots as before.
   A seat may bring a sideboard (up to 10 cards its heroes may take, each under its limit;
   `MatchSeries.sideboard_error`) and swap up to 5 cards a break between games
   (`swap_error` / `set_cards`: only the break's deck and sideboard, the deck still legal);
   the swaps stay. Online the deck carries `sideboard`; the host checks swaps in `_series_deck`.
9e. (2026-10-26) The Draft mode is `DraftState` (rules/), pure: heroes A B B A A B with none shared,
   four packs of ten from the copy pool of both players' colours (evolutions only of drafted
   heroes), picks in turn, the rest to the other, no card of the other's colour or over its
   limit, a player with nothing legal skips, every deck filled to `deck_size` (20) at the end.
9f. (2026-10-26) The first tag rule (`FirstTag`, shared with the web app through
   tests/fixtures/first_tag_cases.json) locks a card to who may play it: General (any hero of
   its colour), a hero alias (the name follows the hero through evolutions; a name after "&"
   that is no hero yet is skipped, so "Shanks & Roger" is Shanks's until Roger comes) or a trait read off
   the hero's current card (the last evolution, else the base). `_play` refuses the others
   ("only for X", "Requires T"); equipment whose tag the hero no longer fits falls into the
   graveyard when an evolution comes or goes (`_drop_unfit_equipment`). A record carries the
9g. (2026-11-01) Colorless cards: `color: "None"` passes the colour check in `deck_verdict`
   and `_play` (the first tag still counts), and `bonusColors` on the card drive the fx
   `BONUS` / `INSTEAD` effects and `OWN_COST` (docs/fx-keywords.md). The Draft counts a
   colorless card as a card of any colour.
g. (2026-10-26) A grid knockback stopped by a wall or a hero just stops (no damage since
   2026-11-07). A Wind stage draws its direction (`StageState.wind_dir`, one of six) when it is
   revealed; `terrain()` blows that way and the state and the replay keep it.
10. `REVERSE_ROLL` puts the activated hero back where it stood when the Roll phase began
   (`GameState.roll_snapshot`); pushed heroes, picked cores and revealed stages stay.
11. A hero in the start zone can be activated at any time, and a stunned or locked hero
   cannot; `select ""` is only legal when nothing can be activated.
12. (2026-10-26) A hero in its start zone reaches no hex (`reaches_hex` false, as `in_range`):
   a [Range] effect from there has no target. An Action whose first effect has nothing to work
   on (no hex for a wall, no core or hero in reach) is not played: it stays in the hand, costs
   nothing, and the hand shows why (`_play_blocker`).
13. (2026-10-26) A face-down stage turns face up whenever a hero stops on it: a roll, a
   knockback, an effect's move or a swap (`RulesEngine.arrive`).
14. (2026-10-30, playtest) A hero's optional ability ("may", Once Per Turn or not) is used only
   by a hero that acts: the activated hero, or in the Battle phase a hero in the battle being
   fought. Between battles nobody plays cards. A Battle Phase effect aimed at a hero picks among
   that battle's heroes; Remove Evolution only offers heroes with one.
15. (2026-10-30, playtest) A [Range] effect that names the opponent rather than a hero
   (`NO_CLAIM OPP`, `COST OPP`, `CHOOSE OPP`) needs an enemy hero in range. A chosen branch is
   checked in full before its first step runs, so a choice never half happens. FREE_PLAY offers
   only cards that could really go on the hero (`free_play_error`).
16. (2026-10-30, playtest) Battle members: the seed (or the locked group) and the enemies in
   range with it are the starters; then every hero in range with a starter of the other team
   joins, the seed's allies too (`_joiners`). (Marko 2026-11-06, playtest: the opponent's
   activated Zoro stood next to Luffy, a joiner, and was left out.) Then **one chain step**: every
   free hero in range (either way) with an enemy already in the battle joins, once; those pull
   nobody further. Scenario 41.
- JO1-011 "3 copies at once": the third copy of the card played by the same player in the
  same phase also gives +5 DMG (`IF COPIES 3`).
- Stage reveal bonuses last while the hero stays on that stage and it is unclaimed.
- Stage-002 (Elbaph): "players in combat" are the players with a hero on the stage when it is
  revealed; the higher top-card cost gives their heroes there +2000 Power.
- Standard (`MatchSettings.standard()`): map 23×23, physics knockback, cards as printed
  (`range_delta` 0; it was -1 until the cards carried the lower ranges, 2026-10-26).
  `MatchSettings.new()` keeps the cards as printed (map 17) for the scenario tests. Throw distances at full power are
  22 / 18 / 15 / 11 hexes for WT 1–4.
- Claim by Stay needs two Stays in a row: the same activated hero stays on the same stage at
  the end of two consecutive turns (`StageState.stay_hero / stay_turn`, event `stage_stay`).
  The other two claims (two heroes, battle winner) are unchanged.
