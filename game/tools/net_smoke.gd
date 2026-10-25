extends SceneTree
## Dev smoke test: host + client in one process, then the match scene as the client, then as the
## host, each pushed through a few frames. Run: godot --headless --path game -s tools/net_smoke.gd

const PORT: int = 7798

var db: CardDb
var host: NetHost
var client: NetClient
var fails: int = 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("ok   " if ok else "FAIL ") + what)


func _hud(scene: Node) -> MatchHud:
	var h: MatchHud = scene.get("hud")
	return h


func _state(scene: Node) -> GameState:
	var s: GameState = scene.get("state")
	return s


func _initialize() -> void:
	call_deferred("_go")


func _go() -> void:
	db = CardDb.load_from(GameSettings.data_path())
	_check(db.is_ok(), "cards loaded: " + db.error)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	host = NetHost.new(RulesEngine.new(db.catalog), "Host", "0.1.0", db.version)
	host.settings.manual_setup = false
	root.add_child(host)
	_check(host.listen(PORT) == "", "host listens")
	host.set_my_deck(MatchLaunch.engine_deck(db.catalog, DeckCode.random_deck(db.catalog, rng), "Host", rng))
	client = NetClient.new("Guest", "0.1.0", db.version)
	root.add_child(client)
	_check(client.connect_to("127.0.0.1", PORT) == "", "client connects")
	var waited: float = 0.0
	while not client.link.connected and waited < 4.0:
		await create_timer(0.1).timeout
		waited += 0.1
	await create_timer(0.5).timeout
	_check(client.slot == 1, "client got seat 1 (got %d)" % client.slot)
	client.send_deck(MatchLaunch.engine_deck(db.catalog, DeckCode.random_deck(db.catalog, rng), "Guest", rng))
	client.send_ready(true)
	await create_timer(0.4).timeout
	_check(host.start(11) == "", "host starts: " + host.can_start())
	await create_timer(0.5).timeout
	_check(client.state != null, "client has a state")
	_check(host.add_bot("hard", {}) == "the table is full", "no third seat in 1v1")

	# The match scene as the client.
	MatchLaunch.config = {"net": {"role": "client", "node": client}, "settings": MatchSettings.from_dict(client.settings), "decks": [], "bots": PackedInt32Array(), "seed": 0}
	var scene: Node = (load("res://scenes/match/match.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await create_timer(0.3).timeout
	_check(str(scene.get("net_role")) == "client", "client scene up")
	_check(_hud(scene).local_slots == PackedInt32Array([1]), "client plays seat 1 only")
	_check(JsonUtil.as_dict(scene.get("bots")).is_empty(), "client runs no bots")
	scene.call("_apply", Move.make(Move.MULLIGAN, 1, {"keep": true}))
	scene.call("_apply", Move.make(Move.MULLIGAN, 0, {"keep": true}))
	await create_timer(0.5).timeout
	_check(_state(scene).player(1).mulligan_done, "client's mulligan reached the host and came back")
	_check(not _state(scene).player(0).mulligan_done, "client cannot move for the host")
	scene.queue_free()
	await create_timer(0.2).timeout

	# The match scene as the host: its moves reach the client as states.
	var before: int = host.recorder.record.frame_count()
	MatchLaunch.config = {"net": {"role": "host", "node": host}, "settings": host.settings, "decks": [], "bots": PackedInt32Array(), "seed": 0}
	scene = (load("res://scenes/match/match.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await create_timer(0.3).timeout
	_check(str(scene.get("net_role")) == "host", "host scene up")
	_check(_hud(scene).local_slots == PackedInt32Array([0]), "host plays seat 0 only")
	_check(JsonUtil.as_dict(scene.get("bots")).is_empty(), "no bots at this table")
	scene.call("_apply", Move.make(Move.MULLIGAN, 0, {"keep": true}))
	await create_timer(0.6).timeout
	_check(host.recorder.record.frame_count() > before, "the match moved on (%d → %d frames)" % [before, host.recorder.record.frame_count()])
	_check(client.state.phase == host.state().phase, "client is in the host's phase (%s)" % client.state.phase)
	scene.queue_free()
	await create_timer(0.2).timeout
	print("net smoke: %d failures" % fails)
	quit(1 if fails > 0 else 0)
