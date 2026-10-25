# Online play (step 3)

Host-authoritative over Tailscale (GDD 2). One player hosts; the host's game runs the rules
engine, the physics and the bots and is the only one that changes the state. Guests send moves
and render the state they are sent. Moving to a dedicated server later means running `NetHost`
without a scene; nothing else changes.

## Transport

- `NetLink`: one ENet endpoint (`ENetMultiplayerPeer` used directly, no SceneTree RPCs), polled
  every frame. Messages are JSON dictionaries with a `t` field. Reliable channel 0 for
  everything except ball positions, which go unreliable on channel 1 (`send_fast`).
- Host listens on port **7777** on all interfaces; guests connect to the host's Tailscale
  address (`100.x.y.z`). The lobby shows the host's `100.*` addresses.
- Every 3 s the host sends `ping`; ENet notices a dead link on its own and `peer_left` fires.

## Messages (`NetProtocol`)

| From | `t` | Fields | When |
|---|---|---|---|
| guest | `hello` | name, game_version, cards_version, net_version | right after the link is up; also on reconnect |
| host | `welcome` / `reject` | slot, players, settings / reason | answer to hello |
| guest | `deck`, `ready` | engine deck dict / bool | lobby |
| host | `lobby` | players [{slot, name, ready, bot, connected, has_deck}], settings | any lobby change |
| host | `start` | settings, players (record header), seed, cards_version | the host pressed Start, or a reconnect into a running match |
| guest | `move` | Move dict | the player did something |
| host | `state` | redacted GameState dict | after every accepted move or roll, to each guest separately |
| host | `refused` | move, reason | the engine (or the seat check) said no |
| host | `balls` | p: {hero id: [x, y, z]} | ~20 Hz while the host's physics runs (unreliable) |
| host | `roll` | RollOutcome dict | the roll ended; the paths are for drawing |
| guest | `pause` / `resume` | – | anyone may pause; the pauser or the host resumes |
| host | `paused` / `resumed` | by, name | |
| host | `player` | slot, name, connected | a guest dropped or came back |
| host | `over` | summary | the match ended |

### What a guest may see (`NetProtocol.redact`)

The state a guest gets is the true state minus what GDD 11 keeps hidden: the opponent's hand
(a count of `?`), every deck's order (counts only), the others' aims, face-down cores' cards,
and the card options of a decision that is not theirs. Everything a guest's HUD shows comes
from this state, so there is nothing to leak.

### Versions

`hello` carries the game version and the `cards.json` version. A different game version is
rejected with "update the game"; a different cards version with "sync the shared folder and
join again" (the host never sends cards or images; Syncthing is required, GDD 2).

## Seats, reconnect, pause

- Seats are numbered in join order; the host is slot 0; bots are seats with `peer = -1`.
- A guest who drops **in a match** keeps the seat (`connected = false`); the host pauses the
  match. A `hello` with the same name takes the seat back and gets `start` + the current
  `state`. In the lobby a dropped guest's seat is removed.
- Pause: anyone; resume: the one who paused, or the host. While paused the host refuses moves
  with "paused".

## In the match scene

- **Host role**: `_apply` → `NetHost.apply` (the recorder behind it records the match as
  usual, so the host has the replay, the save and the stats); physics as in a local match,
  plus `send_balls` every 50 ms; `apply_roll` broadcasts the outcome and the states.
- **Client role**: `_apply` → `send_move`; `state_received` → redraw; `balls` move the frozen
  bodies; no recorder, no bots, no save (the host keeps them).
- Hot seat is unchanged; the network is a seat type, as GDD 2 wants.

## Not done yet (step 3 continues)

- Shared replay viewing: the host streams `MatchRecord` frames (`frame {index, state, rolls}`)
  and the guests watch; same data as `docs/replay.md`.
- Guests keeping their own replay: they can store the states they receive as frames.
- Timer per phase, 2v2 seats (step 4), a dedicated server build.
