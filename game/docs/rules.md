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

## Energy claims (`MatchSettings.stage_claim = "energy"`; the default until 2026-11-10, now an option)

From Marko (2026-11-02); the default of Standard and every mode from 2026-11-02 until the shared ring
took over on 2026-11-10 (below). It stays an option (Separate in the rules panel), as do the Stay
claims. `MatchSettings.new()` keeps Stay, which the scenario tests use. `stage_goal` (default 14) is
the energy a stage needs.

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
- A claimed stage remembers who took it: `StageState.claimed_heroes`, the heroes of the claiming
  side standing on it at the claim (also `heroes` in the `stage_claimed` event; empty when none
  stood there, as with a claim that was held back). Only the picture uses it: the logos on the
  stage's flag (scenario 70).
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

### The shared ring (`stage_claim = "ring"`, Standard's rule since 2026-11-10)

The default of Standard and every mode since 2026-11-10 (Marko), with separate energy and Stay
still offered in the rules panel; in the GDD as the rule, marked as still to be played by hand.
Rules saved before that day follow, since only what differs from Standard is stored. Everything
above holds (`energy_claims()` is true for it too) except how energy goes in
(`_put_energy_ring`):

- A stage has one ring of `stage_goal` places for both sides; `ring_free` is what is empty.
- Energy fills the empty places first. With none left, each energy turns one place of another team
  into the player's own (from whoever holds the most; event `stage_energy` carries `taken`).
- A team holding the whole ring claims the stage (`stage_energy_of_team`); what is left over is lost.
- Knocked off stays: half the player's energy there goes, and those places are empty again.
- Decided (2026-11-10): energy left on a stage does not fade; a knock-off empties, it does
  not hand places to the other side; the goal stays 14; a place taken counts as energy invested for
  the tie-break; in 2v2 the ring is per team.
- The cards that touch claims, gone through under the ring (2026-11-13, scenarios 71 to 76; nothing had to change):
  - "can't claim" (`NO_CLAIM`, on heroes or on the player): the energy still goes in and may fill the ring; the claim
    is held back and looked at again in every later End phase. Until then the ring is open: the other side alone on
    the stage takes places with its energy before the claim is looked at (all energy goes in first, then claims), and
    a knock off halves it. A full ring claims whether or not its side still stands there.
  - a card that sends an enemy off its stage (`KNOCKBACK` away or towards) or knocks it out there costs that player
    half, as a battle's knockback does; a move or swap by its own side (`MOVE`, `SWAP`) costs nothing.
  - energy a card gives or takes before the End phase (`CHARGE`, `DISCHARGE`, up to `max_energy`) is what goes in.
- Scenarios 67 and 68. Compare with `tools/bot_games.gd --claim=ring`.
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
  `evo` must be the next one. Stats and abilities come from the evolution card alone (the
  ability of the card under it is off: `FxRuntime.sources` takes `stat_card`, scenario 66);
  damage carries over (new max − damage taken). `remove_evolution()` drops HP only down to the new max.
- **Assist**: at most `assist_limit` (3) per player, the same card once; a fourth needs
  `replace` (an assist in play that goes to the graveyard).
- **Action**: plays its bonus (lasting until the end of the phase, `HeroState.phase_bonus`) and its fx
  effects (docs/fx-keywords.md); a card with neither is refused ("card effects are not ready yet").
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
- A combo is a bonus on top of its two cards, not a replacement (Marko 2026-11-21; until then it replaced
  them). When: in a battle's card round, `play_card` of the second card of a combo's pair. The card is played
  and resolves as ever; then, when the first card was played this battle by the same player, is not in a
  combo yet, and the player can pay X, the move puts `combo_offer {player, card, hero, combos: [{id, with,
  with_hero, extra}]}` on `pending`, behind the choices the card itself asked for.
- The pair, by the Combo card's kind (`comboKind`, Marko 2026-11-22; `CardDef.combo_kind`): a **team** combo is two cards played for two different heroes of the player, who has two or more heroes in the battle
  (an Assist pairs with any); a **solo** combo (the default: a Combo card without the team mark) is both cards played for the same hero. The same holds when the
  pair is two copies of one card (`ingredients: [id, id]`). A solo combo so works for one hero, a team combo for
  both.
