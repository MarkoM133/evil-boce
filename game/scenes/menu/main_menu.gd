extends Control
## Main menu (GDD 7) in the web app's look: the hero strip on top, the logo on the left and big
## italic entries on the right that slide in one after another. Every entry works: Continue (an
## unfinished match), Play, Online, Sandbox, Replays, Decks, Settings and Exit.

const SANDBOX_SCENE: String = "res://scenes/sandbox/sandbox.tscn"
const SETUP_SCENE: String = "res://scenes/match/match_setup.tscn"
const LOBBY_SCENE: String = "res://scenes/net/lobby.tscn"
const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const REPLAYS_SCENE: String = "res://scenes/replays/replays_menu.tscn"
const SETTINGS_SCENE: String = "res://scenes/menu/settings_menu.tscn"
const DECKS_SCENE: String = "res://scenes/decks/decks_menu.tscn"

## [label, action, what it is]
const ENTRIES: Array = [
	["PLAY", "play", "Against the bot, or two players on this computer"],
	["ONLINE", "online", "Host a match or join one over Tailscale"],
	["SANDBOX", "sandbox", "Throw balls around, try terrain"],
	["REPLAYS", "replays", "Watch past matches, continue from any phase"],
	["DECKS", "decks", "Your decks, deck codes"],
	["SETTINGS", "settings", "Shared folder, display, sound, keys"],
	["EXIT", "exit", ""],
]


func _ready() -> void:
	theme = UiTheme.get_theme()
	GameSettings.apply(get_tree())
	var db := CardDb.load_from(GameSettings.data_path())
	var logo: Texture2D = db.logo()
	if logo != null:
		DisplayServer.set_icon(logo.get_image())

	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var strip := HeroStrip.new()
	strip.setup(db)
	strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip.custom_minimum_size = Vector2(0, 150)
	add_child(strip)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_top = 170
	row.offset_bottom = -50
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 80)
	add_child(row)

	# Left: the logo, big.
	var left := CenterContainer.new()
	left.custom_minimum_size = Vector2(560, 0)
	row.add_child(left)
	if logo != null:
		var img := TextureRect.new()
		img.texture = logo
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.custom_minimum_size = Vector2(520, 480)
		left.add_child(img)
		img.pivot_offset = Vector2(260, 240)
		img.scale = Vector2(0.9, 0.9)
		img.modulate.a = 0.0
		var lt: Tween = img.create_tween().set_parallel(true)
		lt.tween_property(img, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		lt.tween_property(img, "modulate:a", 1.0, 0.3)
	else:
		left.add_child(UiTheme.label("EVIL BOĆE", 110))

	# Right: the entries.
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 2)
	right.custom_minimum_size = Vector2(520, 0)
	row.add_child(right)
	var entries: Array = ENTRIES.duplicate()
	# A match left unfinished (quit or crash) comes back first.
	if ReplayStore.has_current():
		entries.push_front(["CONTINUE", "continue", "Back to the match you left"])
	var first: Button = null
	for i: int in entries.size():
		var entry: Array = entries[i]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		right.add_child(line)
		var num: Label = UiTheme.label("%02d" % (i + 1), 18, Palette.DIM)
		num.custom_minimum_size = Vector2(30, 0)
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(num)
		var b := Button.new()
		b.text = str(entry[0])
		b.theme_type_variation = &"MenuItem"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(250, 0)
		var action: String = str(entry[1])
		if action == "continue":
			b.add_theme_color_override("font_color", Palette.GOLD)
		b.pressed.connect(_on_pressed.bind(action))
		b.mouse_entered.connect(func() -> void: b.grab_focus())
		line.add_child(b)
		var what := Label.new()
		what.text = str(entry[2])
		what.add_theme_color_override("font_color", Palette.MUTED)
		what.add_theme_font_size_override("font_size", 13)
		what.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		what.visible = false
		line.add_child(what)
		b.focus_entered.connect(func() -> void: what.visible = true)
		b.focus_exited.connect(func() -> void: what.visible = false)
		if first == null:
			first = b
		# Entries slide in from the right, one after another.
		line.modulate.a = 0.0
		var t: Tween = line.create_tween().set_parallel(true)
		t.tween_property(line, "modulate:a", 1.0, 0.2).set_delay(0.05 * i + 0.1)
		t.tween_property(num, "position:x", 0.0, 0.25).from(60.0).set_delay(0.05 * i + 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if first != null:
		first.grab_focus.call_deferred()

	var foot := Label.new()
	foot.add_theme_color_override("font_color", Palette.DIM)
	foot.add_theme_font_size_override("font_size", 13)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.position = Vector2(18, -34)
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	if db.is_ok():
		foot.text = "v%s  ·  cards v%d, %d cards  ·  %s" % [version, db.version, db.card_count, db.root_dir]
	else:
		foot.text = "v%s  ·  %s  ·  set the shared folder in Settings" % [version, db.error]
		foot.add_theme_color_override("font_color", Palette.GOLD)
	add_child(foot)


func _on_pressed(action: String) -> void:
	match action:
		"continue":
			var record: MatchRecord = ReplayStore.load_current()
			if record == null or record.frame_count() == 0:
				ReplayStore.clear_current()
				get_tree().reload_current_scene()
				return
			MatchLaunch.config = MatchLaunch.from_record(record)
			get_tree().change_scene_to_file(MATCH_SCENE)
		"play":
			get_tree().change_scene_to_file(SETUP_SCENE)
		"online":
			get_tree().change_scene_to_file(LOBBY_SCENE)
		"replays":
			get_tree().change_scene_to_file(REPLAYS_SCENE)
		"sandbox":
			get_tree().change_scene_to_file(SANDBOX_SCENE)
		"settings":
			get_tree().change_scene_to_file(SETTINGS_SCENE)
		"decks":
			get_tree().change_scene_to_file(DECKS_SCENE)
		"exit":
			get_tree().quit()
