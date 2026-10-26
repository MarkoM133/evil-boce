extends Control
## Settings (GDD 7), in tabs: Game (shared folder, name, how a match plays), Interface (what the
## screen shows), Graphics, Sound, Keys. Every change is saved and applied at once; the data
## folder is checked as it is typed.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const KEY_LABELS: Dictionary[String, String] = {"pass": "Pass / end the round", "menu": "Menu / cancel",
	"card_zoom": "Show a card big", "battle_cam": "Battle camera on / off", "hold": "Hold (no auto-pass while down)",
	"beams": "Beams on heroes on / off"}
const TABS: Array[String] = ["GAME", "INTERFACE", "GRAPHICS", "SOUND", "KEYS"]

## The tab last open, kept while the game runs.
static var _last_tab: int = 0

var _data_path: LineEdit
var _data_check: Label
var _key_buttons: Dictionary[String, Button] = {}
## The action waiting for a key press ("" when none).
var _binding: String = ""
var _browse: FileDialog
var _pages: Array[VBoxContainer] = []
var _tab_chips: HBoxContainer


func _ready() -> void:
	var frame: Dictionary = MenuScreen.build(self, CardDb.load_from(GameSettings.data_path()), "Settings",
		"Saved at once; display changes apply straight away.", _back, 820.0)
	var content: VBoxContainer = frame["content"]
	_tab_chips = HBoxContainer.new()
	_tab_chips.add_theme_constant_override("separation", 6)
	content.add_child(_tab_chips)
	for t: String in TABS:
		var page: VBoxContainer = MenuScreen.card(content, 26)
		page.add_theme_constant_override("separation", 8)
		_pages.append(page)
	_build_game(_pages[0])
	_build_interface(_pages[1])
	_build_graphics(_pages[2])
	_build_sound(_pages[3])
	_build_keys(_pages[4])
	_show_tab(_last_tab)
	_show_keys()
	_check_data()


## Shows tab `i` (and only its card); the chips mark which one.
func _show_tab(i: int) -> void:
	_last_tab = i
	for k: int in _pages.size():
		(_pages[k].get_parent() as Control).visible = k == i
	for c: Node in _tab_chips.get_children():
		c.queue_free()
	for k: int in TABS.size():
		var on: bool = k == i
		var chip: UiShape = UiShape.chip(TABS[k], Palette.ACCENT if on else Palette.PANEL_SOLID,
			Palette.FG if on else Palette.MUTED, 18, 36.0, 18.0)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var idx: int = k
		chip.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_show_tab(idx))
		_tab_chips.add_child(chip)