- `choose {value: combo id}` accepts: X is paid, both records are marked used, event `combo`, and the Combo
  card comes on top: its stat boxes go on both heroes the cards were played for (one hero, when it played
  both), and its `BATTLE:` lines run like an Action's. A line that speaks of "your Hero" (target SELF,
  COST_DAMAGE, a BONUS, IF ACTIVATED) runs once for each of those heroes, so each pays the additional cost
  and each is checked for the bonus; a line with targets of its own (ALL_FRIENDLY_IN_BATTLE, ENEMY…) runs
  once, for the second card's hero. A combo whose additional cost a hero cannot pay (COST_DAMAGE needs more
  HP than it takes) is not offered. `choose {value: ""}` or `pass` declines: nothing changes.
- Same combo again: any time the condition holds. A card may be in several combos; all that fit are offered.
- `ALL_FRIENDLY_IN_BATTLE`: every hero of the card's player in the battle the context names, else the one
  being fought. Scenarios 57, 58, 87 (a solo combo: two copies, one hero, tag bonus) and 88 (a team combo: both heroes); the bot takes the first combo on offer.
- Match scene (no rules): the offer dialog shows the combo card above its buttons. Event `combo` shows the
  combo card over the screen (`MatchHud._combo_show`, queued with the bands; a click or Enter skips it).
  The pause menu's right side has tabs MATCH LOG and COMBO LIST (when there are combos); COMBO LIST shows the
  pictures of each combo and its two cards, and the combos this screen's deck can make, or every combo (ALL); it reads
  the deck from the match record, or the deck an online guest sent (`NetClient.my_deck`), never the
  opponent's.

## Token cards (decided and built 2026-11-14)

- Data: a card with `"token": true` (`CardDef.token`), an Action only (another type is not ready). Its id is its
  maker's with a number (`DQ1-010-1`). `FirstTag.deck_verdict` refuses it, so no deck, sideboard, random deck or
  Draft pack holds one (`js/tags.js` has the same line).
- Made by fx `TOKEN <ME|OPP> <id> [n]` (`RulesEngine.make_token`, event `token {player, card, amount}`): the cards
  go to `PlayerState.tokens`, beside the hand. A `TOKEN` on an `END` or `PASSIVE` line is not read (the card is
  not ready), and nothing is made while the phase is End.
- Played with `play_card` like a card from the hand: the same colour, first tag, phase and cost rules; a roll
  offer lists a `ROLL` token; `PlayerState.playable_cards()` is the hand plus the tokens (the bot and auto-pass
  use it). Played, it is gone: event `action` carries `"token": true` and nothing goes to the graveyard.
- It is not a card in the hand: `hand` and every count of it leave tokens out, a `DISCARD` does not see them, a
  lost battle or a ring-out cannot be paid with one (a hand of tokens only is an empty hand), `FREE_PLAY` does not
  offer them, and a combo that lists one is never offered.
- Everyone sees them: `NetProtocol.redact` leaves `tokens` as they are (the hand stays a count).
- The end of the turn (`_end_phase`, before `turn_end`) removes what nobody played: event `tokens_gone {player,
  cards}`.
- Records: `MatchRecorder._used_cards` adds the tokens the match's cards can make (`CardDef.tokens_made`), so a
  match carried on from its record knows them.
