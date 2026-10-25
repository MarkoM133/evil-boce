extends Control
## Settings (GDD 7): the shared data folder, the online name, display, sound and keys. Every
## change is saved and applied at once; the data folder is checked as it is typed.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const KEY_LABELS: Dictionary[String, String] = {"pass": "Pass / end the round", "menu": "Menu / cancel",
	"card_zoom": "Show a card big"}

var _data_path: LineEdit
var _data_check: Label
var _key_buttons: Dictionary[String, Button] = {}
## The action waiting for a key press ("" when none).
var _binding: String = ""
var _browse: FileDialog


func _ready() -> void:
	var frame: Dictionary = MenuScreen.build(self, CardDb.load_from(GameSettings.data_path()), "Settings",
		"Saved at once; display changes apply straight away.", _back, 760.0)
	var content: VBoxContainer = frame["content"]
	var col: VBoxContainer = MenuScreen.card(content, 26)
	col.add_theme_constant_override("separation", 8)

	_header(col, "GAME")
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

	_header(col, "DISPLAY")
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
	var q := _option(col, "Quality", ["Low  ·  no shadows, faster", "Medium", "High  ·  softer shadows"],
			GameSettings.QUALITIES.find(GameSettings.quality()))
	q.item_selected.connect(func(i: int) -> void: _store("display", "quality", GameSettings.QUALITIES[i]))

	_header(col, "EFFECTS")
	var hs := _option(col, "Hit-stop", ["Off", "On  ·  a blink of freeze when damage lands"], 1 if GameSettings.effect("hit_stop") else 0)
	hs.item_selected.connect(func(i: int) -> void: _store("effects", "hit_stop", i == 1))
	var sm := _option(col, "Slow motion", ["Off", "On  ·  when a ball goes over the edge"], 1 if GameSettings.effect("slow_mo") else 0)
	sm.item_selected.connect(func(i: int) -> void: _store("effects", "slow_mo", i == 1))

	_header(col, "SOUND")
	for bus: String in GameSettings.BUSES:
		_volume(col, bus)

	_header(col, "KEYS")
	for action: String in GameSettings.DEFAULT_KEYS:
		row = _row(col, KEY_LABELS[action])
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
	var note := Label.new()
	note.theme_type_variation = &"Muted"
	note.text = "Mouse: drag to aim, right click cancels, wheel zooms. Home resets the camera. Right click on a card or a hero shows its card big."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)

	_show_keys()
	_check_data()


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
