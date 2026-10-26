class_name MatchRules
extends HBoxContainer
## The match rules before a match (Play setup and the online lobby) in one bar: the map as a
## tile with a drawing of the board, which opens a picker with the maps, and a MATCH RULES card
## with a summary, which opens a panel with every rule a match can change. The local player or
## the host edits (`editable`); an online guest only looks. Edits `settings` in place and says
## `changed`.

signal changed

## Map size -> [size word, one line about it].
const MAP_INFO: Dictionary[int, Array] = {
	15: ["SMALL", "Heroes meet fast. Short, rough matches."],
	17: ["MEDIUM", "A step between the two."],
	23: ["LARGE", "Room to move and to place stages. The Standard map."],
}
## The panel: columns of [section, rows]; a row is [setting, name, what it does, the values offered].
const COLUMNS: Array = [
	[
		["HEROES", [
			["range_delta", "Hero range", "Added to every hero's printed range. Lowered, it never drops below 2.", [-2, -1, 0, 1]],
			["core_slots", "Cores per hero", "How many cores one hero can hold.", [1, 2, 3, 4]],
			["equipment_limit", "Equipment per hero", "How many equipment cards one hero can wear.", [1, 2, 3, 4, 5]],
			["wall_damage", "Wall damage", "Damage for every knockback step a wall or another hero blocks.", [0, 1, 2, 3, 4]],
		]],
		["BATTLE", [
				["max_tie_turns", "Tied battles", "Turns a tied battle may repeat before both heroes are knocked back.", [1, 2, 3, 4]],
		]],
		["TIME", [
			["timer_seconds", "Move timer", "Seconds for each move. When it runs out the game makes the safe move: pass, keep, stay, a missed roll.", [0, 15, 20, 30, 45, 60, 90]],
		]],
	],
	[
		["STAGES & CORES", [
			["manual_setup", "Placement", "Who puts the stages and cores on the map before the first turn.", [true, false]],
			["stages_to_win", "Stages to win", "Stages a player must hold at once to win.", [2, 3, 4]],
		]],
		["CARDS & ENERGY", [
			["deck_size", "Deck", "Cards played from each deck: a smaller deck is drawn at random from the full one.", [20, 25, 30, 40]],
			["start_hand", "Starting hand", "Cards drawn at the start, and again after a mulligan.", [3, 4, 5, 6, 7]],
			["max_energy", "Most energy", "Energy grows by one each turn up to this.", [5, 6, 7, 8, 9, 10, 12]],
			["assist_limit", "Assists", "How many assists one player can have out.", [1, 2, 3, 4, 5]],
		]],
	],
]

var settings: MatchSettings = MatchSettings.standard()
var editable: bool = true

var _map_tile: PanelContainer
var _map_box: StyleBoxFlat
var _map_preview: MapPreview
var _map_size: Label
var _map_word: Label
var _rules_tile: PanelContainer
var _rules_box: StyleBoxFlat
var _rules_chip: HBoxContainer
var _rules_line: Label
var _rules_changes: Label
var _rules_btn: Button
var _layer: CanvasLayer
var _rules_body: HBoxContainer
var _rules_foot: Label


func setup(s: MatchSettings, can_edit: bool) -> void:
	settings = s
	editable = can_edit
	if _map_tile == null:
		_build()
	_refresh()


## New settings from outside (a guest hears the host's).
func set_settings(s: MatchSettings) -> void:
	settings = s
	_refresh()


func set_editable(on: bool) -> void:
	editable = on
	_refresh()


static func standard_value(key: String) -> Variant:
	return MatchSettings.standard().get(key)


static func value_text(key: String, v: Variant) -> String:
	match key:
		"range_delta":
			var d: int = JsonUtil.as_int(v)
			return "AS PRINTED" if d == 0 else "%+d" % d
		"manual_setup":
			return "BY THE PLAYERS" if JsonUtil.as_bool(v) else "AT RANDOM"
		"timer_seconds":
			var t: int = JsonUtil.as_int(v)
			return "OFF" if t <= 0 else "%d S" % t
	return str(v)


