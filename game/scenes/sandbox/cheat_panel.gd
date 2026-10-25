class_name CheatPanel
extends PanelContainer
## Sandbox side panel: map size, spawning heroes, the selected ball's WT / range / HP,
## terrain painting, view toggles and the last throw.

signal map_size_selected(n: int)
signal reset_pressed
signal spawn_toggled(on: bool)
## Terrain to paint, or -1 when painting is off.
signal terrain_tool_selected(terrain: int)
signal wt_changed(value: int)
signal range_changed(value: int)
signal hp_changed(value: int)
signal open_pressed
signal remove_pressed
signal show_path_toggled(on: bool)
signal auto_open_toggled(on: bool)

var heroes: Array[HeroDef] = []

var _hero_pick: OptionButton
var _team_buttons: Array[Button] = []
var _spawn_btn: Button
var _sel_box: VBoxContainer
var _sel_empty: Label
var _sel_name: Label
var _sel_info: Label
var _wt: SpinBox
var _rng: SpinBox
var _hp: SpinBox
var _open_btn: Button
var _terrain_btns: Array[Button] = []
## Hex.DIRECTIONS index for painted wind, and how each one looks from the default camera.
const WIND_ARROWS: Array[String] = ["→", "↘", "↙", "←", "↖", "↗"]
var _wind_dir: int = 0
var _last_big: Label
var _last_info: Label
var _data_info: Label
var _quiet: bool = false


