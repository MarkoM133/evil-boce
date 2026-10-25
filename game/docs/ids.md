# Ids in a match

Stable string ids for everything the rules engine, the sim, replays and the network refer to.
The engine assigns them; scenes and the sim only carry them around.

| Thing | Id | Example | Notes |
|---|---|---|---|
| Player slot | `p<index>` | `p0`, `p1` | Index into the match's slot list; the team is a property of the slot (1v1: team = index). |
| Hero on the table | `<slot>:<card id>` | `p0:OP1-001` | A deck holds 3 different heroes, so the card id is unique per slot. |
| Core | `core:<n>` | `core:3` | Numbered when the match is set up. |
| Stage | `stage:<n>` | `stage:1` | Numbered when the match is set up. |
| Wall | `wall:<n>` | `wall:2` | Numbered as they are placed. |
| Card instance | `<slot>:<card id>#<copy>` | `p1:OP1-014#2` | Only where a copy matters (hand, graveyard, equipment on a hero). |

- `RollResult.ball_id` and `RollOutcome.thrower` hold hero ids. The sandbox, which has no
  slots, uses `<card id>#<n>` instead.
- Hexes are `[q, r]` in JSON, see `hex.md`.
