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
	25: ["HUGE", "More room: heroes take a turn or two longer to meet."],
	27: ["GIANT", "The widest table: long throws, slow to close in."],
	MatchSettings.MAP_RANDOM: ["ANY", "Drawn when the match starts. Chaos plays this way."],
}
## The rules shown big at the top of MATCH RULES (Marko 2026-11-11, M1): the ones a Standard match really changes.
const MAIN_RULES: Array[String] = ["stage_claim", "stage_goal", "stages_to_win", "timer_seconds"]
## Rules of the modes not offered now (MatchSettings.LOCKED_MODES): shown only when changed (a remembered custom).
const HIDDEN_RULES: Array[String] = ["series_wins", "deck_size"]
## A shorter line for the hovered rule where the full one is too long for the foot.
const SHORT_WHAT: Dictionary[String, String] = {
	"stage_claim": "How a stage is claimed. Shared ring: one ring of places for both sides; your energy fills it, then takes the other side's. Separate: each side fills its own. Stay: the first rule (two Stays in a row, two heroes, or the battle there).",
}
## The panel: columns of [section, rows]; a row is [setting, name, what it does, the values offered].
const COLUMNS: Array = [
	[
		["HEROES", [
			["range_delta", "Hero range", "Added to every hero's printed range. Lowered, it never drops below 2.", [-2, -1, 0, 1, 2]],
			["core_slots", "Cores per hero", "How many cores one hero can hold; 0 plays without cores.", [0, 1, 2, 3, 4, 5]],
			["equipment_limit", "Equipment per hero", "How many equipment cards one hero can wear.", [1, 2, 3, 4, 5]],
		]],
		["BATTLE", [
				["max_tie_turns", "Tied battles", "Turns a tied battle may repeat before both heroes are knocked back.", [1, 2, 3, 4]],
		]],
		["TIME", [
			["timer_seconds", "Move timer", "Seconds for each move. When it runs out the game makes the safe move: pass, keep, stay, a missed roll.", [0, 15, 20, 30, 45, 60, 90]],
		]],
		["SERIES", [
			["series_wins", "Series", "Wins that take the match. The loser starts the next game; stages and cores are picked again, the decks stay.", [1, 2, 3]],
		]],
	],
	[
		["STAGES & CORES", [
			["manual_setup", "Placement", "Who puts the stages and cores on the map before the first turn.", [true, false]],
			["stages_to_win", "Stages to win", "Stages a player must hold at once to win.", [2, 3, 4]],
			["stage_claim", "Stage claims", "Shared ring: each stage has one ring of places for both sides. The energy left at the end of the turn goes into the stage under your hero: it fills the empty places, then takes the other side's, and the whole ring claims the stage. Separate (the rule before 2026-11-10): each side fills its own and the first to the goal claims it. In both, the other side knocking your last hero off the stage costs you half your energy there. Stay (the first rule): two turns in a row on a stage, two heroes on it, or the battle there won.", [MatchSettings.CLAIM_RING, MatchSettings.CLAIM_ENERGY, MatchSettings.CLAIM_STAY]],
			["stage_goal", "Energy to claim", "The energy one stage needs: the places in its ring, or with Separate what each side must put in.", [8, 10, 12, 14, 16, 18, 20]],
		]],
		["CARDS & ENERGY", [
			["deck_size", "Deck", "Cards played from each deck: a smaller deck is drawn at random from the full one. 50 and 60 are for random and drafted decks; a saved deck plays its 40.", [20, 30, 40, 50, 60]],
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
var _map_question: Label
var _map_size: Label
var _map_word: Label
var _rules_tile: PanelContainer
var _rules_box: StyleBoxFlat
var _rules_chip: HBoxContainer
var _rules_line: Label
var _rules_changes: Label
var _rules_btn: Button
var _layer: CanvasLayer
var _rules_body: VBoxContainer
## MORE RULES is open (M1).
var _rules_more: bool = false
var _rules_foot: Label


func setup(s: MatchSettings, can_edit: bool) -> void:
	# Remembered rules of a mode that is not offered now go back to Standard.
	if can_edit and MatchSettings.LOCKED_MODES.has(s.mode):
		s = MatchSettings.preset("standard")
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
		"core_slots":
			return "NO CORES" if JsonUtil.as_int(v) <= 0 else str(JsonUtil.as_int(v))
		"manual_setup":
			return "BY THE PLAYERS" if JsonUtil.as_bool(v) else "AT RANDOM"
		"series_wins":
			var w: int = JsonUtil.as_int(v)
			return "ONE GAME" if w <= 1 else "BEST OF %d" % (w * 2 - 1)
		"timer_seconds":
			var t: int = JsonUtil.as_int(v)
			return "OFF" if t <= 0 else "%d S" % t
		"stage_claim":
			return "SEPARATE" if str(v) == MatchSettings.CLAIM_ENERGY else ("SHARED RING" if str(v) == MatchSettings.CLAIM_RING else "STAY")
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
	# Leaning like START MATCH beside them (Marko 2026-10-26), the content upright inside.
	_lean(_map_box)
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
	_map_question = UiTheme.label("?", 72, Palette.DIM)
	_map_question.custom_minimum_size = Vector2(112, 112)
	_map_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_question.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_map_question.visible = false
	mrow.add_child(_map_question)
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
	_lean(_rules_box)
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
	_rules_line = Label.new()
	_rules_line.add_theme_color_override("font_color", Palette.MUTED)
	_rules_line.add_theme_font_size_override("font_size", 14)
	_rules_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rcol.add_child(_rules_line)
	_rules_changes = Label.new()
	_rules_changes.add_theme_font_size_override("font_size", 14)
	_rules_changes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rcol.add_child(_rules_changes)


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
	var random_map: bool = n == MatchSettings.MAP_RANDOM
	_map_preview.visible = not random_map
	_map_question.visible = random_map
	if not random_map:
		_map_preview.map_size = n
	_map_size.text = "RANDOM" if random_map else "%d × %d" % [n, n]
	var info: Array = MAP_INFO[n] if MAP_INFO.has(n) else ["", ""]
	_map_word.text = ("DRAWN AT THE START" if random_map else str(info[0])) + ("  ·  STANDARD" if n == MatchSettings.standard().map_size else "")
	_map_tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if editable else Control.CURSOR_ARROW
	_map_tile.tooltip_text = "Pick the map" if editable else "The host picks the map"
	# The modes are picked right here (playtest 2026-10-30: they were inside MATCH RULES); the
	# rules themselves sit behind a quiet button and only say something when they differ.
	for c: Node in _rules_chip.get_children():
		c.queue_free()
	_rules_chip.add_child(UiTheme.label("MODE", 15, Palette.GOLD))
	var diff: PackedStringArray = changes()
	for name: String in MatchSettings.MODES:
		if name == "custom":
			continue
		var b := Button.new()
		b.text = name.to_upper()
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 17)
		b.theme_type_variation = &"Gold" if name == settings.mode else &""
		var locked: bool = MatchSettings.LOCKED_MODES.has(name)
		b.disabled = not editable or locked
		b.tooltip_text = MatchSettings.LOCKED_LINE if locked else str(MatchSettings.MODE_LINES.get(name, ""))
		if locked:
			b.modulate = Color(1, 1, 1, 0.45)
			b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.pressed.connect(func() -> void:
			settings = MatchSettings.preset(name)
			_changed())
		_rules_chip.add_child(b)
	if settings.mode == "custom":
		_rules_chip.add_child(UiShape.chip("CUSTOM · %d" % diff.size(), Palette.ACCENT, Palette.FG, 13, 22.0, 10.0))
	# RULES at the end of the mode row, level with the mode buttons.
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rules_chip.add_child(gap)
	_rules_btn = Button.new()
	_rules_btn.theme_type_variation = &"Ghost"
	_rules_btn.focus_mode = Control.FOCUS_NONE
	_rules_btn.add_theme_font_size_override("font_size", 15)
	_rules_btn.pressed.connect(open_rules)
	_rules_chip.add_child(_rules_btn)
	_rules_line.text = str(MatchSettings.MODE_LINES.get(settings.mode, ""))
	# A mode says what it is in its line; only a custom mix lists what it changed.
	var custom: bool = settings.mode == "custom" and not diff.is_empty()
	_rules_changes.text = ("Changed: " + ", ".join(diff)) if custom else ""
	_rules_changes.visible = custom
	_rules_changes.add_theme_color_override("font_color", Palette.GOLD)
	_rules_btn.text = ("RULES ›" if editable else "SEE RULES ›")
	if _rules_body != null and is_instance_valid(_rules_body):
		_fill_rules()


func _changed() -> void:
	settings.mode = settings.mode_of()
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
	# Five maps and Random: three a row (playtest 2026-10-30 added 25 and 27).
	var row := GridContainer.new()
	row.columns = 3
	row.add_theme_constant_override("h_separation", 18)
	row.add_theme_constant_override("v_separation", 18)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(row)
	for n: int in GameSettings.MAP_SIZES:
		row.add_child(_map_choice(n))
	row.add_child(_map_choice(MatchSettings.MAP_RANDOM))


func _map_choice(n: int) -> Control:
	var picked: bool = n == settings.map_size
	var tile := PanelContainer.new()
	var sb: StyleBoxFlat = UiTheme.box(Palette.SURFACE_2, 0, Color(0, 0, 0, 0), 16, 16)
	sb.set_border_width_all(3)
	sb.border_color = Palette.ACCENT if picked else Color(0, 0, 0, 0)
	tile.add_theme_stylebox_override("panel", sb)
	tile.custom_minimum_size = Vector2(300, 0)
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(col)
	if n == MatchSettings.MAP_RANDOM:
		var q: Label = UiTheme.label("?", 160, Palette.DIM)
		q.custom_minimum_size = Vector2(220, 220)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		col.add_child(q)
	else:
		var pic := MapPreview.new()
		pic.map_size = n
		pic.custom_minimum_size = Vector2(220, 220)
		col.add_child(pic)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_row)
	name_row.add_child(UiTheme.label("RANDOM" if n == MatchSettings.MAP_RANDOM else "%d × %d" % [n, n], 36))
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
		"Standard, or change what you like. Straw values differ from Standard." if editable else "The host sets these. Straw values differ from Standard.", 1020.0)
	# The rules scroll when the screen is too short for them (Marko 2026-11-02: cut off below).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	_rules_body = VBoxContainer.new()
	_rules_body.add_theme_constant_override("separation", 12)
	_rules_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_rules_body)
	var fit := func() -> void:
		var room: float = get_viewport().get_visible_rect().size.y - 300.0
		scroll.custom_minimum_size.y = minf(_rules_body.get_combined_minimum_size().y, maxf(room, 200.0))
	_rules_body.minimum_size_changed.connect(fit)
	fit.call_deferred()
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	# What the hovered rule does, in one place (M1); else how far the rules are from Standard.
	_rules_foot = Label.new()
	_rules_foot.add_theme_font_size_override("font_size", 15)
	_rules_foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules_foot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rules_foot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rules_foot.custom_minimum_size = Vector2(0, 44)
	foot.add_child(_rules_foot)
	if editable:
		var reset := Button.new()
		reset.text = "BACK TO STANDARD"
		reset.theme_type_variation = &"Ghost"
		reset.add_theme_font_size_override("font_size", 16)
		reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		reset.pressed.connect(func() -> void:
			var map: int = settings.map_size
			settings = MatchSettings.preset("standard")
			settings.map_size = map
			_changed())
		foot.add_child(reset)
	var done := Button.new()
	done.text = "DONE" if editable else "CLOSE"
	done.theme_type_variation = &"Primary"
	done.add_theme_font_size_override("font_size", 24)
	done.custom_minimum_size = Vector2(160, 0)
	done.pressed.connect(_close)
	foot.add_child(done)
	_fill_rules()


