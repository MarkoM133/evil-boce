extends Control
## Settings (GDD 7), in tabs: Game (shared folder, name, how a match plays), Interface (what the
## screen shows), Graphics, Sound, Keys. Every change is saved and applied at once; the data
## folder is checked as it is typed. Laid out as chosen (Marko 2026-11-11, S2): the tabs a column on the left, a
## choice of two or three a row of buttons (a drop-down only for long lists), and what a setting does in one line
## at the bottom for the hovered one. Sound is greyed out while the game has no sound.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const KEY_LABELS: Dictionary[String, String] = {"pass": "Pass / end the round", "menu": "Menu / cancel",
	"card_zoom": "Show a card big", "battle_cam": "Battle camera on / off", "hold": "Hold (no auto-pass while down)",
	"beams": "Beams on heroes on / off", "table_text": "Words over the table on / off", "stage_strip": "Stage and core boxes open / folded"}
const TABS: Array[String] = ["GAME", "INTERFACE", "GRAPHICS", "SOUND", "KEYS"]

## The tab last open, kept while the game runs.
static var _last_tab: int = 0

## Opened over a match from the pause menu (Marko 2026-11-07): Back (or Esc) calls this and the
## match goes on, instead of going to the main menu.
var on_back: Callable = Callable()

var _data_path: LineEdit
var _data_check: Label
var _key_buttons: Dictionary[String, Button] = {}
## The action waiting for a key press ("" when none).
var _binding: String = ""
var _browse: FileDialog
var _pages: Array[VBoxContainer] = []
var _nav: VBoxContainer
## The line at the bottom: what the hovered setting does.
var _foot: Label
## The row the next _hint belongs to (null after a heading).
var _last_row: HBoxContainer

## A choice of a few values as buttons side by side (or a drop-down for a long list); `item_selected` as
## OptionButton has it, so every setting connects the same way.
class Choice extends HBoxContainer:
	signal item_selected(index: int)
	var _buttons: Array[Button] = []

	func setup(items: Array[String], selected: int) -> void:
		add_theme_constant_override("separation", 6)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if items.size() > 3:
			var o := OptionButton.new()
			for it: String in items:
				o.add_item(it)
			o.select(selected)
			o.custom_minimum_size = Vector2(240, 0)
			o.item_selected.connect(func(i: int) -> void: item_selected.emit(i))
			add_child(o)
			return
		for i: int in items.size():
			var b := Button.new()
			b.text = items[i].to_upper()
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 17)
			b.custom_minimum_size = Vector2(130, 0)
			var at: int = i
			b.pressed.connect(func() -> void:
				_mark(at)
				item_selected.emit(at))
			add_child(b)
			_buttons.append(b)
		_mark(selected)

	func _mark(i: int) -> void:
		for k: int in _buttons.size():
			_buttons[k].theme_type_variation = &"Gold" if k == i else &""


func _ready() -> void:
	var frame: Dictionary = MenuScreen.build(self, CardDb.load_from(GameSettings.data_path()), "Settings",
		"Saved at once; display changes apply straight away.", _back, 1060.0)
	var content: VBoxContainer = frame["content"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	content.add_child(row)
	_nav = VBoxContainer.new()
	_nav.add_theme_constant_override("separation", 6)
	_nav.custom_minimum_size.x = 210
	row.add_child(_nav)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)
	for t: String in TABS:
		var page: VBoxContainer = MenuScreen.card(right, 26, true)
		page.add_theme_constant_override("separation", 8)
		_pages.append(page)
	_foot = Label.new()
	_foot.theme_type_variation = &"Muted"
	_foot.add_theme_font_size_override("font_size", 15)
	_foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_foot.custom_minimum_size = Vector2(0, 44)
	right.add_child(_foot)
	_build_game(_pages[0])
	_build_interface(_pages[1])
	_build_graphics(_pages[2])
	_build_sound(_pages[3])
	_build_keys(_pages[4])
	_show_tab(_last_tab)
	_show_keys()
	_check_data()