func _build_game(col: VBoxContainer) -> void:
	_header(col, "SHARED FOLDER AND NAME")
	var row := _row(col, "Shared folder")
	_data_path = LineEdit.new()
	_data_path.text = GameSettings.data_path()
	_data_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_data_path.tooltip_text = "The Syncthing folder with data/cards.json, sprites and decks"
	_data_path.text_changed.connect(func(_t: String) -> void: _check_data())
	_data_path.text_submitted.connect(func(_t: String) -> void: _save_data())
	_data_path.focus_exited.connect(_save_data)
	row.add_child(_data_path)
	var browse := Button.new()
	browse.text = "Browse…"
	browse.pressed.connect(_open_browse)
	row.add_child(browse)
	_data_check = Label.new()
	_data_check.theme_type_variation = &"Muted"
	_data_check.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_data_check)
	row = _row(col, "Name online")
	var name_edit := LineEdit.new()
	name_edit.text = GameSettings.player_name()
	name_edit.max_length = 24
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(t: String) -> void: GameSettings.set_player_name(t))
	row.add_child(name_edit)
	row = _row(col, "Web app")
	var web := LineEdit.new()
	web.text = GameSettings.web_app_url()
	web.placeholder_text = WebApp.DEFAULT_URL
	web.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	web.tooltip_text = "Where the deck builder and card studio open"
	web.text_changed.connect(func(t: String) -> void: GameSettings.set_web_app_url(t))
	row.add_child(web)
	var open_web := Button.new()
	open_web.text = "OPEN  ↗"
	open_web.pressed.connect(func() -> void: WebApp.open())
	row.add_child(open_web)
	_hint(col, "GitHub Pages works for everyone; the local server is http://localhost:5100/ while it runs. Empty goes back to Pages.")

	_header(col, "IN A MATCH")
	var ap := _option(col, "Auto-pass", ["On", "Off"], 0 if GameSettings.auto_pass() else 1)
	ap.item_selected.connect(func(i: int) -> void: _store("display", "auto_pass", i == 0))
	_hint(col, "Passes for you after a short wait when you have nothing to play. Hold Ctrl to stop it.")
	var bcam := _option(col, "Battle camera", ["Flies to each battle", "Off"], 0 if GameSettings.battle_cam_auto() else 1)
	bcam.item_selected.connect(func(i: int) -> void: _store("display", "battle_cam", i == 0))
	var speed := _option(col, "Animation speed", ["Normal", "Fast"], GameSettings.ANIM_SPEEDS.find(GameSettings.anim_speed()))
	speed.item_selected.connect(func(i: int) -> void: _store("display", "anim_speed", GameSettings.ANIM_SPEEDS[i]))
	_hint(col, "Fast shortens banners, knockback and the battle camera's waits.")

	_header(col, "RESET")
	var reset := Button.new()
	reset.text = "Reset all settings"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		# A second click does it (no dialog in the way).
		if reset.text != "Click again to reset":
			reset.text = "Click again to reset"
			return
		GameSettings.reset_to_defaults()
		GameSettings.apply(get_tree(), true)
		get_tree().reload_current_scene())
	col.add_child(reset)
	_hint(col, "Interface, graphics, sound and keys go back to their defaults. The shared folder, your name and your decks stay.")


func _build_interface(col: VBoxContainer) -> void:
	_header(col, "SIZE AND MENU")
	var scales: Array[String] = []
	for s: float in GameSettings.UI_SCALES:
		scales.append("%d %%" % roundi(s * 100.0))
	var near: int = 0
	for i: int in GameSettings.UI_SCALES.size():
		if absf(GameSettings.UI_SCALES[i] - GameSettings.ui_scale()) < absf(GameSettings.UI_SCALES[near] - GameSettings.ui_scale()):
			near = i
	var ui := _option(col, "Interface size", scales, near)
	ui.item_selected.connect(func(i: int) -> void: _store("display", "ui_scale", GameSettings.UI_SCALES[i]))
	var layout := _option(col, "Main menu", ["Side strip", "Cinema"], GameSettings.MENU_LAYOUTS.find(GameSettings.menu_layout()))
	layout.item_selected.connect(func(i: int) -> void: _store("display", "menu_layout", GameSettings.MENU_LAYOUTS[i]))
	var fill := _option(col, "Cinema middle", ["Logo only", "Last match, what's new", "Table with balls"], GameSettings.CINEMA_FILLS.find(GameSettings.cinema_fill()))
	fill.item_selected.connect(func(i: int) -> void: _store("display", "cinema_fill", GameSettings.CINEMA_FILLS[i]))
	var splash := _option(col, "Splash at start", ["Shown", "Skipped"], 0 if GameSettings.splash() else 1)
	splash.item_selected.connect(func(i: int) -> void: _store("display", "splash", i == 0))

	_header(col, "ON THE TABLE")
	var beams := _option(col, "Beams on heroes", ["On", "Off"], 0 if GameSettings.beams() else 1)
	beams.item_selected.connect(func(i: int) -> void: _store("display", "beams", i == 0))
	_hint(col, "The light over the heroes a card or a pick points at; the rings always show. Key B switches it in a match.")
	var rng := _option(col, "Range circles", ["Activated heroes always, others on hover", "Only on hover"],
		GameSettings.RANGE_MODES.find(GameSettings.range_mode()))
	rng.item_selected.connect(func(i: int) -> void: _store("display", "range", GameSettings.RANGE_MODES[i]))

	_header(col, "TEXT AND BANNERS")
	var tips := _option(col, "Card text on hover", ["Shown", "Off"], 0 if GameSettings.hover_text() else 1)
	tips.item_selected.connect(func(i: int) -> void: _store("display", "hover_text", i == 0))
	_hint(col, "Right click or Alt still shows any card big.")
	var ban := _option(col, "Banners", ["All, phases too", "Big moments only", "Off"],
		GameSettings.BANNER_MODES.find(GameSettings.banners()))
	ban.item_selected.connect(func(i: int) -> void: _store("display", "banners", GameSettings.BANNER_MODES[i]))
	var fps := _option(col, "FPS counter", ["Off", "On"], 1 if GameSettings.show_fps() else 0)
	fps.item_selected.connect(func(i: int) -> void: _store("display", "fps", i == 1))