func _init() -> void:
	custom_minimum_size = Vector2(300, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	scroll.add_child(col)

	var title := Label.new()
	title.text = "SANDBOX"
	title.theme_type_variation = &"Big"
	col.add_child(title)
	_data_info = _muted(col, "")

	_header(col, "MAP")
	var map_row := _row(col)
	var sizes := OptionButton.new()
	for n: int in GameSettings.MAP_SIZES:
		sizes.add_item("%d × %d" % [n, n], n)
	sizes.select(GameSettings.MAP_SIZES.find(GameSettings.map_size()))
	sizes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sizes.item_selected.connect(func(i: int) -> void: map_size_selected.emit(sizes.get_item_id(i)))
	map_row.add_child(sizes)
	var reset := _button(map_row, "Reset")
	reset.tooltip_text = "Remove all balls and terrain"
	reset.pressed.connect(func() -> void: reset_pressed.emit())

	_header(col, "SPAWN HERO")
	_hero_pick = OptionButton.new()
	_hero_pick.fit_to_longest_item = false
	col.add_child(_hero_pick)
	var team_row := _row(col)
	var group := ButtonGroup.new()
	for i: int in 2:
		var b := _button(team_row, Palette.TEAM_NAMES[i].to_upper())
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := UiTheme.box(Palette.team(i))
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_stylebox_override("hover_pressed", UiTheme.box(Palette.team(i).lightened(0.1)))
		_team_buttons.append(b)
	_team_buttons[0].button_pressed = true
	_spawn_btn = _button(col, "Place on map or strip")
	_spawn_btn.toggle_mode = true
	_spawn_btn.tooltip_text = "Click a hex or a start strip. Right click or Esc stops."
	_spawn_btn.toggled.connect(func(on: bool) -> void: spawn_toggled.emit(on))

	_header(col, "SELECTED")
	_sel_empty = _muted(col, "Click a ball to select it.")
	_sel_box = VBoxContainer.new()
	_sel_box.add_theme_constant_override("separation", 6)
	col.add_child(_sel_box)
	_sel_name = Label.new()
	_sel_name.add_theme_font_override("font", UiTheme.display_bold())
	_sel_name.add_theme_font_size_override("font_size", 22)
	_sel_box.add_child(_sel_name)
	_sel_info = _muted(_sel_box, "")
	var stats := GridContainer.new()
	stats.columns = 3
	stats.add_theme_constant_override("h_separation", 6)
	_sel_box.add_child(stats)
	_wt = _spin(stats, "WT", 1, 6)
	_rng = _spin(stats, "RANGE", 0, 12)
	_hp = _spin(stats, "HP", 0, 40)
	_wt.value_changed.connect(_on_spin.bind(wt_changed))
	_rng.value_changed.connect(_on_spin.bind(range_changed))
	_hp.value_changed.connect(_on_spin.bind(hp_changed))
	var sel_row := _row(_sel_box)
	_open_btn = _button(sel_row, "Open")
	_open_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open_btn.tooltip_text = "O"
	_open_btn.pressed.connect(func() -> void: open_pressed.emit())
	var rm := _button(sel_row, "Remove")
	rm.tooltip_text = "Delete"
	rm.pressed.connect(func() -> void: remove_pressed.emit())

	_header(col, "TERRAIN (7 HEXES)")
	var names: Array[String] = ["Ice", "Mud", "Clear", "Ramp", "Wind"]
	var types: Array[int] = [Terrain.Type.ICE, Terrain.Type.MUD, Terrain.Type.NONE, Terrain.Type.RAMP, Terrain.Type.WIND]
	var ter_row := _row(col)
	for i: int in names.size():
		if i == 3:
			ter_row = _row(col)
		var b := _button(ter_row, names[i])
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t: int = types[i]
		b.toggled.connect(func(on: bool) -> void: _on_terrain_toggled(b, t, on))
		_terrain_btns.append(b)
	# Wind direction for the next Wind patch, as seen from the default camera.
	var dir_btn := _button(ter_row, WIND_ARROWS[_wind_dir])
	dir_btn.tooltip_text = "Wind direction (click to turn)"
	dir_btn.pressed.connect(func() -> void:
		_wind_dir = (_wind_dir + 1) % 6
		dir_btn.text = WIND_ARROWS[_wind_dir])

	_header(col, "VIEW")
	var path := CheckBox.new()
	path.text = "Show last throw path"
	path.button_pressed = true
	path.toggled.connect(func(on: bool) -> void: show_path_toggled.emit(on))
	col.add_child(path)
	var auto := CheckBox.new()
	auto.text = "Open when a ball stops"
	auto.button_pressed = true
	auto.toggled.connect(func(on: bool) -> void: auto_open_toggled.emit(on))
	col.add_child(auto)

	_header(col, "LAST THROW")
	_last_big = Label.new()
	_last_big.theme_type_variation = &"Big"
	_last_big.text = "–"
	col.add_child(_last_big)
	_last_info = _muted(col, "Distance is start hex to end hex.")
	_last_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	show_selection(null)


func set_heroes(list: Array[HeroDef], info: String) -> void:
	heroes = list
	_hero_pick.clear()
	for h: HeroDef in heroes:
		_hero_pick.add_item("%s  ·  WT%d  ·  %s" % [h.name, h.wt, h.color_name])
	if not heroes.is_empty():
		_hero_pick.select(0)
	_data_info.text = info


func selected_hero() -> HeroDef:
	var i: int = _hero_pick.selected
	return heroes[i] if i >= 0 and i < heroes.size() else null


func wind_dir() -> int:
	return _wind_dir


func selected_team() -> int:
	return 1 if _team_buttons[1].button_pressed else 0


func set_spawn_active(on: bool) -> void:
	_spawn_btn.set_pressed_no_signal(on)


func clear_terrain_tool() -> void:
	for b: Button in _terrain_btns:
		b.set_pressed_no_signal(false)


func show_selection(piece: SandboxPiece) -> void:
	_sel_box.visible = piece != null
	_sel_empty.visible = piece == null
	if piece == null:
		return
	_quiet = true
	_sel_name.text = piece.label()
	_sel_name.add_theme_color_override("font_color", piece.hero.ball_color.lightened(0.2))
	_sel_info.text = "%s  ·  %s team  ·  card WT%d" % [piece.hero.id, Palette.TEAM_NAMES[piece.team], piece.hero.wt]
	_wt.value = piece.body.wt
	_rng.value = piece.rng
	_hp.value = piece.hp
	_quiet = false
	set_open_state(piece.view.is_open())


func set_open_state(open: bool) -> void:
	_open_btn.text = "Close" if open else "Open"


func set_last_throw(big: String, info: String) -> void:
	_last_big.text = big
	_last_info.text = info


func _on_spin(v: float, sig: Signal) -> void:
	if not _quiet:
		sig.emit(int(v))


func _on_terrain_toggled(b: Button, t: int, on: bool) -> void:
	if on:
		for other: Button in _terrain_btns:
			if other != b:
				other.set_pressed_no_signal(false)
		terrain_tool_selected.emit(t)
	else:
		terrain_tool_selected.emit(-1)


func _header(parent: Control, text: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	parent.add_child(gap)
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Header"
	parent.add_child(l)


func _muted(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Muted"
	parent.add_child(l)
	return l


func _row(parent: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	parent.add_child(r)
	return r


func _button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b


func _spin(parent: Control, label: String, lo: int, hi: int) -> SpinBox:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var l := Label.new()
	l.text = label
	l.theme_type_variation = &"Header"
	box.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.rounded = true
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(s)
	return s
