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
- A packet over 8 KB goes out gzipped behind a `0x01` byte (plain JSON always starts with `{`);
  in practice that is the states mid-match and the record at the end.

## Messages (`NetProtocol`)

| From | `t` | Fields | When |
|---|---|---|---|
| guest | `hello` | name, game_version, cards_version, net_version | right after the link is up; also on reconnect |
| host | `welcome` / `reject` | slot, players, settings / reason | answer to hello |
| guest | `deck`, `ready` | engine deck dict / bool | lobby |
| host | `lobby` | players [{slot, name, ready, bot, connected, has_deck, shown}], settings, again | any lobby change; `again` = the host took everyone back after a match; `shown` = the seat's picks as the lobby shows them to the others (deck name, heroes, stages, cores; "" = random) |
| host | `start` | settings, players (record header), seed, cards_version | the host pressed Start, or a reconnect into a running match |
| guest | `move` | Move dict | the player did something |
| host | `state` | redacted GameState dict | after every accepted move or roll, to each guest separately |
| host | `refused` | move, reason | the engine (or the seat check) said no |
| host | `balls` | p: {hero id: [x, y, z]} | ~20 Hz while the host's physics runs (unreliable) |
| host | `roll` | RollOutcome dict | the roll ended; the paths are for drawing |
| guest | `pause` / `resume` | – | anyone may pause; the pauser or the host resumes |
| host | `paused` / `resumed` | by, name | |
| host | `player` | slot, name, connected | a guest dropped or came back |
| host | `over` | summary, record | the match ended; `record` is the full MatchRecord (nothing is hidden any more) |

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

## Lobby

- The host picks the map, the range change and how stages and cores are placed (the same
  choices as the local Play setup). Changing them un-readies the guests.
- Each player picks a saved deck or a random one; a saved deck that breaks the deck rules is
  not sent and Ready stays off.
- "Add a bot" fills the other seat (Easy / Hard); "Remove the bot" frees it for a player.
- A guest may not use the host's name (seats are found by name on reconnect).

## In the match scene

- **Host role**: `_apply` → `NetHost.apply` (the recorder behind it records the match as
  usual, so the host has the replay, the save and the stats); physics as in a local match,
  plus `send_balls` every 50 ms; `apply_roll` broadcasts the outcome and the states.
- **Client role**: `_apply` → `send_move`; `state_received` → redraw; `balls` move the frozen
  bodies; no recorder, no bots, no save (the host keeps them).
- Hot seat is unchanged; the network is a seat type, as GDD 2 wants.
- Only local matches write `saves/current.json` (Continue); an online one needs everyone.

## End of a match

- The host saves the replay and writes the stats to the shared folder (once per match).
- The guest gets the full record in `over` and saves it to its own Replays; it can watch it
  from the end screen. Watching closes the online session.
- The host's end screen says "Back to the lobby": seats and decks stay, guests press Ready
  again, guests who left during the match lose their seat.

## Not done yet

- Watching a replay together (the host steps through frames, the guests follow).
- Spectator seats, timer per phase, 2v2 seats (step 4), a dedicated server build.
- A real test over Tailscale between two computers.