func _build_graphics(col: VBoxContainer) -> void:
	_header(col, "WINDOW")
	var mode := _option(col, "Window", ["Windowed", "Fullscreen"], 1 if GameSettings.fullscreen() else 0)
	mode.item_selected.connect(func(i: int) -> void: _store("display", "fullscreen", i == 1))
	var sizes: Array[String] = []
	for r: Vector2i in GameSettings.RESOLUTIONS:
		sizes.append("%d × %d" % [r.x, r.y])
	var res := _option(col, "Window size", sizes, maxi(0, GameSettings.RESOLUTIONS.find(GameSettings.resolution())))
	res.item_selected.connect(func(i: int) -> void: _store("display", "resolution", GameSettings.RESOLUTIONS[i]))
	var vsync := _option(col, "VSync", ["Off", "On"], 1 if GameSettings.vsync() else 0)
	vsync.item_selected.connect(func(i: int) -> void: _store("display", "vsync", i == 1))
	var fps_names: Array[String] = []
	for f: int in GameSettings.FPS_LIMITS:
		fps_names.append("No limit" if f == 0 else "%d" % f)
	var fps := _option(col, "Frame limit", fps_names, maxi(0, GameSettings.FPS_LIMITS.find(GameSettings.max_fps())))
	fps.item_selected.connect(func(i: int) -> void: _store("display", "max_fps", GameSettings.FPS_LIMITS[i]))

	_header(col, "QUALITY AND EFFECTS")
	var q := _option(col, "Quality", ["Low  ·  no shadows, faster", "Medium", "High  ·  softer shadows"],
			GameSettings.QUALITIES.find(GameSettings.quality()))
	q.item_selected.connect(func(i: int) -> void: _store("display", "quality", GameSettings.QUALITIES[i]))
	var hs := _option(col, "Hit-stop", ["Off", "On  ·  a blink of freeze when damage lands"], 1 if GameSettings.effect("hit_stop") else 0)
	hs.item_selected.connect(func(i: int) -> void: _store("effects", "hit_stop", i == 1))
	var sm := _option(col, "Slow motion", ["Off", "On  ·  when a ball goes over the edge"], 1 if GameSettings.effect("slow_mo") else 0)
	sm.item_selected.connect(func(i: int) -> void: _store("effects", "slow_mo", i == 1))


func _build_sound(col: VBoxContainer) -> void:
	_header(col, "VOLUME")
	for bus: String in GameSettings.BUSES:
		_volume(col, bus)


func _build_keys(col: VBoxContainer) -> void:
	_header(col, "KEYS")
	for action: String in GameSettings.DEFAULT_KEYS:
		var row := _row(col, KEY_LABELS[action] if KEY_LABELS.has(action) else action)
		var b := Button.new()
		b.custom_minimum_size = Vector2(180, 0)
		b.pressed.connect(_start_binding.bind(action))
		row.add_child(b)
		_key_buttons[action] = b
	var zoom := _option(col, "Card zoom key", ["Hold it", "Press on / off"], GameSettings.ZOOM_MODES.find(GameSettings.zoom_mode()))
	zoom.item_selected.connect(func(i: int) -> void: _store("keys", "zoom_mode", GameSettings.ZOOM_MODES[i]))
	var reset := Button.new()
	reset.text = "Default keys"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_END
	reset.pressed.connect(func() -> void:
		GameSettings.reset_keys()
		_binding = ""
		_show_keys())
	col.add_child(reset)
	_header(col, "MOUSE")
	_hint(col, "Drag a ball back to aim, release to throw; right click cancels. Wheel zooms, drag the table to turn the camera, Home resets it. Right click on a card or a hero shows its card big.")


