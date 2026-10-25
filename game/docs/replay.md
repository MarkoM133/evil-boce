# Match record: replay, save, continue from here

One format for three things (GDD 2): a **replay** (step through the phases, roll paths come from
the record, the physics never runs again), a **save** (resume from the last phase) and
**"continue from here"** (start a new match from any phase of a replay). The network host (step
3) sends the same frames, so a shared replay view and a reconnect use this too.

## Shape (`MatchRecord`, `format: 1`)

```json
{
  "format": 1, "game_version": "0.1.0", "cards_version": 7, "created": "2026-10-25T13:40:00Z",
  "settings": { MatchSettings dict },
  "players": [{"slot": 0, "name": "Marko", "team": 0, "bot": false, "deck_name": "...", "heroes": [...], "stages": [...]}],
  "decks": [ the engine deck dicts the match started with ],
  "seed": 123,
  "cards": { "OP1-001": { cards.json record }, ... },
  "frames": [
    {"index": 0, "turn": 0, "phase": "mulligan", "state": { GameState dict }, "moves": [ Move dicts ], "rolls": [ RollOutcome dicts ]},
    ...
  ],
  "finished": true, "winner": 0, "result": "stages"
}
```

- **A frame per phase the engine waits in.** `state` is the state at the *start* of that phase (the
  first moment the engine waits for input there, after its own triggers ran); `moves` and `rolls`
  are what happened during it, in order. Phases nobody acts in (draw, end) fold into the next
  frame; their events are in the state's log. Every frame can be resumed as it is, without
  re-running any trigger.
- **Cards travel with the record** (`cards`: every card the decks, stages and cores use, as
  cards.json records, hand-written `fx` included). `MatchRecord.catalog()` rebuilds a
  `CardCatalog` from them, so an old replay plays with the cards as they were.
- **Roll paths**: each `RollOutcome` keeps the sampled path of every ball; the replay view
  draws those instead of throwing.
- Moves refused by the engine are not recorded.

## Writing it (`MatchRecorder`)

`MatchRecorder.start(engine, settings, decks, seed, players)` runs `RulesEngine.start_match`
and opens frame 0. `apply(move)` / `apply_roll(outcome)` go through the engine and, when
accepted, into the current frame; a phase or turn change opens the next frame with a snapshot.
When the match ends, `record.finished / winner / result` are set.

`MatchRecorder.resume(engine, record, index)` continues from frame `index` (default: the last):
the record is branched there (`MatchRecord.branch_at`), the moves of that frame are dropped
(the player makes them again), and recording goes on from that state. The original record is
untouched.

## Files (`ReplayStore`)

| What | Where | Notes |
|---|---|---|
| Replays | `user://replays/<created>_<players>.json` | local, one per match; `list_replays()` reads headers only |
| Match in progress | `user://saves/current.json` | written after every move; cleared when the match ends |
| Stats | `<shared>/stats/<created>_<players>.json` | `MatchRecord.summary()`: players, heroes, decks, winner, turns, battles, KOs, ring-outs, claims, cards played |

`user://` is `%APPDATA%\EvilBoce\` (project setting `custom_user_dir_name`). Replays stay on the
player's machine; only the summary goes into the shared folder (GDD 2).

## What is left for the UI (step 2, part 5 and step 3)

- Replays menu: list, open, step by frame, play/pause/speed, delete, "continue from here"
  (`MatchRecorder.resume` with a frame index, then the match scene as usual).
- Main menu "Continue" from `ReplayStore.load_current()`.
- Replay view: draw `frames[i].state` like the match scene does, and animate `rolls` paths.
- Host-shared viewing: the host streams frames; same data, no new format.
