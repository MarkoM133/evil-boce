# fx: card effects

Two layers (GDD 14): `FxTextParser` reads the card text written with the phrases from the
card text guide and writes fx lines; a hand-written `fx` field on the card (web app, tab
Effect) replaces that. The game runs the fx (`FxRuntime`). A card with a sentence nobody
understood (`CardDef.unparsed`) is **not ready** and cannot be played until it gets an fx.

## One line per effect

```
WHEN [ONCE] [OPTIONAL] [RANGE] [IF COND [ARG]]: ACTION; ACTION; ...
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
| `PREROLL` `ROLL` `POSTROLL` `BATTLE` `END` | may only be played in that phase; runs as played | fires at the start of that phase (or, with `OPTIONAL`, may be used then) | – |
| `PASSIVE` | – | counts while the card is in play (`BUFF`, `DAMAGE_MOD`, `COST`) | counts for heroes standing on the stage |
| `REVEAL` | – | – | runs when the stage is turned face up |

A `ROLL` effect on an Action may be played after the roll (that is when the Roll card round
happens). A stage's `PASSIVE` effect uses `EACH_HERO` = the heroes on it.

### Flags and conditions

- `ONCE`: once per turn. `OPTIONAL`: "may"; the player uses it with the `use_ability` move,
  which counts as a turn in the card round. `RANGE`: `[Range]`, chosen targets, walls and
  cores must be within the hero's range.
- `IF ACTIVATED`: the hero is this turn's activated hero. `IF WIN`: the effect waits and runs
  only if the hero's side wins the current battle (after damage, before knockback).
  `IF OPP_EQUIPPED {Trait}`: an enemy (in a battle: an enemy in that battle) has equipment
  with that trait. `IF COPIES <n>`: this is at least the n-th copy of the card the player
  played in this phase.
- An assist's `BATTLE` effect runs at the start of every battle with SELF = its player's hero
  in that battle.

Cards the parser cannot read get a hand-written line in `game/data/placeholders/card_fx.json`
until the web app's Effect tab writes `fx` into `cards.json`.

### TARGET

Heroes: `SELF` (the hero the card belongs to: the activated hero for an Action, your hero
in the battle, the hero with the ability, the equipped hero), `EQUIPPED` (same, for
equipment), `ENEMY` / `FRIENDLY` (the player picks one; one candidate is picked for them),
`ALL_FRIENDLY`, `ALL_ENEMY`, `ALL_OTHER_IN_RANGE`, `ALL_FRIENDLY_IN_RANGE`, `ALL_HEROES`,
`EACH_HERO` (on a stage: those standing on it), `MOST_HP`, `MOST_PWR` (on a stage; nobody on a tie).
Players: `ME`, `OPP`.

### VERBS

| Verb | Args | What it does |
|---|---|---|
| `BUFF <t> <STAT> <n> [TURN] [PER <COUNTER> [arg]]` | STAT = PWR DMG KB RNG HP | +n to the stat until the end of the phase (`TURN`: the turn). Under `PASSIVE` it counts live. `PER` multiplies by a counter. |
| `DAMAGE <t> <n|DMG>` | | n damage (`DMG` = the source hero's DMG), through damage modifiers |
| `HEAL <t> <n>` | | up to max HP |
| `MOVE SELF <n>` | | the player picks a free hex up to n steps away (walls and heroes block) |
| `KNOCKBACK <t> <n> [AWAY|TOWARDS]` | | grid knockback from the source hero (`TOWARDS` pulls) |
| `STATUS <t> <NAME> [turns|TURN]` | IMMUNE_KB, STUN, … | status with a timer (`TURN` = this turn) |
| `DAMAGE_MOD <t> <n> [TURN]` | | "takes ±n DMG from all sources"; passive or this turn |
| `REMOVE_EVO <t>` | | takes the top evolution off |
| `WALL [n]` | | the player picks a free hex (not on a stage) for a 1-hex wall |
| `REVEAL_CORE` / `ACTIVATE_CORE` | | pick a core on the field: turn it face up / put it on SELF |
| `DEACTIVATE_CORE SELF [n]` | | pick n cores on SELF; they go to the inventory to be put back within SELF's range |
| `CHARGE <p> <n>` / `DISCHARGE <p> <n>` | | energy ±n (0 … max) |
| `DRAW <p> <n>` / `DISCARD <p> <n>` | | draw; the discarding player picks the card |
| `COST <p> <n> [{Trait}] [PHASE] [TURN]` | | cards of that player cost ±n (filter by trait or by the card's phase); passive, or this turn |
| `NO_CLAIM <p>` | | that player claims no stage this turn |
| `ROLL_AGAIN` | | the activated hero rolls once more, right away (Roll phase, after the roll) |
| `COST_DAMAGE <n>` | | additional cost: SELF takes n as the card is played (needs more than n HP) |
| `CHOOSE <p> [A; B] [C; D]` | | that player picks a branch; its actions run |
| `RECYCLE <p> <n> [TOP|BOTTOM|SHUFFLE]` | | the top n of the graveyard go back into the deck |
| `PICK_CORE` | | pick a core on the field (in range with `RANGE`); `MOVE_CORE` / `TRAP_CORE` use it |
| `MOVE_CORE <n>` | | the picked core moves up to n hexes (free hex, not on a stage) |
| `TRAP_CORE <n>` | | an enemy hero that activates the picked core this turn takes n |
| `HOLD_HIT SELF` | | with `BATTLE IF WIN`: after winning, the owner may deal no DMG and double the Knockback |
| `NOOP` | | nothing (a "no" branch) |
| `FREE_PLAY <max cost> [{Trait}]` | | play a card from the hand on SELF without paying (colour rules do not apply) |
| `SWAP FRIENDLY [ENGAGED]` | | SELF and a friendly hero trade hexes (`ENGAGED`: one an enemy reaches or that reaches an enemy) |
| `DUEL_TOP <STAT> <n>` | | stage: players with heroes on it show their top card; the higher cost gets +n for its heroes there |

Extra arguments: `DAMAGE … TRUE` ignores damage modifiers ("cannot be blocked");
`DEACTIVATE_CORE SELF <n> UPTO` lets the player pick how many (0 … n), and `PER COUNT` in a
later `BUFF` multiplies by that number. `MOVE` with a group target asks every hero in turn
(its own hex = stays). A stage's `REVEAL` bonus counts while the hero stays on that stage
and it is unclaimed (`GameState.stage_buffs`); once the hero leaves, it is gone.

Counters for `PER`: `TRAIT_EQUIPPED {Trait}` (equipment with the trait on the target),
`CORES` (cores on the target), `MISSING_HP <n>` (per n HP missing), `ENERGY` (the owner's
energy), `LOW_HP_FRIENDLY <n>` (the owner's heroes with ≤ n HP).

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
`discard a card`; `remove an Evolution`; `cannot take a Stage`; `As an additional cost, take
N DMG`; `Your Opponent chooses:` with two dashed lines. Clauses joined by "and" are read one by
one. Everything else lands in `unparsed`; `tests/test_fx_parser.gd` lists the exact phrases.