- Card text: "Create a Spark Token." / "Create 2 Spark Tokens." (`FxTextParser`, the name kept aside before the
  card's own name becomes SELF); `CardCatalog.resolve_tokens` then swaps the name for the token card's id
  (`token_named`: the maker's own token first, one card of that name otherwise). No such card, or a line the fx
  language refuses (a token in the End phase), leaves the card not ready.
- Decided by Marko 2026-11-14: a free play from the hand (`FREE_PLAY`) never plays a token; `TOKEN OPP` stays in
  the language.
- Scenarios 81 and 82, `tests/test_tokens.gd`.
- Match scene (no rules): your tokens stand right of your hand, a little apart, in a drifting violet mist with a
  glow (`ui/token_mist.gdshader`; still on low quality or fast animations); a new one comes out of the mist, a
  played or ended one dissolves into it. The other side's tokens are violet chips under its counts (a click shows
  the card); the hand count leaves them out. A token is never picked to pay damage. Screenshot helpers
  `demo_tokens`, `demo_tokens_gone` (after `demo_battle`, `demo_hand_stand`).
- Card Studio: New token on the maker's page (id = maker + number), violet frame and the hourglass mark from the
  renderer, tokens follow their card in a code move, never a combo ingredient.

## Fire terrain, terrain from a card, ignoring terrain (decided and built 2026-11-22)

- **Fire** is a fifth terrain (`Terrain.Type.FIRE`). It leaves the roll alone. As the End phase starts (`_set_phase`, before
  the End effects, the energy claims and the win check) each hero standing on it takes `FIRE_DAMAGE` (1), through
  `hero_damage` with `by: "fire"`, after a `burn` event.
- A card can put a terrain on a stage (`TERRAIN <name>`): `StageState.terrain_override` replaces the stage card's own
  terrain in `terrain()` (`stage_terrain`). It fades after a claim like any terrain.
- A hero that **ignores terrain** (`PASSIVE: STATUS SELF IGNORE_TERRAIN`, `ignores_terrain`): Fire does not burn it and
  the sim rolls its ball as on plain ground (`BallBody.ignores_terrain`, set by the match from the state; the bot's
  `TerrainPhysics.roll_path` takes the same flag). A Ramp still moves it.
- A status on a `PASSIVE` line holds while its card is in play: the engine asks `has_status(s, h, name)` (the hero's own
  statuses, then `FxRuntime.passive_status`), so "X is immune to Knockback" on an Evolution now works.
- Tests: `tests/test_dq1_fx.gd` (the DQ1 words are tested there on small cards written as card text).

## What the DQ1 set added to the engine (built 2026-11-22)

The fx words are in `docs/fx-keywords.md` ("Words that came with DQ1"); the open readings in `docs/pitanja.md`. In
the engine:

- **State.** `GameState.turn_plays` (every card played this turn: player, card, hero, phase, battle),
  `GameState.battle_snapshot` (where every hero stood as the Battle phase began), `StageState.terrain_override` and
  `cursed_by`, `HeroState.stun_by`. A battle's `played` entries carry `gave_phase` / `gave_turn` (the bonuses the card
  put on its hero) and `negated`. All of it is in the save and the net state.
- **As the End phase starts** (`_set_phase`, in this order, before the End effects and the claims): Fire burns
  (`_burn`), doomed heroes go down (`_doom`), heals put off till then land (`_late_heals`), heroes go back to where the
  Battle phase found them (`_returns`).
- **Playing a card** (`_play`): a REQUIRE line is checked first (`_requirement`); a line that is only a cost is
  followed by a check that the next line can start (`_play_blocker`, `_only_costs`); no cards for a hero with the
  passive status NO_CARDS; no Battle Phase cards for a hero on a stage cursed by another side; an Evolution or an
  Equipment with COST_DAMAGE takes it as it goes on; an Equipment with EQUIP_OTHER goes on another hero (the move's
  `wearer`); a bonus line that says "instead" after a bare phase line replaces the stat box (`FxRuntime.box_replaced`);
  after the card's own effects the cards that were in play as it was played get `FxRuntime.on_card_played`.
- **Costs** (`card_cost`): `FxRuntime.cost_mod` takes the hero the card is for; a combo's extra energy goes through
  `combo_cost`.
- **Damage** (`hero_damage`): none for a hero of stone; a hit bought off (`prevent`) does nothing; a hero that would
  go down asks `FxRuntime.save_from_ko` first. `ko_hero` is a KO by a card, as a hit for all the HP.
- **Battles**: before a hit is offered to the loser, `FxRuntime.offer_shields`; a side with a FLEE hero cannot win, its
  hero is not hit and is ringed out in `_finish_battle`; effects that wait for the battle (`FxEffect.waits_for_battle`:
  WIN, WIN_ALLY, LOSE_BELOW) are settled in `FxRuntime.on_battle_done`.
- **Tags**: `gained_tags`, `hero_has_tag`, `hero_is`; `CardDef.has_trait` reads each part of a tag joined by "&".
- **Rolling**: a hero with NO_ROLL is left out of `_rollers`; a thrown hero with the passive status BRITTLE loses its
  Evolution in `apply_roll`.
- **Deck check**: a card whose first tag no hero of the deck carries may still go in when the deck holds a card that
  gives that tag in the match (`FirstTag.tags_given`, read by `deck_verdict` from the cards `evolutions_in` returns; the
  refusal names the cards that would let it in).
- **An action that needs several answers** hands the rest of its effect on to an effect of its own
  (`FxRuntime._hand_on`): which cards go back (RECYCLE with a tag), which heroes pay (PAY_HP).
- **Not built**: the HUD's own words for the new events (`burn`, `terrain`,
  `stunned`, `saved`, `card_undone`, `stage_cursed`, `stage_drained`, `assist_gone`, `card_shown` …) and a way to
  name the `wearer` when several heroes fit.