## Shows tab `i` (and only its card); the column on the left marks which one. Sound is greyed out while the
## game has no sound (Marko 2026-11-11).
func _show_tab(i: int) -> void:
	if TABS[i] == "SOUND":
		i = 0
	_last_tab = i
	for k: int in _pages.size():
		(_pages[k].get_parent() as Control).visible = k == i
	_foot.text = "Hover a setting to read what it does."
	for c: Node in _nav.get_children():
		c.queue_free()
	for k: int in TABS.size():
		var b := Button.new()
		b.text = TABS[k]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 26)
		b.theme_type_variation = &"Primary" if k == i else &""
		if TABS[k] == "SOUND":
			b.disabled = true
			b.tooltip_text = "No sound in the game yet."
			b.modulate = Color(1, 1, 1, 0.4)
		var idx: int = k
		b.pressed.connect(func() -> void: _show_tab(idx))
		_nav.add_child(b)


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
	open_web.text = "OPEN"
	open_web.icon = WebApp.external_icon()
	open_web.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	open_web.pressed.connect(func() -> void: WebApp.open())
	row.add_child(open_web)
	_hint(col, "GitHub Pages works for everyone; the local server is http://localhost:5100/ while it runs. Empty goes back to Pages.")
	var dc := _option(col, "Discord status", ["Shown  ·  friends see the match you play", "Off"], 0 if GameSettings.discord() else 1)
	dc.item_selected.connect(func(i: int) -> void:
		_store("online", "discord", i == 0)
		if i == 0:
			DiscordPresence.refresh())

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
	# The layout and, with Cinema, what fills its middle, in one (Marko 2026-11-11).
	var menus: Array[String] = ["Side strip", "Cinema, logo only", "Cinema, last match and what's new", "Cinema, table with balls"]
	var menu_at: int = 0 if GameSettings.menu_layout() == "strip" else 1 + maxi(0, GameSettings.CINEMA_FILLS.find(GameSettings.cinema_fill()))
	var layout := _option(col, "Main menu", menus, menu_at)
	layout.item_selected.connect(func(i: int) -> void:
		_store("display", "menu_layout", "strip" if i == 0 else "cinema")
		if i > 0:
			_store("display", "cinema_fill", GameSettings.CINEMA_FILLS[i - 1]))
	var splash := _option(col, "Splash at start", ["Shown", "Skipped"], 0 if GameSettings.splash() else 1)
	splash.item_selected.connect(func(i: int) -> void: _store("display", "splash", i == 0))
	var cur := _option(col, "Cursor", ["Game  ·  the slanted arrow, red over what can be clicked", "System  ·  the plain Windows arrow"], 0 if GameSettings.game_cursor() else 1)
	cur.item_selected.connect(func(i: int) -> void: _store("display", "game_cursor", i == 0))

	# Beams, words over the table and the stage boxes are switched in a match (keys B, T and G) and kept from
	# there; their keys are on the Keys tab (Marko 2026-11-11: not twice).
	_header(col, "ON THE TABLE")
	var rng := _option(col, "Range circles", ["Activated heroes always, others on hover", "Only on hover"],
		GameSettings.RANGE_MODES.find(GameSettings.range_mode()))
	rng.item_selected.connect(func(i: int) -> void: _store("display", "range", GameSettings.RANGE_MODES[i]))
	var tips := _option(col, "Card text on hover", ["Shown", "Off"], 0 if GameSettings.hover_text() else 1)
	tips.item_selected.connect(func(i: int) -> void: _store("display", "hover_text", i == 0))
	_hint(col, "Right click or Alt still shows any card big.")
	var ban := _option(col, "Banners", ["All, phases too", "Big moments only", "Off"],
		GameSettings.BANNER_MODES.find(GameSettings.banners()))
	ban.item_selected.connect(func(i: int) -> void: _store("display", "banners", GameSettings.BANNER_MODES[i]))