## Rules (not the map) that differ from Standard, as "Name value".
func changes() -> PackedStringArray:
	var out := PackedStringArray()
	for column: Array in COLUMNS:
		for section: Array in column:
			for row: Array in section[1]:
				var key: String = row[0]
				if settings.get(key) != standard_value(key):
					out.append("%s %s" % [str(row[1]), value_text(key, settings.get(key)).to_lower()])
	return out


func _build() -> void:
	add_theme_constant_override("separation", 14)
	# The map.
	_map_tile = PanelContainer.new()
	_map_box = UiTheme.box(Palette.PANEL_SOLID, 0, Color(0, 0, 0, 0), 16, 12)
	_map_box.set_border_width_all(2)
	_map_box.border_color = Color(0, 0, 0, 0)
	_map_tile.add_theme_stylebox_override("panel", _map_box)
	_map_tile.custom_minimum_size = Vector2(330, 0)
	add_child(_map_tile)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 14)
	mrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_tile.add_child(mrow)
	_map_preview = MapPreview.new()
	_map_preview.custom_minimum_size = Vector2(112, 112)
	mrow.add_child(_map_preview)
	var mcol := VBoxContainer.new()
	mcol.alignment = BoxContainer.ALIGNMENT_CENTER
	mcol.add_theme_constant_override("separation", 0)
	mcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mrow.add_child(mcol)
	mcol.add_child(UiTheme.label("MAP", 13, Palette.GOLD))
	_map_size = UiTheme.label("", 34)
	mcol.add_child(_map_size)
	_map_word = UiTheme.label("", 14, Palette.MUTED)
	mcol.add_child(_map_word)
	_hover(_map_tile, _map_box, func() -> bool: return editable, open_map_picker)

	# The rules.
	_rules_tile = PanelContainer.new()
	_rules_box = UiTheme.box(Palette.PANEL_SOLID, 0, Color(0, 0, 0, 0), 18, 12)
	_rules_box.set_border_width_all(2)
	_rules_box.border_color = Color(0, 0, 0, 0)
	_rules_tile.add_theme_stylebox_override("panel", _rules_box)
	_rules_tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_rules_tile)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 14)
	rrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rules_tile.add_child(rrow)
	var rcol := VBoxContainer.new()
	rcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rcol.alignment = BoxContainer.ALIGNMENT_CENTER
	rcol.add_theme_constant_override("separation", 4)
	rcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rrow.add_child(rcol)
	_rules_chip = HBoxContainer.new()
	_rules_chip.add_theme_constant_override("separation", 10)
	_rules_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rcol.add_child(_rules_chip)
	_rules_line = UiTheme.label("", 18)
	_rules_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rcol.add_child(_rules_line)
	_rules_changes = Label.new()
	_rules_changes.add_theme_font_size_override("font_size", 14)
	_rules_changes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rcol.add_child(_rules_changes)
	_rules_btn = Button.new()
	_rules_btn.add_theme_font_size_override("font_size", 20)
	_rules_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rules_btn.pressed.connect(open_rules)
	rrow.add_child(_rules_btn)
	_hover(_rules_tile, _rules_box, func() -> bool: return true, open_rules)


## A tile that lights up on hover and calls `on_click` when clicked, while `active` says so.
func _hover(tile: Control, box: StyleBoxFlat, active: Callable, on_click: Callable) -> void:
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.mouse_entered.connect(func() -> void:
		if JsonUtil.as_bool(active.call()):
			box.border_color = Palette.GOLD
			tile.queue_redraw())
	tile.mouse_exited.connect(func() -> void:
		box.border_color = Color(0, 0, 0, 0)
		tile.queue_redraw())
	tile.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and JsonUtil.as_bool(active.call()):
			on_click.call())


