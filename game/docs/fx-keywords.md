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

Examples: `POSTROLL ONCE OPTIONAL IF ACTIVATED: MOVE SELF 2` (Bucciarati, "If Bruno Bucciarati is activated, he may move up to 2 spaces"; an OPTIONAL ability is usable by the activated hero only, so IF ACTIVATED just says what the text says),
`POSTROLL IF ACTIVATED: DAMAGE ALL_OTHER_IN_RANGE 2` (Fugo),
`PASSIVE: BUFF EQUIPPED PWR 1000 PER TRAIT_EQUIPPED {Sword}` (Wado Ichimonji),
`BATTLE IF WIN: DISCARD OPP 1`, `POSTROLL RANGE: CHOOSE OPP [CHARGE ME 2; DISCHARGE OPP 2] [HEAL SELF 3; DAMAGE ENEMY 3]`.

### WHEN

| Word | Action card | Hero, equipment, evolution, assist | Stage |
|---|---|---|---|
| `PLAY` | runs as the card is played, in any card round | runs when the card enters play | – |
| `START` `PREROLL` `ROLL` `POSTROLL` `BATTLE` `END` | may only be played in that phase; runs as played | fires at the start of that phase (or, with `OPTIONAL`, may be used then) | `BATTLE` only: fires at the start of every battle fought on the stage (a hero of the battle stands on it), for the players in that battle (Elbaph, 2026-11-05) |
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
  the offer is passed). `RANGE`: a condition on the targets, not on the whole effect (range rule B, Marko
  2026-11-05: the card text says it next to the target, "a friendly Hero in Range", "an Opponent's
  Hero in Range", "a Core in Range", "Place a Wall … in Range"; there is no RANGE chip and no "[Range]" at
  the start any more). With `RANGE` the chosen targets, walls and cores must be within SELF's range. On an
  effect that names a player, not a hero (`COST OPP …`, `DISCHARGE OPP …`, `CHOOSE OPP …`), the text says
  "If an Opponent's Hero is in Range, …" and `RANGE` means an enemy hero must be in range for the card to be
  played; the effect then covers the whole opponent (Observation Killing; Soul Pocus is not played without
  an enemy in range). A card whose first action targets `ALL_ENEMY_IN_RANGE` is not played either when no
  enemy hero is in range (Conqueror's Haki, Marko 2026-11-07); `RANGE` on such a line adds nothing. "an Opponent's Hero's Range" is the enemy's range, not SELF's (Intercept: a friendly
  hero an enemy reaches). `deactivate a Core` is a core on that hero (`DEACTIVATE_CORE SELF`); `activate a
  Core in Range` is a core on the field (`ACTIVATE_CORE` with `RANGE`). Targets are chosen by the player who
  plays the card unless the text says otherwise; a colour bonus looks at the hero the card is played for; a
  discount never takes a card's cost below 1. Card text wording (gain / lose Energy, names only on Hero and
  Evolution cards) is in the private text guide. Which hero a card may be played for is
  the card's first tag and colour, read by the game itself: no condition names the hero (`IF HERO` does not exist; a bonus for one hero is `BONUS {Tag}`).
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
- `BONUS {Tag}` (Marko 2026-11-21): the same, for a hero rather than a colour: the hero the card is played for
  is called that (its name or an alias), or the card it plays as now carries the tag, read as the first tag
  is. `BATTLE BONUS {Flazzard}: BUFF SELF DMG 2`. Card text: "{Flazzard} Bonus: +2 DMG." A tag with spaces
  stays one word in the head (`BONUS {Mage & Brave Hero}`).
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
`ALL_FRIENDLY`, `ALL_ENEMY`, `ALL_OTHER_IN_RANGE`, `ALL_FRIENDLY_IN_RANGE`, `ALL_ENEMY_IN_RANGE` (every enemy in SELF's range, "Opponent's Heroes in Range"), `ALL_FRIENDLY_IN_BATTLE` (every hero of the card's player in the battle being fought, "Each of your Heroes in this Battle"; a combo, 2026-11-07), `ALL_HEROES`,
`EACH_HERO` (on a stage: those standing on it), `MOST_HP`, `MOST_PWR` (on a stage; nobody on a tie), `MOST_ENERGY`
(with `PICK` as the last argument of the action, one hero of the group picked by the owner of its heroes: `BUFF
MOST_ENERGY PWR 3000 PICK` = "the player with more Energy chooses one of their Heroes in this Battle"; a group
that spans players is picked by the card's player),
(the heroes of the player with the most Energy among the players in the battle, or with heroes on the stage; nobody
on a tie; Egghead "the Hero whose player has more Energy", 2026-11-05).
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
| `STATUS <t> <NAME> [turns|TURN]` | IMMUNE_KB, STUN, … | status with a timer (`TURN` = this turn)  On a `PASSIVE` line the status holds while the card is in play (`RulesEngine.has_status`): `PASSIVE: STATUS SELF IMMUNE_KB` ("X is immune to Knockback"), `PASSIVE: STATUS SELF IGNORE_TERRAIN` ("X ignores Terrain, except Ramp": Ice, Mud and Wind do nothing to its roll and Fire does not burn it; a Ramp still does) |
| `DAMAGE_MOD <t> <n> [TURN]` | | "takes ±n DMG from all sources"; passive or this turn. Applied to every hit on its own (battle hits, walls, traps, cards, a damage cost); a reduction never brings a hit under 1 (Marko 2026-11-08); on a battle hit only to the part that lands on the hero, not to cards paid from the hand. `DAMAGE … TRUE` skips it |
| `REMOVE_EVO <t>` | | takes the top evolution off |
| `WALL [n]` | | the player picks a free hex (not on a stage) for a 1-hex wall |
| `REVEAL_CORE` / `ACTIVATE_CORE` | | pick a core on the field: turn it face up / put it on SELF |
| `DEACTIVATE_CORE SELF [n]` | | pick n cores on SELF; they go to the inventory to be put back within SELF's range |
| `CHARGE <p> <n>` / `DISCHARGE <p> <n>` | | energy ±n (0 … max) |
| `DRAW <p> <n>` / `DISCARD <p> <n>` | | draw; the discarding player picks the card (a token is never discarded) |
| `TOKEN <p> <token card id> [n]` | | that player gets n (1) of that token card beside the hand (GDD 10, 2026-11-14), e.g. `PREROLL: TOKEN ME DQ1-010-1`. A token is a card with `"token": true`, an Action, whose id is its maker's with a number; everyone sees it; it is played like a card from the hand (colour, first tag, phase, cost) and then it is gone, not in the graveyard; unplayed, the end of the turn takes it. It is not a card in the hand: not counted, discarded, paid as damage, free-played or part of a combo. Never on an `END` or `PASSIVE` line (such a line is not read), and nothing is made in the End phase. Card text (Marko 2026-11-14): "Create a Spark Token." / "Create 2 Spark Tokens."; the parser writes the name (`TOKEN ME {Spark}`) and the catalog puts in the id of the token card with that name once every card is loaded (the maker's own token first); a name no token card has leaves the card not ready. A hand-written fx names the id. `TOKEN OPP` gives it to the opponent (no card text for it yet) |
| `COMPANION` | | on an Assist's `PLAY` line: the card puts its companion on a free hex next to the hero it was played for (the activated hero when it names none); the player picks the hex. With no free hex next to the hero it goes on the nearest free one, the player picking among the equally near (Marko 2026-11-22). A companion is a token, not a hero: no HP, no stage, no battle; it is there while its Assist is in play, one per player (a new one sends the old one and its Assist to the graveyard); balls push it and off the table it is gone with its Assist (GDD 10, 2026-11-21). Card text: "When you play this card, place Coco Jumbo next to your Hero." |
| `HIDE <reach> [energy]` | | on the same Assist, with `OPTIONAL` (`POSTROLL OPTIONAL: HIDE 1 1`): one hero of its player on the map within `reach` hexes of the companion, not locked in a tie, hides inside for that energy; with two near, the player picks. One hero at a time. A hidden hero is off the table (zone `shelter`): no target, in no battle, on no stage, its ability and equipment do nothing, no card is played for it; if it was the activated hero its player is down to Pass or an Assist for the turn. It comes out when it is activated (`select`, with `hex` to pick which of the free hexes nearest to the companion: next to it, or the nearest ring with one when there is no room; the first of them otherwise) and then rolls or stays. Card text: "A friendly Hero within 1 space may pay 1 Energy to hide inside." |
| `WANDER <n>` | | on the same Assist, `END`: the companion walks 1 to n hexes in a line, direction and length drawn by lot, until something is in the way; a direction with no free first step is skipped; never off the table; the hero inside goes along. Card text: "It moves up to 2 spaces in a random direction." |
| `TERRAIN <Ice|Mud|Ramp|Wind|Fire>` | | the stage SELF stands on (revealed, not claimed) gets that terrain in place of its own, for as long as a stage keeps a terrain; with no such stage under the hero the card is not played. Card text: "The Terrain of a Stage your Hero stands on becomes Fire." (2026-11-22) |
| `COST <p> <n> [{Trait}] [PHASE] [TURN]` | | cards of that player cost ±n (filter by trait or by the card's phase); passive, or this turn |
| `NO_CLAIM <p or hero group>` | | that player claims no stage this turn; on heroes (`NO_CLAIM ALL_ENEMY_IN_RANGE`, Conqueror's Haki): the heroes in range as the card is played get a "no_claim" status for the turn, and a stage claims for a player only if a hero of theirs on it is free (energy still goes in; the claim waits). `NO_CLAIM OPP` stays for the whole opponent |
| `ROLL_AGAIN` | | the activated hero rolls once more, right away (Roll phase, after the roll); the ball stopping again brings new offers |
| `REVERSE_ROLL` | | the activated hero goes back to where it stood as the Roll phase began; heroes it pushed, cores it picked up and stages it revealed stay ("reverse the roll", "return this hero to where it was before the roll") |
| `COST_DAMAGE <n>` | | additional cost: SELF takes n as the card is played (needs more than n HP). `COST_DAMAGE 0` under `INSTEAD BONUS` right after it takes the cost away for that hero ("{Flazzard} Bonus: Do not pay the additional cost."). On a Combo card each hero of the combo pays it |
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
| `SWAP FRIENDLY [ENGAGED]` | | SELF and a friendly hero trade hexes (`ENGAGED`: one that an enemy hero has in its range, "that is in an Opponent's Hero's Range"; with `RANGE` it must also be in SELF's range; Marko 2026-11-05) |
| `DUEL_TOP <STAT> <n> [PICK]` | | stage: the players show their top card (the cards stay on top); the higher cost gets +n for its heroes (on the stage under `REVEAL`, for the rest of the phase under `BATTLE`); `PICK`: the winner picks one of their heroes in the battle instead; a tie gives nothing |

Extra arguments: `DAMAGE … TRUE` ignores damage modifiers ("cannot be blocked");
`DEACTIVATE_CORE SELF <n> UPTO` lets the player pick how many (0 … n), and `PER COUNT` in a
later `BUFF` multiplies by that number. `MOVE` with a group target asks every hero in turn
(its own hex = stays). A stage's `REVEAL` bonus counts while the hero stays on that stage
and it is unclaimed (`GameState.stage_buffs`); once the hero leaves, it is gone.

Counters for `PER`: `TRAIT_EQUIPPED {Trait}` (equipment with the trait on the target, the card itself included),
`CORES` (cores on the target), `MISSING_HP <n>` (per n HP missing), `ENERGY` (the owner's
energy), `LOW_HP_FRIENDLY <n>` (the owner's heroes with ≤ n HP, the hero itself included, KO heroes not), `LOW_HP_OTHER_FRIENDLY <n>` (the same without the hero whose effect it is: "every other friendly Hero").

## Words that came with DQ1 (2026-11-22)

Tested in `tests/test_dq1_fx.gd` on small cards written as card text.

**A {Tag} may be several words** (`{Avan Style}`) anywhere in a line, and a tag joined by "&" on a card counts as
each of its parts (`CardDef.has_trait`: "Mage & Brave Hero" is a {Mage} card and a {Brave Hero} card).

**Conditions** (`IF <COND> [args…]`; the condition is the last thing in the head, every word after its name is
its argument):

| condition | holds when | card text |
|---|---|---|
| `OPP_COUNT <n>` | at least n opponent heroes are in SELF's battle | "If there are at least 2 Opponent's Heroes in this Battle, …" |
| `OPP_PWR <n>` | an opponent hero in SELF's battle has n Power or more. Asked while a power is being worked out it is false, so two such passives never chase each other | "… if an Opponent's Hero in this Battle has 8000 Power or more" |
| `GRAVE {Tag} <n>` | the player has at least n cards with the tag in the graveyard | (with REQUIRE) |
| `GRAVE_MORE {A} {B}` | more {A} than {B} cards in the player's graveyard; a tie is neither | "X gets +2 Knockback if you have more {A} than {B} cards in your graveyard, or +2 DMG if you have more {B} than {A}." (two lines) |
| `OPP_PLAYED <TURN|BATTLE> {Tag} [{Tag}…]` | an opponent played a card with one of the tags this turn, or in SELF's battle (`GameState.turn_plays`) | "… if your Opponent played a {Fire} or {Explosion} card in this Battle" |
| `PWR_TIED` | the player's side and an opposing side of SELF's battle have the same Power now (on an Action: after its stat box) | "If after playing this card you have the same Power as your Opponent, …" |
| `LOW_HP <n>` | SELF has n HP or less | |
| `ON_STAGE` | SELF stands on a revealed, unclaimed stage | (with REQUIRE) |
| `CLAIMED_LAST_TURN` | the player claimed a stage last turn | (with REQUIRE) |
| `WIN_ALLY` | waits for the battle like `WIN`: SELF's side won and another hero of that side was in it | "Whenever X wins a Battle with another friendly Hero in it, …" |
| `LOSE_BELOW <n>` | waits for the battle: SELF's side lost and SELF has less than n HP once the hits have landed (a KO counts) | "If you lose this Battle and your Hero falls below 4 HP, …" |

A "Battle Phase:" line with `OPP_PWR` or `OPP_PLAYED` on a card that stays in play (Hero, Evolution, Equipment,
Assist) is written as `PASSIVE`: the condition changes while the battle is fought, so it is asked all the time,
and it only holds in a battle.

**Counters** (`BUFF … PER <COUNTER>`): `OPP_IN_BATTLE` (opponent heroes in the hero's battle, "for each
Opponent's Hero in this Battle"), `HP` (the hero's HP now, "for each HP they have"), `MISSING_HP 1` ("for each HP
they are missing"), `GRAVE {Tag} [n]` (one for each n cards with the tag in the hero's player's graveyard, "for
each 3 {Strash Mastery} cards in your graveyard").

**Verbs**

| verb | effect |
|---|---|
| `REQUIRE <COND> [args]` | the card is played only while the condition holds; otherwise it stays in the hand and nothing is paid (`RulesEngine._requirement`). "Play this card only if you have at least 3 {Avan Style} cards in your graveyard." is `REQUIRE GRAVE {Avan Style} 3`; "… only while your Hero is on a Stage." `REQUIRE ON_STAGE`; "… only if you claimed a Stage last turn." `REQUIRE CLAIMED_LAST_TURN` |
| `RECYCLE <p> <n> <TOP|BOTTOM|SHUFFLE> {Tag}` | with a tag: the newest n cards with it, wherever they lie in the graveyard. "Put 3 of them on the bottom of your deck." after a REQUIRE GRAVE sentence takes that tag. With more such cards than asked for, the player says which, card by card (`RECYCLE_PICK`, Marko 2026-11-22); with exactly that many they all go |
| `OWN_COST` on a plain line | "This card costs 1 Energy less if your Opponent played a {Fire} card this turn." is `BATTLE IF OPP_PLAYED TURN {Fire}: OWN_COST -1` |

**INSTEAD after a bare phase line** replaces the card's stat box for the hero it holds for
(`FxRuntime.box_replaced`): "Battle Phase: / Yellow Bonus: Your Hero gets +1000 Power for each Opponent's Hero in
this Battle instead." gives a Yellow hero +1000 per opponent in place of the box, any other hero the box.

**Cards in play that watch cards being played** (`PLAYED`, a WHEN of its own). Each time a card is played, after
its own effects, every `PLAYED` line of the cards that were in play as it was played runs if its filter fits
(`FxRuntime.on_card_played`; a card never answers its own play, and a hero's own card still answers the Evolution
that takes its place). In such a line `SELF` is the hero whose card it is and `CARD_HERO` the hero the card was
played for. The filter is the condition `TAG`:

`PLAYED IF TAG <{Tag}|ANY> [ACTION|EQUIPMENT|EVOLUTION|ASSIST] [NTH n] [MAX n] [PHASE P] [FOR_SELF] [OPP] [IN_RANGE] [HP_BEFORE n]: …`

- without `OPP` it is about cards its own player plays; with it, cards an opponent plays;
- `NTH n`: the n-th such card that player plays this turn (in phase P when the line names one);
- `MAX n`: the line runs at most n times a turn ("This happens up to 3 times a turn.");
- `PHASE P`: only in that phase (the sentence opens with "Battle Phase:");
- `FOR_SELF`: the card is played for the hero whose card the line is on; `IN_RANGE`: for a hero in its range;
- `HP_BEFORE n`: the card's hero had n HP or less before the card.

| card text | fx |
|---|---|
| "Whenever you play an {Avan Style} card, draw 1 card, then put 1 card from your hand to the bottom of your deck." | `PLAYED IF TAG {Avan Style}: DRAW ME 1; BOTTOM ME 1` |
| "Battle Phase: Whenever you play a {Fire} card, X gets +1000 Power until the end of the turn. This happens up to 3 times a turn." | `PLAYED IF TAG {Fire} PHASE BATTLE MAX 3: BUFF SELF PWR 1000 TURN` |
| "Whenever you play your third {Mage} card in a turn, draw a card." | `PLAYED IF TAG {Mage} NTH 3: DRAW ME 1` |
| "Battle Phase: The first {Mage} card you play in a turn gets +2000 Power." | `PLAYED IF TAG {Mage} NTH 1 PHASE BATTLE: BUFF CARD_HERO PWR 2000` |
| "{Wind} cards played for the equipped Hero get +1000 Power." | `PLAYED IF TAG {Wind} FOR_SELF: BUFF CARD_HERO PWR 1000` |
| "Battle Phase: If an Opponent's Hero is in Range, your Opponent's cards give 2000 less Power." | `PLAYED IF TAG ANY OPP IN_RANGE PHASE BATTLE: WEAKEN_CARD 2000` |

A bonus a `PLAYED` line puts on `CARD_HERO` is kept with the card it went to (the battle's list of played cards), so
whatever takes that card back takes the bonus too.

| verb | effect |
|---|---|
| `NEXT_CARD {Tag} <STAT> <n>` | the next card with the tag the player plays this turn gives its hero that much more ("The next {Lightning} card you play this turn gets an additional +3000 Power.") |
| `WEAKEN_CARD <n>` | in a `PLAYED` line: the card just played gives its hero up to n less Power, never less than nothing |
| `BOTTOM <p> <n>` | that player puts a card from the hand on the bottom of the deck (their pick) |
| `HEAL_MOD <t> <n> [BY]` | passive: those heroes heal n more ("Whenever a Hero on this Stage is healed, they heal an additional 1 HP." is `HEAL_MOD EACH_HERO 1`); with `BY` it is about the healer: heals from cards played for the hero whose passive it is ("Cards played for X heal an additional 1 HP." is `HEAL_MOD SELF 1 BY`) |
| `HEAL <t> FULL` | to full HP ("When you play this Evolution, X heals to full HP." is `PLAY: HEAL SELF FULL`) |
| `COST <p> <n> …` filters | the words after the amount say which cards: {Tag}s (one of them is enough), a card type (`EQUIPMENT`, `EVOLUTION`, `ACTION`, `ASSIST`, `COMBO`: a combo's extra energy, which like a card never goes under 1 by a discount), `COSTS <n>` (printed cost n), `FOR_SELF` (cards played for the hero whose card it is). "Your Equipment cards cost 1 Energy less.", "Your combos cost 2 Energy less.", "{Mage} cards played for X cost 1 Energy less.", "Your {Fire} and {Explosion} cards that cost 3 cost 1 Energy less." On a card that stays in play a cost line is `PASSIVE` whatever phase the sentence opens with |

"If X has 5 or less HP, his Evolution cards cost 2 Energy less and heal him 3 HP." is two lines:
`PASSIVE IF LOW_HP 5: COST ME -2 EVOLUTION FOR_SELF` and `PLAYED IF TAG ANY EVOLUTION FOR_SELF HP_BEFORE 5: HEAL SELF 3`.

**Tags gained in the match.** `GAIN_TAG <t> {Tag} [TURN]`: on a `PASSIVE` line those heroes carry the tag while the
card is in play ("The equipped Hero gains {Mage}.", "Your Heroes gain {Brave Hero}."); with `TURN` for this turn
("… until the end of the turn"). A gained tag counts like one the hero carries (Marko 2026-11-22): for playing cards
(`FirstTag.play_verdict` takes `RulesEngine.gained_tags`) and for effects (`hero_has_tag`, `BONUS {Tag}`).

**Narrowing the heroes of an action.** `WITH {Tag}` after the arguments keeps the heroes called that or carrying
the tag (`hero_is`); `HP <n>` those with n HP or less. A group narrowed to nobody as an effect's first step means
the card is not played. A hero a card that is not a hero's own speaks of by name (its first tag: "Hyunckel gets +2
Knockback" on an Assist tagged Hyunckel) is written `ALL_FRIENDLY … WITH {Hyunckel}`. In an Assist's ability
"your Hero" is the player's hero acting now: the activated one, or its hero in the battle being fought; with two of its heroes in that battle the player picks (`PICK_SELF`, Marko 2026-11-22).

| verb | effect, and the card text the parser reads |
|---|---|
| `BUFF <group> … PICK WITH {Tag}` | "A friendly Hero with {Brave Hero} in this Battle gets +5000 Power." (`ALL_FRIENDLY_IN_BATTLE`, the player picks among those with the tag); without PICK all of them: "Your {Dark Army} Heroes in this Battle get +3000 Power." |
| `PAY <n>` | the player pays n Energy; an ability that starts with it is not offered without the Energy. "You may pay 2 Energy. If you do, …" |
| `PAY_HP <t> <n>` then `… PAID …` | each of those heroes with more than n HP is asked, one by one, whether it pays n (`PAY_HP_ASK`, an option for its player; Marko 2026-11-22); `PAID` is the target for the ones that did. "Each of your {Dark Army} Heroes may pay 1 HP to get +2000 Power." (the heroes in the battle) |
| `KO <t> [HP <n>]` | the hero goes down (a hit for all its HP, so what saves from a KO still can). "KO an Opponent's Hero in Range with 1 HP." |
| `STATUS <t> STONE TURN` | no Power and no damage this turn. "Another friendly Hero in Range has 0 Power and cannot take DMG this turn." |
| `STATUS <t> DOOMED TURN` | the hero is KO'd as the End phase starts. "Your Hero is KO'd during the End Phase." |
| `STATUS <t> STUN <n> [LINKED]` | cannot be activated; n counts this turn, so "next turn" is 2 and "for 2 turns" 3. `LINKED`: it ends when the hero whose card it is is KO'd or ringed out ("… or until X is KO'd or ringed out") |
| `STATUS SELF NO_ROLL TURN` | the hero does not roll this turn ("They cannot roll this turn.") |
| `STATUS SELF FLEE TURN` | "Your Hero loses this Battle without taking DMG. After the Battle, they are ringed out.": its side cannot win the battle, no hit goes to it, and it is ringed out (a full ring-out) when the battle is done. With another hero of its side in the battle (for now, Marko 2026-11-22): the ones that stay are locked as after a tie, no winner and no hit that turn |
| passive statuses | `BRITTLE` ("If X rolls, this Evolution goes to the graveyard."), `NO_CARDS` ("No cards can be played for X."), `KO_IF_REMOVED` ("If this Evolution is removed, X is KO'd.": a card took it off, not a roll) |
| `SACRIFICE` | the Assist whose line it is goes to the graveyard. "You may put this Assist into the graveyard. If you do, …" |
| `SAVE_KO <t>` | passive on an Assist: the first of those heroes that would be KO'd stays at 1 HP and the Assist goes to the graveyard. "The first time one of your Heroes would be KO'd, they stay at 1 HP instead. Then put this Assist into the graveyard." |
| `SHIELD <t> <n>` | passive on an Assist: before a battle hit of n or less is dealt to one of those heroes, its player is asked whether the Assist goes to the graveyard instead (`PREVENT <hero> <n>` then keeps that hit off). "If X would take 5 or less DMG, you may put this Assist into the graveyard instead." |
| `HEAL_LATER <t> <n>` | heals as the End phase starts. "… your Hero heals 1 HP at the end of the turn." |
| `RING_OUT_DRAW <n>` | if an opponent's hero is ringed out in this Battle phase the player draws n, once. Read after a SACRIFICE sentence |
| `TELEPORT <SELF|FRIENDLY> <n|STAGE>` | to a free hex up to n away, or (STAGE) a free hex of a stage in SELF's range; walls and balls in between do not matter. "Your Hero moves to an empty space up to 10 spaces away.", "Move another friendly Hero in Range to an empty space on a Stage in Range." |
| `APPROACH <n>` | SELF steps up to n hexes towards the nearest opponent hero of its battle, until next to it. "Your Hero moves 2 spaces towards the nearest Opponent's Hero." |
| `RETURN_LATER SELF` | as the End phase starts the hero goes back to where the Battle phase found it (`GameState.battle_snapshot`), also from its start zone; not when KO |
| `KNOCKBACK <t> <n> RANDOM` | each hero its own direction, drawn by lot. "When this Stage is revealed, Knockback each Hero on it 5 spaces in a random direction." |
| `BUFF MOST_ASSISTS … PICK` | like `MOST_ENERGY`, by Assists in play. "… the player with more Assists chooses one of their Heroes in this Battle. That Hero gets +3000 Power." |
| `DUEL_HAND <STAT> <n> PICK` | each player with a hero in the battle shows a card from the hand (their pick, it stays in the hand); the higher cost wins and picks one of their heroes for +n; a tie nobody, an empty hand shows 0 |
| `DRAIN_STAGE <n>` | n of the opponents' Energy leaves the stage SELF stands on (from whoever holds the most). "Remove 5 of your Opponent's Energy from that Stage." |
| `CURSE_STAGE` | for the rest of the match no Battle Phase cards for the other sides' heroes standing on the stage SELF stands on (`StageState.cursed_by`) |
| `REVEAL_STAGE` | a face-down stage of an opponent in SELF's range turns face up (its reveal effect runs for SELF) |
| `NEGATE_LAST [{Tag}] [RANGE <n>]` | the last Battle Phase card an opponent played in this battle is undone when it has the tag, or was played for a hero with n Range or more: it loses the stats it gave (`gave_phase` / `gave_turn` kept with the card) and its effects that still wait; what already happened stays. Otherwise the card is not played |
| `REMOVE_ASSIST OPP`, `GAIN_ASSIST` | one of the opponent's Assists goes to their graveyard (the card's player picks); the same turn GAIN_ASSIST brings it into play on that player's side |
| `EQUIP_OTHER [{Tag}]` | on an Equipment: it goes on another hero of the player in the range of the hero it is played for, one with the tag (the move's `wearer` names it when several fit), and it is played in the phase its sentence opens with |

`COST_DAMAGE` on an Evolution is paid as it goes on ("As an additional cost, X takes 3 DMG.").

## Choices

When an effect needs a decision, the engine pushes `{"type": "choose", "player", "kind":
"hero"|"hex"|"core"|"card"|"option", "options": [...], "prompt", "resume": {...}}` onto
`state.pending` and waits for `choose {"value": ...}` from that player (an index for `option`).
The effect continues from where it stopped; the state can be saved in between.

## What the parser reads today

Phase prefixes, `Once Per Turn`, `may`, `If <hero> is activated`, `While <hero> / the equipped Hero is
activated`, `If the equipped Hero is activated, …`, `If you win this Battle`, `If the Opponent's Hero in this
Battle has a {Sword} equipped, …` (`IF OPP_EQUIPPED`), `When this Stage is revealed`, `Terrain:` lines (data,
not an effect). Range (rule B, 2026-11-05) next to its target: `an Opponent's Hero in Range`, `a friendly Hero in
Range`, `a Core in Range`, `a Wall … in Range` set `RANGE` and read on; `If an Opponent's Hero is in Range, …`
too; `Opponent's Heroes in Range can't claim a Stage this turn` is `NO_CLAIM ALL_ENEMY_IN_RANGE`; the old
`[Range]` head still reads. The hero's first name alone is SELF (`Giorno may …`). Stat bonuses with `for every /
each …` and `until the end of the turn`; `takes N DMG`, `takes ±N DMG from all sources`, `takes 1 less DMG from
each source`; heals; `move up to N spaces`; `Knockback an Opponent's Hero N spaces, away from your Hero` /
`Knock … back N spaces`; `Choose an Opponent's Hero in Range.` names the target of the next sentence (`Knock them
back 3 spaces.`); `move N spaces towards you / your Hero`; `Swap your Hero with another friendly Hero that is in
an Opponent's Hero's Range` (`SWAP FRIENDLY ENGAGED`); `immune to Knockback`; `Place a Wall (on an empty space)`;
`When you play this card, place <name> next to your Hero` (`PLAY: COMPANION`), `A friendly Hero within N space(s) may (pay N Energy to) hide inside` (`HIDE`), `It moves (up to) N spaces in a random direction` (`WANDER`);
`Reveal / activate / deactivate a Core`; `Move a Core up to N spaces` and after it `If an Opponent's Hero activates
that Core this turn, they take N DMG` (`TRAP_CORE`); `If he does, …` / `If you do, …` adds to the sentence before;
`gain / lose N Energy` (`they lose …` is the opponent; charge / discharge still read); `for each Energy their
player has`; cost changes (`{Haki} cards cost 1 Energy less`, `This card costs 1 Energy less`, `your Opponent's cards cost 2
Energy more`, `… Battle Phase cards cost 2 Energy more this turn`); stat bonuses with `gets` (the text standard: gets
for stats, gain / lose for Energy, for each, Knockback; Marko 2026-11-05 evening); `play a {Sword} Equipment with a
cost of 3 or less without paying its cost` (`FREE_PLAY`); `roll … again`;
`discard a card`; `remove an Evolution`; `cannot take a Stage`; `the Opponent's Hero in this Battle takes all
of the damage` (`FULL_HIT`; a sentence `Your Opponent can't discard cards to reduce it` after it is skipped); `As an additional cost, take
N DMG` (or `…, your Hero takes N DMG`: `COST_DAMAGE`); `Your Opponent chooses:` with two dashed lines. Clauses joined by "and" are read one by
one. Colour bonus lines of colorless cards (`Red Bonus: …`, `Cyan / Purple Bonus: …`): `This
card costs N less to play` (`OWN_COST`), `+N STAT` (a buff on the card's hero), `It also …` /
`You also …` and `… gets / gains / heals / takes an additional …` (an extra effect with the WHEN
and the condition of the sentence before), `It … N … instead` (the
sentence before with its number swapped, `INSTEAD`). Everything else lands in `unparsed`;
`tests/test_fx_parser.gd` lists the exact phrases.
