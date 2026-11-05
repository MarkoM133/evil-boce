# fx: card effects

Two layers (GDD 14): `FxTextParser` reads the card text written with the phrases from the
card text guide and writes fx lines; a hand-written `fx` field on the card (web app, tab
Effect) replaces that. The game runs the fx (`FxRuntime`). A card with a sentence nobody
understood (`CardDef.unparsed`) is **not ready** and cannot be played until it gets an fx.

## One line per effect

```
WHEN [ONCE] [OPTIONAL] [RANGE] [IF COND [ARG]]: ACTION; ACTION; ...

A `KNOCKBACK` is always a physical hit in the game (GDD 10, 2026-10-26); the card word
stays Knockback, there is no Launch keyword.

ACTION = VERB [TARGET] [ARGS...]
```

Examples: `POSTROLL ONCE OPTIONAL: MOVE SELF 2` (Bucciarati),
`POSTROLL IF ACTIVATED: DAMAGE ALL_OTHER_IN_RANGE 2` (Fugo),
`PASSIVE: BUFF EQUIPPED PWR 1000 PER TRAIT_EQUIPPED {Sword}` (Wado Ichimonji),
`BATTLE IF WIN: DISCARD OPP 1`, `POSTROLL RANGE: CHOOSE OPP [CHARGE ME 2; DISCHARGE OPP 2] [HEAL SELF 3; DAMAGE ENEMY 3]`.

### WHEN

| Word | Action card | Hero, equipment, evolution, assist | Stage |
|---|---|---|---|
| `PLAY` | runs as the card is played, in any card round | runs when the card enters play | – |
| `START` `PREROLL` `ROLL` `POSTROLL` `BATTLE` `END` | may only be played in that phase; runs as played | fires at the start of that phase (or, with `OPTIONAL`, may be used then) | – |
| `PASSIVE` | – | counts while the card is in play (`BUFF`, `DAMAGE_MOD`, `COST`) | counts for heroes standing on the stage |
| `REVEAL` | – | – | runs when the stage is turned face up |

A `ROLL` effect (an Action, or an `OPTIONAL` ability) is offered when the balls stop: the engine
asks each player with one (`roll_offer`), once per stop; the Roll phase has no card round. A stage's `PASSIVE` effect uses `EACH_HERO` = the heroes on it.

Stat boxes (the card's `bonus`, e.g. +2000 Power, +1 DMG, printed on the card, not in its text) are not fx: the
game gives them by itself, never write a BUFF for them. An Action's go to the hero it is played on until the end of
the phase; an Equipment's count while it is equipped. Only what the text adds is fx (a colour bonus such as
"Yellow Bonus: +1 DMG." is `PASSIVE BONUS: BUFF EQUIPPED DMG 1` on Equipment, on top of the boxes). An Action
whose text is only a phase ("Battle Phase:") is such a card: its fx is the WHEN alone (`BATTLE:`), which says
when it may be played. That bare line is only for a card with no effect at all: as soon as the text has an
effect, its line (`BATTLE IF WIN: FULL_HIT OPP`) already says when the card may be played, and a bare `BATTLE:`
beside it is never written.

### Flags and conditions

- `ONCE`: once per turn. `OPTIONAL`: "may"; the player uses it with the `use_ability` move,
  which counts as a turn in the card round. An Action needs no `OPTIONAL` and it changes nothing
  there: playing the card is the "may" (a "Roll Phase:" Action is played from the roll offer, or
  the offer is passed). `RANGE`: `[Range]`, chosen targets, walls and
  cores must be within the hero's range. On an effect that names a player, not a hero (`NO_CLAIM OPP`,
  `COST OPP …`, `DISCHARGE OPP …`), `RANGE` means an enemy hero must be in range for the card to be played; the
  effect then still covers the whole opponent (playtest 2026-10-30). Which hero a card may be played for is
  the card's first tag and colour, read by the game itself: no condition names the hero (`IF HERO` does not exist).
- `IF ACTIVATED`: the hero is this turn's activated hero. `IF WIN`: the effect waits and runs
  only if the hero's side wins the current battle (after damage, before knockback).
  `IF OPP_EQUIPPED {Trait}`: an enemy (in a battle: an enemy in that battle) has equipment
  with that trait. `IF COPIES <n>`: this is at least the n-th copy of the card the player
  played in this phase.
- An assist's `BATTLE` effect runs at the start of every battle with SELF = its player's hero
  in that battle.
- `BONUS [Colour]` (colorless cards, 2026-11-01): the effect counts only when the hero the card
  is played for (SELF: the activated hero, the equipped hero, the hero an assist helps) is one
  of the card's `bonusColors`, or the colour named. A colorless card (`color: "None"`) is
  played for a hero of any colour; the first tag still counts.
