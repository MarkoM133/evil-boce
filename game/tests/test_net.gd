extends GutTest
## Host and client in one process over 127.0.0.1: version checks, lobby, a few moves,
## redaction, pause, reconnect. Needs real frames, so it waits with the tree.

const PORT: int = 7799

var catalog: CardCatalog
var host: NetHost
var client: NetClient
var client_state: GameState
var refusals: Array = []
var rejected: String = ""
var welcomed_slot: int = -1


func before_all() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string("res://tests/fixtures/cards.json"))


func after_each() -> void:
	if client != null:
		client.queue_free()
		client = null
	if host != null:
		host.queue_free()
		host = null
	await wait_frames(2)


func _deck(a: bool) -> Dictionary:
	var cores: Array = ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]
	if a:
		return {"name": "A", "heroes": ["TA-001", "TA-002", "TA-003"], "cards": {"TX-010": 40}, "stages": ["TS-001", "TS-002", "TS-003"], "cores": cores}
	return {"name": "B", "heroes": ["TB-001", "TB-002", "TB-003"], "cards": {"TX-011": 40}, "stages": ["TS-004", "TS-005", "TS-006"], "cores": cores}


func _start_host() -> void:
	host = NetHost.new(RulesEngine.new(catalog), "Host", "1.0", 1)
	host.settings.manual_setup = false
	add_child_autofree(host)
	assert_eq(host.listen(PORT), "")


func _start_client(name: String, game_version: String = "1.0", cards_version: int = 1) -> void:
	client = NetClient.new(name, game_version, cards_version)
	add_child_autofree(client)
	client.state_received.connect(func(s: GameState) -> void: client_state = s)
	client.move_refused.connect(func(m: Dictionary, why: String) -> void: refusals.append(why))
	client.rejected.connect(func(why: String) -> void: rejected = why)
	client.welcomed.connect(func(s: int) -> void: welcomed_slot = s)
	assert_eq(client.connect_to("127.0.0.1", PORT), "")


## The first ENet connection in a process can take a second or two: wait for it, then a bit more.
func _settle(seconds: float = 0.6) -> void:
	var waited: float = 0.0
	while client != null and client.link.peer != null and not client.link.connected and waited < 4.0:
		await wait_seconds(0.1)
		waited += 0.1
	await wait_seconds(seconds)


func test_version_mismatch_is_rejected() -> void:
	_start_host()
	_start_client("Old", "0.9", 1)
	await _settle()
	assert_true(rejected.begins_with("update the game"), "first: " + rejected)
	client.queue_free()
	client = null
	rejected = ""
	_start_client("Stale", "1.0", 2)
	await _settle()
	assert_true(rejected.begins_with("sync the shared folder"), "second: " + rejected)


func test_lobby_match_moves_and_redaction() -> void:
	_start_host()
	host.set_my_deck(_deck(true))
	_start_client("Guest")
	await _settle()
	assert_eq(welcomed_slot, 1)
	assert_eq(host.seats.size(), 2)
	assert_eq(host.can_start(), "Guest has no deck")
	client.send_deck(_deck(false))
	client.send_ready(true)
	await _settle(0.4)
	assert_eq(host.can_start(), "")
	assert_eq(host.start(5), "")
	await _settle()
	assert_true(client.started)
	assert_not_null(client_state)
	assert_eq(client_state.phase, GameState.PHASE_MULLIGAN)
	# The client sees its own hand but not the host's, and no deck order.
	var mine: PlayerState = client_state.player(1)
	var theirs: PlayerState = client_state.player(0)
	assert_eq(mine.hand.size(), 5)
	assert_false(mine.hand.has(NetProtocol.PLACEHOLDER_CARD))
	assert_eq(theirs.hand.size(), 5)
	assert_true(theirs.hand[0] == NetProtocol.PLACEHOLDER_CARD)
	assert_true(mine.deck[0] == NetProtocol.PLACEHOLDER_CARD)
	assert_eq(mine.deck.size(), host.state().player(1).deck.size())
	for c: CoreState in client_state.cores:
		assert_eq(c.card_id, NetProtocol.PLACEHOLDER_CARD, "face-down cores are unknown")
	# A move for the wrong seat is refused; a right one is applied and comes back as state.
	client.send_move(Move.make(Move.MULLIGAN, 0, {"keep": true}))
	client.send_move(Move.make(Move.MULLIGAN, 1, {"keep": true}))
	await _settle()
	assert_eq(refusals, ["that is not your seat"])
	assert_true(host.state().player(1).mulligan_done)
	assert_true(client_state.player(1).mulligan_done)
	assert_eq(host.apply(Move.make(Move.MULLIGAN, 0, {"keep": true})), "")
	await _settle()
	assert_eq(client_state.phase, GameState.PHASE_START)
	# Pause from the client; the host may not be able to move; the client resumes.
	client.send_pause(true)
	await _settle(0.4)
	assert_true(host.paused)
	assert_eq(host.apply(Move.make(Move.SELECT, 0, {"hero": "p0:TA-001"})), "paused")
	client.send_pause(false)
	await _settle(0.4)
	assert_false(host.paused)
	assert_eq(host.apply(Move.make(Move.SELECT, 0, {"hero": "p0:TA-001"})), "")
	await _settle(0.4)
	assert_eq(str(client_state.active.get(0, "")), "p0:TA-001")


