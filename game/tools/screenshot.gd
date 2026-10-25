extends SceneTree
## Loads a scene, optionally calls methods on it, waits, saves a PNG to game/.shots/, quits.
## godot_console --path game -s res://tools/screenshot.gd -- --scene=res://scenes/sandbox/sandbox.tscn
##     [--frames=90] [--out=sandbox.png] [--call=demo_setup,demo_closeup] [--size=1600x900]
## Methods in --call run one after another, `--wait` frames apart (default 30). Runs at 60 FPS.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 60
	var opts: Dictionary[String, String] = {
		"scene": "res://scenes/menu/main_menu.tscn",
		"frames": "90",
		"out": "shot.png",
		"call": "",
		"wait": "30",
		"size": "1600x900",
	}
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--") and arg.contains("="):
			opts[arg.substr(2, arg.find("=") - 2)] = arg.substr(arg.find("=") + 1)
	var dims: PackedStringArray = opts["size"].split("x")
	if dims.size() == 2:
		DisplayServer.window_set_size(Vector2i(int(dims[0]), int(dims[1])))
	var packed := load(opts["scene"]) as PackedScene
	if packed == null:
		push_error("Cannot load scene " + opts["scene"])
		quit(1)
		return
	var node: Node = packed.instantiate()
	root.add_child(node)
	current_scene = node
	await _frames(5)
	for m: String in opts["call"].split(",", false):
		if node.has_method(m):
			node.call(m)
		else:
			push_error("Scene has no method " + m)
		await _frames(int(opts["wait"]))
	await _frames(int(opts["frames"]))
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var dir: String = ProjectSettings.globalize_path("res://.shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var path: String = dir.path_join(opts["out"])
	img.save_png(path)
	print("Saved " + path)
	quit()


func _frames(n: int) -> void:
	for i: int in n:
		await process_frame