- `INSTEAD`: the effect replaces the one right before it on the card when its BONUS and IF
  hold, and is skipped otherwise; it keeps the WHEN of the one before. `PREROLL RANGE: HEAL
  FRIENDLY 3` + `PREROLL RANGE INSTEAD BONUS: HEAL FRIENDLY 4` is "heals 4 HP instead".

Cards the parser cannot read get a hand-written line in `game/data/placeholders/card_fx.json`
until the web app's Effect tab writes `fx` into `cards.json`.

### TARGET

Heroes: `SELF` (the hero the card belongs to: the activated hero for an Action, your hero
in the battle, the hero with the ability, the equipped hero), `EQUIPPED` (same, for
equipment), `ENEMY` / `FRIENDLY` (the player picks one; one candidate is picked for them; `FRIENDLY` is
always another friendly hero, never SELF: "a friendly Hero" on Bon Apetit or Giorno is not the hero the card is
played for, Marko 2026-11-05; with `RANGE` it must be in SELF's range),
`ALL_FRIENDLY`, `ALL_ENEMY`, `ALL_OTHER_IN_RANGE`, `ALL_FRIENDLY_IN_RANGE`, `ALL_HEROES`,
`EACH_HERO` (on a stage: those standing on it), `MOST_HP`, `MOST_PWR` (on a stage; nobody on a tie).
Players: `ME`, `OPP`.

Who a group holds: `ALL_FRIENDLY` and `ALL_ENEMY` are every hero of that side that is not KO, SELF
included in `ALL_FRIENDLY`. `ALL_OTHER_IN_RANGE` and `ALL_FRIENDLY_IN_RANGE` never include SELF ("other
friendly Heroes in range" is `ALL_FRIENDLY_IN_RANGE`). Under `PASSIVE` every group is read live: a hero that
moves into or out of range gains or loses the effect at once.

### VERBS

| Verb | Args | What it does |
|---|---|---|
| `BUFF <t> <STAT> <n> [TURN] [PER <COUNTER> [arg]]` | STAT = PWR DMG KB RNG HP | +n to the stat until the end of the phase (`TURN`: the turn). Under `PASSIVE` it counts live. `PER` multiplies by a counter. |
| `DAMAGE <t> <n|DMG>` | | n damage (`DMG` = the source hero's DMG), through damage modifiers |
| `HEAL <t> <n>` | | up to max HP |
| `MOVE SELF <n>` | | the player picks a free hex up to n steps away (walls and heroes block) |
| `KNOCKBACK <t> <n> [AWAY|TOWARDS]` | | grid knockback from the source hero (`TOWARDS` pulls) |
| `STATUS <t> <NAME> [turns|TURN]` | IMMUNE_KB, STUN, … | status with a timer (`TURN` = this turn) |
| `DAMAGE_MOD <t> <n> [TURN]` | | "takes ±n DMG from all sources"; passive or this turn. Applied to every hit on its own (battle hits, walls, traps, cards, a damage cost), never below 0; on a battle hit only to the part that lands on the hero, not to cards paid from the hand. `DAMAGE … TRUE` skips it |
| `REMOVE_EVO <t>` | | takes the top evolution off |
| `WALL [n]` | | the player picks a free hex (not on a stage) for a 1-hex wall |
| `REVEAL_CORE` / `ACTIVATE_CORE` | | pick a core on the field: turn it face up / put it on SELF |
| `DEACTIVATE_CORE SELF [n]` | | pick n cores on SELF; they go to the inventory to be put back within SELF's range |
| `CHARGE <p> <n>` / `DISCHARGE <p> <n>` | | energy ±n (0 … max) |
| `DRAW <p> <n>` / `DISCARD <p> <n>` | | draw; the discarding player picks the card |
| `COST <p> <n> [{Trait}] [PHASE] [TURN]` | | cards of that player cost ±n (filter by trait or by the card's phase); passive, or this turn |
| `NO_CLAIM <p>` | | that player claims no stage this turn |
| `ROLL_AGAIN` | | the activated hero rolls once more, right away (Roll phase, after the roll); the ball stopping again brings new offers |
| `REVERSE_ROLL` | | the activated hero goes back to where it stood as the Roll phase began; heroes it pushed, cores it picked up and stages it revealed stay ("reverse the roll", "return this hero to where it was before the roll") |
| `COST_DAMAGE <n>` | | additional cost: SELF takes n as the card is played (needs more than n HP) |
| `OWN_COST <n>` | | this card costs ±n, read when its price is worked out (`PLAY BONUS: OWN_COST -1` = "This card costs 1 less to play" for a hero of a bonus colour); never below 1 |
| `CHOOSE <p> [A; B] [C; D]` | | that player picks a branch; its actions run |
| `RECYCLE <p> <n> [TOP|BOTTOM|SHUFFLE]` | | the top n of the graveyard go back into the deck |
| `PICK_CORE` | | pick a core on the field (in range with `RANGE`); `MOVE_CORE` / `TRAP_CORE` use it |
| `MOVE_CORE <n>` | | the picked core moves up to n hexes (free hex, not on a stage) |
| `TRAP_CORE <n>` | | an enemy hero that activates the picked core this turn takes n |
| `HOLD_HIT SELF` | | with `BATTLE IF WIN`: after winning, the owner may deal no DMG and double the Knockback |
| `FULL_HIT OPP` | | with `BATTLE IF WIN`, on a line of its own: if the card's hero wins this battle, its hit lands whole on the loser's hero, none of it on cards from the hand (the hit already only goes to a hero of this battle). The line arms as the card is played and counts only on a win |
| `NOOP` | | nothing (a "no" branch) |
| `FREE_PLAY <max cost> [{Trait}] [Type]` | | play a card from the hand on SELF without paying (colour rules do not apply); `Type` limits it to Action, Equipment or Assist |
| `SWAP FRIENDLY [ENGAGED]` | | SELF and a friendly hero trade hexes (`ENGAGED`: one an enemy reaches or that reaches an enemy) |
| `DUEL_TOP <STAT> <n>` | | stage: players with heroes on it show their top card; the higher cost gets +n for its heroes there |

Extra arguments: `DAMAGE … TRUE` ignores damage modifiers ("cannot be blocked");
`DEACTIVATE_CORE SELF <n> UPTO` lets the player pick how many (0 … n), and `PER COUNT` in a
later `BUFF` multiplies by that number. `MOVE` with a group target asks every hero in turn
(its own hex = stays). A stage's `REVEAL` bonus counts while the hero stays on that stage
and it is unclaimed (`GameState.stage_buffs`); once the hero leaves, it is gone.

Counters for `PER`: `TRAIT_EQUIPPED {Trait}` (equipment with the trait on the target, the card itself included),
`CORES` (cores on the target), `MISSING_HP <n>` (per n HP missing), `ENERGY` (the owner's
energy), `LOW_HP_FRIENDLY <n>` (the owner's heroes with ≤ n HP, the hero itself included, KO heroes not), `LOW_HP_OTHER_FRIENDLY <n>` (the same without the hero whose effect it is: "every other friendly Hero").

## Choices

When an effect needs a decision, the engine pushes `{"type": "choose", "player", "kind":
"hero"|"hex"|"core"|"card"|"option", "options": [...], "prompt", "resume": {...}}` onto
`state.pending` and waits for `choose {"value": ...}` from that player (an index for `option`).
The effect continues from where it stopped; the state can be saved in between.

## What the parser reads today

Phase prefixes, `Once Per Turn`, `may`, `[Range]`, `If <hero> is activated`, `While <hero> is
activated`, `If you win this Battle`, `When this Stage is revealed`, `Terrain:` lines (data,
not an effect); stat bonuses with `for every …` and `until the end of the turn`; `takes N DMG`,
`takes ±N DMG from all sources`; heals; `move up to N spaces`; `Knockback an Opponent's Hero N
spaces …`; `move N spaces towards you`; `immune to Knockback`; `Place a Wall`; `Reveal /
activate / deactivate a Core`; `charge / discharge N Energy`; cost changes; `roll … again`;
`discard a card`; `remove an Evolution`; `cannot take a Stage`; `the Opponent's Hero in this Battle takes all
of the damage` (`FULL_HIT`; a sentence `Your Opponent can't discard cards to reduce it` after it is skipped); `As an additional cost, take
N DMG` (or `…, your Hero takes N DMG`: `COST_DAMAGE`); `Your Opponent chooses:` with two dashed lines. Clauses joined by "and" are read one by
one. Colour bonus lines of colorless cards (`Red Bonus: …`, `Cyan / Purple Bonus: …`): `This
card costs N less to play` (`OWN_COST`), `+N STAT` (a buff on the card's hero), `It also …` /
`You also …` and `… gets / gains / heals / takes an additional …` (an extra effect with the WHEN
and the condition of the sentence before), `It … N … instead` (the
sentence before with its number swapped, `INSTEAD`). Everything else lands in `unparsed`;
`tests/test_fx_parser.gd` lists the exact phrases.