- `tools/bot_games.gd --drafts[=<id prefix>]` plays the Card Studio drafts too, so a set can be run through whole
  matches before it is published.

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
- Damage reduction (`DAMAGE_MOD` with a negative number) never brings a hit under 1
  (`RulesEngine.MIN_HIT`; Marko 2026-11-08: Kaido's -1 made a ring-out free). Extra
  damage taken adds as before, and `DAMAGE … TRUE` still skips the modifier. Scenario 64.
- An activated hero that leaves the map mid-turn (KO or ring-out) leaves its player with Pass
  or an Assist (`RulesEngine.pass_only`, from `GameState.only_pass` and `only_pass_battle`;
  Marko 2026-11-13): no Action, Equipment or Evolution and no ability. Outside the
  Battle phase that holds until the turn ends; in the Battle phase only in the battle it fell
  in, and in the battles after it the player's other heroes play as ever (all of them when it
  fell before the Battle phase). An Assist is played in the colour of the activated hero, gone
  or not. No Roll Phase offer either (Marko 2026-11-08: a ringed-out hero rolled back in with
  its own ROLL_AGAIN ability). Scenarios 63 and 80, `test_pass_only.gd`.
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
   {hero, targets}`; online playtest 2026-11-07). Scenario 60. A ring-out's own cost is not such a
   hit: its hero is on its strip by then, and the choice waits until it is made or the hero is
   knocked out (two ring-outs in one roll both pay, scenario 69). Damage from cards ("take 3 DMG")
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
   Placing by hand looks ahead (Marko 2026-11-13: the sixth stage had no legal hex and the bot stood still):
   a spot after which the stages (or the cores of that half) still to come would not all fit is refused
   ("no room would be left for the stages still to come"), so every piece always gets out. `SetupFit` does the
   search; `stage_placement_error` / `core_placement_error` with no gap given are that rule, and what the
   table lights, the bot and the timer use. When the map cannot hold them at the match's gap at all (odd custom
   rules), nothing is looked ahead and a piece with no spot is placed at the widest smaller gap that has one
   (`stage_setup_gap`, `setup_gap_relaxed` in the log). Random placement is unchanged.
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
   shuffled deck: a random draw with the same copies and limits.
9c. (2026-10-26) Knockback mode `knockback`: "physics" (the game, 2026-10-26: every
   knockback is a real hit; the word on the cards stays Knockback) or "grid" (hex by hex, as
   above: the engine on its own, as in the scenario tests; not offered in MATCH RULES). A physics knockback is not applied by the
   engine: it waits in `GameState.pending_knockbacks` ({hero, dir, steps}), `_continue` stops
   and every move is refused with "waiting for the knockback" until the scene runs the sim
   (hit along the hex direction, power = steps / full-power hexes of the WT) and brings the
   `RollOutcome` to `apply_knockback`. The outcome lands every moved ball as a roll does
   (cores, stages, ring-outs); the balls and walls it hit are counted (`knockback.hits`) but cost
   nothing (Marko 2026-11-07: no wall damage any more; a ring-out costs 1 DMG, see below).
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
   the hero's current card (the last evolution, else the base). (2026-11-16) A trait is any tag some
   Hero or Evolution card of the catalog carries, of any colour: no list names it (data/traits.json
   only describes tags now, and `CardCatalog.trait_names` is not read by the rule). A tag nobody
   carries is invalid. The spelling in messages is the one on the first card that carries it. `_play` refuses the others
   ("only for X", "Requires T"); equipment whose tag the hero no longer fits falls into the
   graveyard when an evolution comes or goes (`_drop_unfit_equipment`). A record still carries
   the list of described tags, which no longer changes how it replays (its own heroes and
   evolutions carry the tags its cards were played by). `{Sword}` effects count equipment cards, never a hero's trait.
   (2026-11-15) "&" joins traits too, and heroes with traits: each part is a hero first, else a
   trait, and any one of them is enough ("Mage & Brave Hero", "Dai & Mage"). `kind_of` gives
   `heroes`, `traits` and `unknown` for every tag; the kinds are heroes (only heroes), trait (only
   traits, one or more), mixed (both). A part that is neither is skipped while another counts.
   Refusals: "only for X", "Requires T or U", "only for X, or Requires T" in play; in a deck
   "needs a Red hero with T or U", "only for X, or a Red hero with T".
9i. (2026-11-21) Companions (`CompanionState`, `GameState.companions`, at most one per player; the first is
   Coco Jumbo): a token on a hex, not a hero. Its Assist's fx puts it down (`PLAY: COMPANION`, a free hex
   next to the hero, never on a core, wall, hero or another companion; with no room next to it, the nearest
   ring that has a free hex, and the player picks among those: `companion_spots`, Marko 2026-11-22) and it lives while that Assist is in
   play (`_sync_companions` on every step of `_continue`); replaced or fallen, its Assist goes to the
   graveyard. Its hex is taken for heroes (`GameState.is_free`), cores and walls. The sim reports a pushed
   companion as a `RollResult` under the companion's id (`companion:<slot>`): it rests on `end_hex`, and off
   the map, into a strip or out it falls (`companion_falls`). Without such a result (the analytic roll, grid
   knockback) it stays, and a hero that stopped on its hex pushes it to the nearest free one
   (`_unstack_companions`). Hiding (`HIDE`): the hero's zone becomes `shelter`: `is_on_map()` is false, so
   range, battles, stages and targets leave it out; `FxRuntime.sources` skips it and its equipment; the
   groups ALL_FRIENDLY / ALL_ENEMY skip it; `_lost_active` puts its player on Pass or an Assist when it was
   the activated hero. It leaves a stage as by its own doing (no energy lost). Activating it (`select`)
   puts it on one of its exits first (`leave_shelter`): the free hexes nearest to the companion
   (`shelter_exits`: next to it when there is room, else the nearest ring that has one; Marko 2026-11-22). The
   move's `hex` picks which and must be one of them; without it, the first. Fallen with a hero inside:
   `ring_out(hero, "companion")`, the usual 1 DMG or a card, back to the start zone. Its Assist gone any
   other way: the hero comes out on the companion's hex, unhurt. `WANDER` runs with the Assist's END effects,
   before the turn ends. Events: `companion`, `companion_moved` (why: wander | pushed), `companion_gone`
   (why: assist | replaced | fell), `companion_fell`, `sheltered`, `left_shelter`.
   Assumptions: a hero locked in a tie cannot hide; a hidden hero keeps its cores, equipment, evolutions and
   statuses (they tick as ever) and cannot be damaged or healed by cards (it is no target); the companion
   never rests on a core's hex; grid knockback treats a companion's hex as taken (the hero stops before it).
9g. (2026-11-01) Colorless cards: `color: "None"` passes the colour check in `deck_verdict`
   and `_play` (the first tag still counts), and `bonusColors` on the card drive the fx
   `BONUS` / `INSTEAD` effects and `OWN_COST` (docs/fx-keywords.md). The Draft counts a
   colorless card as a card of any colour.
g. (2026-10-26) A grid knockback stopped by a wall or a hero just stops (no damage since
   2026-11-07). A Wind stage draws its direction (`StageState.wind_dir`, one of six) when it is
   revealed; `terrain()` blows that way and the state and the replay keep it.
9h. (2026-11-15) Temporary evolutions: an Evolution card with `tempTurns` n (`CardDef.temp_turns`) is not a
   level. It sits in `HeroState.temp_evo` over whatever `evolutions` holds, with `temp_until` = the turn at whose
   end it goes (played in turn t: t + n − 1, so 1 = this turn). `stat_card` reads it first, so stats, ability and
   traits are its own while it lasts. Playing: any level of its hero (no level check); a new temporary one
   replaces the old; an evolution that stays takes the temporary one off and goes on the level under it
   (`evolutions.size() + 1`, counted without it). `remove_evolution` (the REMOVE_EVO verb) takes the temporary
   one first. `_end_phase` drops those whose turn is up (`_expire_temp_evolutions`, before the tokens go); a KO
   sends it to the graveyard. HP (Marko 2026-11-15): the damage is remembered both ways (new max − damage when it
   comes and when it goes, so 10/12 → 6/8 → 10/12), and the change itself never kills (1 HP at least).
   Equipment (Marko 2026-11-15): while the form lasts nothing falls; equipment whose first tag the form does
   not satisfy stays on but does not work (`equipment_works`: no stat bonus, not a source of effects), and
   `_drop_unfit_equipment` looks again when the form is gone. Such equipment still counts as equipped (the
   limit of 3, TRAIT_EQUIPPED and the like; Marko 2026-11-16). Events: `evolved` with
   `temporary: true, until`; `evolution_removed` with `temporary: true, why` (expired, replaced, evolved, removed).
   Scenarios 83 and 84, tests/test_temp_evolution.gd.
10. (confirmed 2026-11-11) `REVERSE_ROLL` puts the activated hero back where it stood when the Roll phase began
   (`GameState.roll_snapshot`); pushed heroes, picked cores and revealed stages stay.
11. (confirmed 2026-11-11) A hero in the start zone can be activated at any time, and a stunned or locked hero
   cannot; `select ""` is only legal when nothing can be activated.
12. (2026-10-26, confirmed 2026-11-11) A hero in its start zone reaches no hex (`reaches_hex` false, as `in_range`):
   a [Range] effect from there has no target. An Action whose first effect has nothing to work
   on (no hex for a wall, no core or hero in reach) is not played: it stays in the hand, costs
   nothing, and the hand shows why (`_play_blocker`).
13. (2026-10-26, confirmed 2026-11-11) A face-down stage turns face up whenever a hero stops on it: a roll, a
   knockback, an effect's move or a swap (`RulesEngine.arrive`).
14. (2026-10-30, playtest; confirmed 2026-11-11) A hero's optional ability ("may", Once Per Turn or not) is used only
   by a hero that acts: the activated hero, or in the Battle phase a hero in the battle being
   fought. Between battles nobody plays cards. A Battle Phase effect aimed at a hero picks among
   that battle's heroes; Remove Evolution only offers heroes with one.
15. (2026-10-30, playtest; confirmed 2026-11-11) A [Range] effect that names the opponent rather than a hero
   (`NO_CLAIM OPP`, `COST OPP`, `CHOOSE OPP`) needs an enemy hero in range. A chosen branch is
   checked in full before its first step runs, so a choice never half happens. FREE_PLAY offers
   only cards that could really go on the hero (`free_play_error`).
16. (2026-10-30, playtest; confirmed 2026-11-11) Battle members: the seed (or the locked group) and the enemies in
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