func _hint(parent: Control, text: String) -> void:
	var note := Label.new()
	note.theme_type_variation = &"Muted"
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	parent.add_child(note)


func _header(parent: Control, text: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	parent.add_child(gap)
	MenuScreen.heading(parent, text)


func _row(parent: Control, label: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(170, 0)
	row.add_child(l)
	return row


func _option(parent: Control, label: String, items: Array[String], selected: int) -> OptionButton:
	var o := OptionButton.new()
	for it: String in items:
		o.add_item(it)
	o.select(selected)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(parent, label).add_child(o)
	return o


func _volume(parent: Control, bus: String) -> void:
	var row := _row(parent, "Everything" if bus == "Master" else bus)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 5
	s.value = roundf(GameSettings.volume(bus) * 100.0)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var v := Label.new()
	v.custom_minimum_size = Vector2(48, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.text = "%d%%" % int(s.value)
	row.add_child(v)
	s.value_changed.connect(func(x: float) -> void:
		v.text = "%d%%" % int(x)
		_store("sound", bus.to_lower(), x / 100.0))


func _store(section: String, key_: String, value: Variant) -> void:
	GameSettings.set_value(section, key_, value)
	GameSettings.apply(get_tree(), section == "display")


# --- data folder ------------------------------------------------------------------------

func _check_data() -> void:
	var path: String = _data_path.text.strip_edges().replace("\\", "/")
	var db := CardDb.load_from(path)
	if db.is_ok():
		_data_check.text = "✓  cards.json v%d, %d cards" % [db.version, db.card_count]
		_data_check.remove_theme_color_override("font_color")
	else:
		_data_check.text = db.error
		_data_check.add_theme_color_override("font_color", Palette.GOLD)


func _save_data() -> void:
	var path: String = _data_path.text.strip_edges().replace("\\", "/")
	if path.is_empty() or path == GameSettings.data_path():
		return
	GameSettings.set_data_path(path)


func _open_browse() -> void:
	if _browse == null:
		_browse = FileDialog.new()
		_browse.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_browse.access = FileDialog.ACCESS_FILESYSTEM
		_browse.use_native_dialog = true
		_browse.title = "The shared Evil Boće folder"
		_browse.dir_selected.connect(func(dir: String) -> void:
			_data_path.text = dir.replace("\\", "/")
			_check_data()
			_save_data())
		add_child(_browse)
	_browse.current_dir = _data_path.text
	_browse.popup_centered(Vector2i(800, 500))


# --- keys -------------------------------------------------------------------------------

func _start_binding(action: String) -> void:
	_binding = action
	_show_keys()


func _show_keys() -> void:
	for action: String in _key_buttons:
		var b: Button = _key_buttons[action]
		b.text = "Press a key…" if action == _binding else GameSettings.key_name(GameSettings.key(action))


func _input(event: InputEvent) -> void:
	if _binding.is_empty() or not event is InputEventKey:
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return
	get_viewport().set_input_as_handled()
	# One key per action: taking a key from the other action swaps them.
	for other: String in GameSettings.DEFAULT_KEYS:
		if other != _binding and GameSettings.key(other) == k.keycode:
			GameSettings.set_key(other, GameSettings.key(_binding))
	GameSettings.set_key(_binding, k.keycode)
	_binding = ""
	_show_keys()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and GameSettings.logical_key((event as InputEventKey).keycode) == KEY_ESCAPE:
		_back()


func _back() -> void:
	_save_data()
	get_tree().change_scene_to_file(MENU_SCENE)


## Screenshot helper: the Interface tab.
func demo_interface() -> void:
	_show_tab(1)