## The rules as chosen (Marko 2026-11-11, M1): the four a Standard match really changes as big tiles, the rest
## folded under MORE RULES, and what a rule does only for the hovered one, at the bottom.
func _fill_rules() -> void:
	for c: Node in _rules_body.get_children():
		c.queue_free()
	var rows: Dictionary = _rules_by_key()
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	_rules_body.add_child(grid)
	for key: String in MAIN_RULES:
		grid.add_child(_rule_tile(key, JsonUtil.as_array(rows[key])))
	var rest: Array[String] = []
	var rest_changed: int = 0
	for key: String in rows:
		if MAIN_RULES.has(key) or (HIDDEN_RULES.has(key) and settings.get(key) == standard_value(key)):
			continue
		rest.append(key)
		if settings.get(key) != standard_value(key):
			rest_changed += 1
	var more := Button.new()
	more.text = ("MORE RULES  ▴" if _rules_more else "MORE RULES  ▾  ·  %d more" % rest.size()) \
		+ ("  ·  %d changed" % rest_changed if rest_changed > 0 else "")
	more.theme_type_variation = &"Ghost"
	more.add_theme_font_size_override("font_size", 18)
	more.alignment = HORIZONTAL_ALIGNMENT_LEFT
	more.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	if rest_changed > 0:
		more.add_theme_color_override("font_color", Palette.GOLD)
	more.pressed.connect(func() -> void:
		_rules_more = not _rules_more
		_fill_rules())
	_rules_body.add_child(more)
	if _rules_more:
		var small := GridContainer.new()
		small.columns = 2
		small.add_theme_constant_override("h_separation", 40)
		small.add_theme_constant_override("v_separation", 4)
		_rules_body.add_child(small)
		for key: String in rest:
			small.add_child(_rule_line(key, JsonUtil.as_array(rows[key])))
	_rules_summary()


