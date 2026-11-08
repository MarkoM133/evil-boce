extends SceneTree
## Dev: a match with Kaido on the map, a core in front of him and a wall beyond it, for trying a
## throw by hand. R sets it up again. Nothing is saved.
## godot --path game -s res://tools/try_kaido.gd
## With -- --check it throws once by itself, saves game/.shots/try_kaido.png and quits.

var _node: Node
var _r_down: bool = false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	var db: CardDb = CardDb.load_from(GameSettings.data_path())
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var settings: MatchSettings = MatchSettings.standard()
	settings.map_size = 23
	MatchLaunch.config = {
		"settings": settings,
		"decks": [
			MatchLaunch.engine_deck(db.catalog, DeckCode.random_deck(db.catalog, rng, PackedStringArray(["OP1-005", "", ""])), "Player 1", rng),
			MatchLaunch.engine_deck(db.catalog, DeckCode.random_deck(db.catalog, rng), "Bot", rng),
		],
		"bots": PackedInt32Array([1]),
		"seed": rng.randi(),
		"dev": true,
	}
	var packed := load("res://scenes/match/match.tscn") as PackedScene
	_node = packed.instantiate()
	root.add_child(_node)
	current_scene = _node
	await _frames(90)
	_node.call("demo_try_kaido")
	if OS.get_cmdline_user_args().has("--check"):
		_check()


func _check() -> void:
	await _frames(40)
	_node.call("demo_try_kaido_throw", 0.45)
	await _frames(300)
	_node.call("debug_dump")
	await RenderingServer.frame_post_draw
	var dir: String = ProjectSettings.globalize_path("res://.shots")
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir.path_join("try_kaido.png"))
	quit()


func _process(_delta: float) -> bool:
	var down: bool = Input.is_physical_key_pressed(KEY_R)
	if down and not _r_down and _node != null and is_instance_valid(_node):
		_node.call("demo_try_kaido")
	_r_down = down
	return false


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame
