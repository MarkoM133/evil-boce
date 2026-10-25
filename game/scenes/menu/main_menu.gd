extends Control
## Main menu (GDD 7). Continue (an unfinished match), Play, Sandbox, Replays, Settings and Exit work.

const SANDBOX_SCENE: String = "res://scenes/sandbox/sandbox.tscn"
const SETUP_SCENE: String = "res://scenes/match/match_setup.tscn"
const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const REPLAYS_SCENE: String = "res://scenes/replays/replays_menu.tscn"
const SETTINGS_SCENE: String = "res://scenes/menu/settings_menu.tscn"


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

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	center.add_child(col)

	if logo != null:
		var img := TextureRect.new()
		img.texture = logo
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.custom_minimum_size = Vector2(460, 300)
		col.add_child(img)
	else:
		var title := Label.new()
		title.text = "EVIL BOĆE"
		title.add_theme_font_override("font", UiTheme.display_bold())
		title.add_theme_font_size_override("font_size", 96)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	col.add_child(gap)

	var first: Button = null
	var entries: Array = [["PLAY", "play"], ["SANDBOX", "sandbox"], ["REPLAYS", "replays"], ["DECKS", ""],
			["SETTINGS", "settings"], ["EXIT", "exit"]]
	# A match left unfinished (quit or crash) comes back first.
	if ReplayStore.has_current():
		entries.push_front(["CONTINUE", "continue"])
	for entry: Array in entries:
		var b := Button.new()
		b.text = str(entry[0])
		b.theme_type_variation = &"MenuItem"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(320, 0)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var action: String = str(entry[1])
		b.disabled = action.is_empty()
		if b.disabled:
			b.tooltip_text = "Coming in a later step"
			b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_pressed.bind(action))
		b.mouse_entered.connect(func() -> void: if not b.disabled: b.grab_focus())
		col.add_child(b)
		if first == null and (action == "continue" or action == "play"):
			first = b
	if first != null:
		first.grab_focus.call_deferred()

	var foot := Label.new()
	foot.theme_type_variation = &"Muted"
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.position = Vector2(16, -34)
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	if db.is_ok():
		foot.text = "v%s  ·  cards.json v%d, %d cards  ·  %s" % [version, db.version, db.card_count, db.root_dir]
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
		"replays":
			get_tree().change_scene_to_file(REPLAYS_SCENE)
		"sandbox":
			get_tree().change_scene_to_file(SANDBOX_SCENE)
		"settings":
			get_tree().change_scene_to_file(SETTINGS_SCENE)
		"exit":
			get_tree().quit()