func test_reconnect_keeps_the_seat_and_pauses_meanwhile() -> void:
	_start_host()
	host.set_my_deck(_deck(true))
	_start_client("Guest")
	await _settle()
	client.send_deck(_deck(false))
	client.send_ready(true)
	await _settle(0.4)
	assert_eq(host.start(9), "")
	await _settle()
	client.link.close()
	client.queue_free()
	client = null
	await _settle()
	assert_true(host.paused, "a drop pauses the match")
	assert_false(JsonUtil.as_bool(host.seat(1).get("connected", true)))
	client_state = null
	_start_client("Guest")
	await _settle()
	assert_eq(welcomed_slot, 1, "same name, same seat")
	assert_true(client.started)
	assert_not_null(client_state)
	assert_true(JsonUtil.as_bool(host.seat(1).get("connected", false)))
	assert_true(client.paused)
	# The host resumes.
	assert_eq(host.set_paused(false, 0), "")
	await _settle(0.4)
	assert_false(client.paused)


func test_big_packets_are_gzipped_and_come_back_the_same() -> void:
	var list: Array = []
	for i: int in 2000:
		list.append({"id": "p0:OP1-%03d" % (i % 999), "n": i})
	var big: Dictionary = {"t": "x", "list": list}
	var bytes: PackedByteArray = NetProtocol.encode(big)
	assert_eq(bytes[0], NetProtocol.COMPRESSED)
	assert_lt(bytes.size(), JSON.stringify(big).length() / 4)
	assert_eq(JSON.stringify(NetProtocol.decode(bytes)), JSON.stringify(JsonUtil.as_dict(JSON.parse_string(JSON.stringify(big)))))
	var small: PackedByteArray = NetProtocol.encode({"t": "ping"})
	assert_eq(small.get_string_from_utf8(), "{\"t\":\"ping\"}")


func test_a_guest_cannot_take_the_hosts_name() -> void:
	_start_host()
	_start_client("Host")
	await _settle()
	assert_true(rejected.begins_with("the host is called Host too"), rejected)


func test_settings_unready_the_guest_and_the_end_brings_the_record_and_the_lobby() -> void:
	_start_host()
	host.set_my_deck(_deck(true))
	_start_client("Guest")
	var over: Array = []
	var back: Array = []
	client.match_over.connect(func(_s: Dictionary, r: MatchRecord) -> void: over.append(r))
	client.back_in_lobby.connect(func() -> void: back.append(true))
	await _settle()
	client.send_deck(_deck(false))
	client.send_ready(true)
	await _settle(0.4)
	assert_eq(host.can_start(), "")
	var s: MatchSettings = MatchSettings.standard()
	s.map_size = 17
	s.manual_setup = false
	host.set_settings(s)
	await _settle(0.4)
	assert_eq(host.can_start(), "Guest is not ready", "new settings: ready again")
	assert_eq(JsonUtil.as_int(client.settings.get("map_size", 0)), 17)
	client.send_ready(true)
	await _settle(0.4)
	assert_eq(host.start(3), "")
	await _settle()
	client.send_move(Move.make(Move.SURRENDER, 1))
	await _settle()
	assert_true(host.state().is_over())
	assert_eq(over.size(), 1)
	var rec: MatchRecord = over[0]
	assert_not_null(rec, "the guest gets the whole record")
	assert_eq(rec.frame_count(), host.recorder.record.frame_count())
	# Nothing is hidden in it any more: the host's hand is real.
	assert_false(rec.state_at(0).player(0).hand.has(NetProtocol.PLACEHOLDER_CARD))
	host.back_to_lobby()
	await _settle(0.4)
	assert_eq(back.size(), 1)
	assert_false(client.started)
	assert_false(host.started)
	assert_eq(host.can_start(), "Guest is not ready")
	assert_eq(client.slot, 1)


func test_a_bot_seat_can_be_freed_for_a_player() -> void:
	_start_host()
	host.set_my_deck(_deck(true))
	assert_eq(host.add_bot("easy", _deck(false)), "")
	assert_eq(host.add_bot("easy", _deck(false)), "the table is full")
	_start_client("Guest")
	await _settle()
	assert_true(rejected.begins_with("the table is full"), rejected)
	client.queue_free()
	client = null
	rejected = ""
	host.remove_bots()
	assert_false(host.has_bot())
	_start_client("Guest")
	await _settle()
	assert_eq(rejected, "")
	assert_eq(welcomed_slot, 1)