## The foot's line when no rule is hovered: Standard, or how many rules differ from it.
func _rules_summary() -> void:
	if _rules_foot == null or not is_instance_valid(_rules_foot):
		return
	var diff: PackedStringArray = changes()
	_rules_foot.text = "STANDARD  ·  hover a rule to read what it does" if diff.is_empty() \
		else "%d CHANGED FROM STANDARD  ·  %s" % [diff.size(), ", ".join(diff)]
	_rules_foot.add_theme_color_override("font_color", Palette.MUTED if diff.is_empty() else Palette.GOLD)


## Every rule of COLUMNS by its setting: [setting, name, what it does, values].
static func _rules_by_key() -> Dictionary:
	var out: Dictionary = {}
	for column: Array in COLUMNS:
		for section: Array in column:
			for row: Array in section[1]:
				out[str(row[0])] = row
	return out


## A big tile: the rule's name over its value, the arrows either side.
func _rule_tile(key: String, r: Array) -> Control:
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.04), 0, Color(0, 0, 0, 0), 18, 14))
	tile.custom_minimum_size = Vector2(470, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	tile.add_child(v)
	v.add_child(UiTheme.label(str(r[1]).to_upper(), 22))
	v.add_child(_rule_value(key, r, 30, 300.0))
	_rule_hover(tile, key, r)
	return tile


## A small line: the name, then the value with its arrows.
func _rule_line(key: String, r: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_l: Label = UiTheme.label(str(r[1]).to_upper(), 18)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_l)
	row.add_child(_rule_value(key, r, 20, 170.0 if key == "manual_setup" else 110.0))
	_rule_hover(row, key, r)
	return row


func _rule_value(key: String, r: Array, size: int, width: float) -> HBoxContainer:
	var values: Array = r[3]
	var now: Variant = settings.get(key)
	var std: Variant = standard_value(key)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var step := func(d: int) -> void:
		var i: int = values.find(settings.get(key))
		settings.set(key, values[posmod((i if i >= 0 else 0) + d, values.size())])
		_changed()
	if editable:
		h.add_child(_arrow("‹", func() -> void: step.call(-1)))
	var val: Label = UiTheme.label(value_text(key, now), size, Palette.GOLD if now != std else Palette.FG)
	val.custom_minimum_size = Vector2(width, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	val.tooltip_text = "Standard: " + value_text(key, std).to_lower()
	val.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(val)
	if editable:
		h.add_child(_arrow("›", func() -> void: step.call(1)))
	return h


func _rule_hover(c: Control, key: String, r: Array) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.mouse_entered.connect(func() -> void:
		if _rules_foot != null and is_instance_valid(_rules_foot):
			_rules_foot.text = str(SHORT_WHAT.get(key, r[2]))
			_rules_foot.add_theme_color_override("font_color", Palette.FG))
	c.mouse_exited.connect(_rules_summary)


func _arrow(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(44, 0)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(on_press)
	return b


## A tile box leaning like the slanted buttons, with room so the content clears the slant.
static func _lean(sb: StyleBoxFlat) -> void:
	sb.skew = Vector2(UiTheme.SKEW, 0)
	sb.anti_aliasing = true
	sb.content_margin_left += 22
	sb.content_margin_right += 22
