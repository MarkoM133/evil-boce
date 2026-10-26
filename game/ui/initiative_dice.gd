class_name InitiativeDice
extends Control
## Who starts (GDD 7, Marko 2026-10-26): before setup each player rolls two dice on screen and
## the higher total goes first. The engine has already drawn the initiative; the dice only show
## it: the values come from the match seed, so a host and its guests see the same roll, and
## the player the engine picked always has the higher total. A click skips it.

signal finished

const ROLL_TIME: float = 1.3
const HOLD_TIME: float = 1.4
const DIE := Vector2(64, 64)

## Per slot: its two dice labels and its total.
var _die_labels: Array[Label] = []
var _sum_labels: Array[Label] = []
var _final: Array[PackedInt32Array] = []
var _rolling: float = 0.0
var _flicker: float = 0.0
var _done: bool = false
var _rng := RandomNumberGenerator.new()
var _result: Label
var _rows: Array[HBoxContainer] = []
var _winner: int = 0
var _names: PackedStringArray = PackedStringArray()


## Two dice per player (2 players), the initiative player's total higher, from `seed`.
static func values(seed: int, initiative: int) -> Array[PackedInt32Array]:
	var r := RandomNumberGenerator.new()
	r.seed = seed * 7919 + 17
	for _try: int in 100:
		var a := PackedInt32Array([r.randi_range(1, 6), r.randi_range(1, 6)])
		var b := PackedInt32Array([r.randi_range(1, 6), r.randi_range(1, 6)])
		var sa: int = a[0] + a[1]
		var sb: int = b[0] + b[1]
		if sa == sb:
			continue
		var high: PackedInt32Array = a if sa > sb else b
		var low: PackedInt32Array = b if sa > sb else a
		var out: Array[PackedInt32Array] = []
		out.append(high if initiative == 0 else low)
		out.append(low if initiative == 0 else high)
		return out
	var fallback: Array[PackedInt32Array] = []
	fallback.append(PackedInt32Array([6, 5]))
	fallback.append(PackedInt32Array([1, 2]))
	if initiative != 0:
		fallback.reverse()
	return fallback


func setup(seed: int, initiative: int, names: PackedStringArray, colors: Array[Color]) -> void:
	_final = values(seed, initiative)
	_winner = initiative
	_names = names
	_rng.seed = seed
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)
	var title: Label = UiTheme.label("WHO STARTS?", 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 10)
	col.add_child(title)
	for slot: int in 2:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 14)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(row)
		var chip: UiShape = UiShape.chip(names[slot].to_upper() if slot < names.size() else "PLAYER %d" % (slot + 1),
			colors[slot] if slot < colors.size() else Palette.team(slot), Palette.FG, 24, 40.0, 18.0)
		chip.custom_minimum_size.x = maxf(chip.custom_minimum_size.x, 260.0)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
		for _d: int in 2:
			var box := PanelContainer.new()
			box.custom_minimum_size = DIE
			var sb: StyleBoxFlat = UiTheme.box(Color("f3efe7"), 12, Color(0, 0, 0, 0), 0, 0)
			box.add_theme_stylebox_override("panel", sb)
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var n: Label = UiTheme.label("?", 40, Color("141414"))
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			box.add_child(n)
			row.add_child(box)
			_die_labels.append(n)
		var sum: Label = UiTheme.label("", 34, Palette.GOLD)
		sum.custom_minimum_size = Vector2(70, 0)
		sum.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sum)
		_sum_labels.append(sum)
		_rows.append(row)
	_result = UiTheme.label("", 30, Palette.GOLD)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_result)
	_rolling = ROLL_TIME * GameSettings.anim_scale()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func _process(delta: float) -> void:
	if _done:
		return
	if _rolling > 0.0:
		_rolling -= delta
		_flicker -= delta
		if _flicker <= 0.0:
			_flicker = 0.07
			for l: Label in _die_labels:
				l.text = str(_rng.randi_range(1, 6))
		if _rolling <= 0.0:
			_settle()


func _settle() -> void:
	for slot: int in 2:
		var v: PackedInt32Array = _final[slot]
		_die_labels[slot * 2].text = str(v[0])
		_die_labels[slot * 2 + 1].text = str(v[1])
		_sum_labels[slot].text = "= %d" % (v[0] + v[1])
		if slot != _winner:
			_rows[slot].modulate = Color(1, 1, 1, 0.45)
	var who: String = _names[_winner] if _winner < _names.size() else "Player %d" % (_winner + 1)
	_result.text = "%s STARTS" % who.to_upper()
	get_tree().create_timer(HOLD_TIME * GameSettings.anim_scale()).timeout.connect(_close)


func _close() -> void:
	if _done:
		return
	_done = true
	var t: Tween = create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.2)
	t.tween_callback(func() -> void:
		finished.emit()
		queue_free())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if _rolling > 0.0:
			_rolling = 0.0
			_settle()
		else:
			_close()