func _refresh() -> void:
	if _map_tile == null:
		return
	var n: int = settings.map_size
	_map_preview.map_size = n
	_map_size.text = "%d × %d" % [n, n]
	var info: Array = MAP_INFO[n] if MAP_INFO.has(n) else ["", ""]
	_map_word.text = str(info[0]) + ("  ·  STANDARD" if n == MatchSettings.standard().map_size else "")
	_map_tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if editable else Control.CURSOR_ARROW
	_map_tile.tooltip_text = "Pick the map" if editable else "The host picks the map"
	_rules_tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	for c: Node in _rules_chip.get_children():
		c.queue_free()
	_rules_chip.add_child(UiTheme.label("MATCH RULES", 15, Palette.GOLD))
	var diff: PackedStringArray = changes()
	_rules_chip.add_child(UiShape.chip("STANDARD" if diff.is_empty() else "CUSTOM · %d" % diff.size(),
		Palette.SURFACE_2 if diff.is_empty() else Palette.ACCENT, Palette.FG, 13, 22.0, 10.0))
	_rules_line.text = "Hero range %s  ·  stages and cores %s  ·  first to %d stages" % [
		value_text("range_delta", settings.range_delta).to_lower(),
		"placed by the players" if settings.manual_setup else "placed at random", settings.stages_to_win]
	_rules_changes.text = ("Changed: " + ", ".join(diff)) if not diff.is_empty() else "Everything as in Standard."
	_rules_changes.add_theme_color_override("font_color", Palette.GOLD if not diff.is_empty() else Palette.MUTED)
	_rules_btn.text = "CHANGE RULES" if editable else "SEE RULES"
	if _rules_body != null and is_instance_valid(_rules_body):
		_fill_rules()


func _changed() -> void:
	_refresh()
	changed.emit()


# --- the overlays -------------------------------------------------------------------------

## A dimmed screen with a panel in the middle; returns the panel's column. Esc, a click on the
## dim or ✕ closes it.
func _overlay(title: String, subtitle: String, width: float) -> VBoxContainer:
	_close()
	_layer = CanvasLayer.new()
	_layer.layer = 20
	add_child(_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	_layer.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_close())
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	var sb: StyleBoxFlat = UiTheme.box(Palette.PANEL_SOLID, 0, Color(0, 0, 0, 0), 30, 24)
	sb.border_color = Palette.ACCENT
	sb.border_width_top = 4
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(UiTheme.label(title.to_upper(), 44))
	var sub := Label.new()
	sub.text = subtitle
	sub.add_theme_color_override("font_color", Palette.MUTED)
	sub.add_theme_font_size_override("font_size", 15)
	titles.add_child(sub)
	var x := Button.new()
	x.text = "✕"
	x.tooltip_text = "Close (Esc)"
	x.add_theme_font_size_override("font_size", 22)
	x.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	x.pressed.connect(_close)
	head.add_child(x)
	root.modulate.a = 0.0
	root.create_tween().tween_property(root, "modulate:a", 1.0, 0.15)
	return col


func _close() -> void:
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	_rules_body = null
	_rules_foot = null


func is_open() -> bool:
	return _layer != null and is_instance_valid(_layer)


func _input(event: InputEvent) -> void:
	if is_open() and event is InputEventKey and (event as InputEventKey).pressed \
			and GameSettings.logical_key((event as InputEventKey).keycode) == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()


## The maps side by side, each drawn; a click picks it.
func open_map_picker() -> void:
	if not editable:
		return
	var col: VBoxContainer = _overlay("Map", "Heroes come in on the coloured rows; the stages go in the straw middle third.", 1100.0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	for n: int in GameSettings.MAP_SIZES:
		row.add_child(_map_choice(n))


func _map_choice(n: int) -> Control:
	var picked: bool = n == settings.map_size
	var tile := PanelContainer.new()
	var sb: StyleBoxFlat = UiTheme.box(Palette.SURFACE_2, 0, Color(0, 0, 0, 0), 16, 16)
	sb.set_border_width_all(3)
	sb.border_color = Palette.ACCENT if picked else Color(0, 0, 0, 0)
	tile.add_theme_stylebox_override("panel", sb)
	tile.custom_minimum_size = Vector2(330, 0)
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(col)
	var pic := MapPreview.new()
	pic.map_size = n
	pic.custom_minimum_size = Vector2(298, 298)
	col.add_child(pic)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_row)
	name_row.add_child(UiTheme.label("%d × %d" % [n, n], 36))
	var info: Array = MAP_INFO[n] if MAP_INFO.has(n) else ["", ""]
	var word: UiShape = UiShape.chip(str(info[0]), Palette.GOLD, Color.BLACK, 13, 22.0, 9.0)
	word.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(word)
	if picked:
		var now: UiShape = UiShape.chip("PICKED", Palette.ACCENT, Palette.FG, 13, 22.0, 9.0)
		now.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_row.add_child(now)
	var line := Label.new()
	line.text = str(info[1])
	line.add_theme_color_override("font_color", Palette.MUTED)
	line.add_theme_font_size_override("font_size", 14)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(0, 40)
	col.add_child(line)
	_hover(tile, sb, func() -> bool: return true, func() -> void:
		settings.map_size = n
		_close()
		_changed())
	# Hover leaves the picked one red.
	tile.mouse_exited.connect(func() -> void:
		sb.border_color = Palette.ACCENT if n == settings.map_size else Color(0, 0, 0, 0))
	return tile