func _build_graphics(col: VBoxContainer) -> void:
	_header(col, "WINDOW")
	var mode := _option(col, "Window", ["Windowed", "Fullscreen"], 1 if GameSettings.fullscreen() else 0)
	mode.item_selected.connect(func(i: int) -> void: _store("display", "fullscreen", i == 1))
	var sizes: Array[String] = []
	for r: Vector2i in GameSettings.RESOLUTIONS:
		sizes.append("%d × %d" % [r.x, r.y])
	var res := _option(col, "Window size", sizes, maxi(0, GameSettings.RESOLUTIONS.find(GameSettings.resolution())))
	res.item_selected.connect(func(i: int) -> void: _store("display", "resolution", GameSettings.RESOLUTIONS[i]))
	# VSync and the frame limit in one (Marko 2026-11-11): VSync, or a limit, or none.
	var rates: Array[String] = ["VSync (the monitor's rate)"]
	var limits: Array[int] = []
	for f: int in GameSettings.FPS_LIMITS:
		if f > 0:
			rates.append("%d" % f)
			limits.append(f)
	rates.append("No limit")
	limits.append(0)
	var rate_at: int = 0 if GameSettings.vsync() else 1 + maxi(0, limits.find(GameSettings.max_fps()))
	var rate := _option(col, "Frame rate", rates, rate_at)
	rate.item_selected.connect(func(i: int) -> void:
		GameSettings.set_value("display", "max_fps", 0 if i == 0 else limits[i - 1])
		_store("display", "vsync", i == 0))
	var fps := _option(col, "FPS counter", ["Off", "On"], 1 if GameSettings.show_fps() else 0)
	fps.item_selected.connect(func(i: int) -> void: _store("display", "fps", i == 1))

	_header(col, "QUALITY AND EFFECTS")
	var q := _option(col, "Quality", ["Low  ·  no shadows, faster", "Medium", "High  ·  softer shadows"],
			GameSettings.QUALITIES.find(GameSettings.quality()))
	q.item_selected.connect(func(i: int) -> void: _store("display", "quality", GameSettings.QUALITIES[i]))
	# Hit-stop, slow motion and camera shake in one (Marko 2026-11-11).
	var impact_at: int = 0 if GameSettings.effect("shake") else (1 if GameSettings.effect("hit_stop") or GameSettings.effect("slow_mo") else 2)
	var impact := _option(col, "Impact effects", ["All", "No shake", "Off"], impact_at)
	impact.item_selected.connect(func(i: int) -> void:
		GameSettings.set_value("effects", "hit_stop", i < 2)
		GameSettings.set_value("effects", "slow_mo", i < 2)
		_store("effects", "shake", i == 0))
	_hint(col, "All: a blink of freeze when damage lands, slow motion on a ball over the edge (without Evil Bochet) and on his claws taking a fallen hero, and the view jolting on a KO and when he grabs a ball. No shake: the same without the jolt.")
	# Hands only: his hands hold the table, no eyes under it (Marko 2026-11-13).
	var bochet_at: int = 0 if not GameSettings.effect("bochet") else (2 if GameSettings.effect("bochet_eyes") else 1)
	var bo := _option(col, "Evil Bochet", ["Off  ·  the table stands on its slab", "Hands only  ·  his hands hold the table, no eyes",
		"On  ·  hands and eyes"], bochet_at)
	bo.item_selected.connect(func(i: int) -> void:
		GameSettings.set_value("effects", "bochet_eyes", i == 2)
		_store("effects", "bochet", i > 0))
	# Under his table (Marko 2026-11-13): the abyss with mist, or a violet light; from the next match.
	var under := _option(col, "Under the table", ["Abyss  ·  mist and embers, no floor", "Light  ·  a dim violet glow"],
		1 if GameSettings.under_table() == "light" else 0)
	under.item_selected.connect(func(i: int) -> void: _store("effects", "under_table", "light" if i == 1 else "abyss"))


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
	_hint(col, "Drag a ball back to aim, release to throw; right click cancels. Wheel zooms, drag the table to move the camera, right drag turns it, Home resets it. Right click on a card or a hero shows its card big.")


## What the setting just above does: shown at the bottom while it is hovered; text with no row to go with (under a
## heading) stays on the page.
func _hint(parent: Control, text: String) -> void:
	if _last_row != null and not _last_row.has_meta("hint"):
		_last_row.set_meta("hint", text)
		return
	var note := Label.new()
	note.theme_type_variation = &"Muted"
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	parent.add_child(note)


func _header(parent: Control, text: String) -> void:
	_last_row = null
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
	l.custom_minimum_size = Vector2(230, 0)
	row.add_child(l)
	_last_row = row
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.mouse_entered.connect(func() -> void:
		if row.has_meta("hint"):
			_foot.text = str(row.get_meta("hint")))
	return row


## A setting: its name and the choice. An item "On  ·  what it does" is a button ON, and what it does goes to the
## setting's line at the bottom.
func _option(parent: Control, label: String, items: Array[String], selected: int) -> Choice:
	var names: Array[String] = []
	var notes := PackedStringArray()
	for it: String in items:
		var parts: PackedStringArray = it.split("  ·  ", true, 1)
		names.append(parts[0] if items.size() <= 3 else it)
		if items.size() <= 3 and parts.size() > 1:
			notes.append("%s: %s" % [parts[0], parts[1]])
	var c := Choice.new()
	c.setup(names, selected)
	var row: HBoxContainer = _row(parent, label)
	row.add_child(c)
	if not notes.is_empty():
		row.set_meta("hint", ". ".join(notes) + ".")
	return c


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
		get_viewport().set_input_as_handled()
		_back()


func _back() -> void:
	_save_data()
	if on_back.is_valid():
		on_back.call()
		return
	get_tree().change_scene_to_file(MENU_SCENE)


## Screenshot helper: the Interface tab.
func demo_interface() -> void:
	_show_tab(1)