## Every rule in two columns, each with ‹ value › (only the value for a guest).
func open_rules() -> void:
	var col: VBoxContainer = _overlay("Match rules",
		"Everything a match can change. Straw values differ from Standard." if editable else "The host sets these. Straw values differ from Standard.", 1180.0)
	_rules_body = HBoxContainer.new()
	_rules_body.add_theme_constant_override("separation", 40)
	col.add_child(_rules_body)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	_rules_foot = UiTheme.label("", 18, Palette.MUTED)
	_rules_foot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rules_foot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_rules_foot)
	if editable:
		var reset := Button.new()
		reset.text = "BACK TO STANDARD"
		reset.theme_type_variation = &"Ghost"
		reset.add_theme_font_size_override("font_size", 18)
		reset.tooltip_text = "Every rule as in Standard (the map stays)"
		reset.pressed.connect(func() -> void:
			var map: int = settings.map_size
			var std: MatchSettings = MatchSettings.standard()
			for column: Array in COLUMNS:
				for section: Array in column:
					for r: Array in section[1]:
						settings.set(str(r[0]), std.get(str(r[0])))
			settings.map_size = map
			_changed())
		foot.add_child(reset)
	var done := Button.new()
	done.text = "DONE" if editable else "CLOSE"
	done.theme_type_variation = &"Primary"
	done.add_theme_font_size_override("font_size", 24)
	done.custom_minimum_size = Vector2(180, 0)
	done.pressed.connect(_close)
	foot.add_child(done)
	_fill_rules()


func _fill_rules() -> void:
	for c: Node in _rules_body.get_children():
		c.queue_free()
	for column: Array in COLUMNS:
		var colv := VBoxContainer.new()
		colv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		colv.add_theme_constant_override("separation", 10)
		_rules_body.add_child(colv)
		for section: Array in column:
			var head: Label = UiTheme.label(str(section[0]), 15, Palette.GOLD)
			colv.add_child(head)
			for r: Array in section[1]:
				colv.add_child(_rule_row(r))
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 8)
			colv.add_child(gap)
	var diff: PackedStringArray = changes()
	_rules_foot.text = "STANDARD RULES" if diff.is_empty() else "CUSTOM  ·  %d CHANGED" % diff.size()
	_rules_foot.add_theme_color_override("font_color", Palette.MUTED if diff.is_empty() else Palette.GOLD)


func _rule_row(r: Array) -> Control:
	var key: String = r[0]
	var values: Array = r[3]
	var now: Variant = settings.get(key)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	row.add_child(texts)
	texts.add_child(UiTheme.label(str(r[1]).to_upper(), 20))
	var info := Label.new()
	info.text = str(r[2])
	info.add_theme_color_override("font_color", Palette.MUTED)
	info.add_theme_font_size_override("font_size", 13)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(info)
	var std: Variant = standard_value(key)
	var step := func(d: int) -> void:
		var i: int = values.find(settings.get(key))
		settings.set(key, values[posmod((i if i >= 0 else 0) + d, values.size())])
		_changed()
	if editable:
		row.add_child(_arrow("‹", func() -> void: step.call(-1)))
	var val: Label = UiTheme.label(value_text(key, now), 22, Palette.GOLD if now != std else Palette.FG)
	val.custom_minimum_size = Vector2(170 if key == "manual_setup" else 110, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	val.tooltip_text = "Standard: " + value_text(key, std).to_lower()
	val.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(val)
	if editable:
		row.add_child(_arrow("›", func() -> void: step.call(1)))
	return row


func _arrow(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(44, 0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(on_press)
	return b
