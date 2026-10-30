class_name InitiativeDice
extends Control
## Who starts (GDD 7, Marko 2026-10-26): before setup each player rolls two dice on screen and
## the higher total goes first. The engine has already drawn the initiative; the dice only show
## it: the values come from the match seed, so a host and its guests see the same roll, and
## the player the engine picked always has the higher total.
## The dice are two closed balls in the player's colour (playtest 2026-10-30: they fell by
## themselves): a local player throws them with ROLL or a click, they shake and open on a
## number. Bots and remote players throw right after; with no local player both go at once.

signal finished

const ROLL_TIME: float = 1.1
const HOLD_TIME: float = 1.6
const BALL := Vector2(72, 72)
## How long a bot or remote player waits after the local throw.
const OTHER_DELAY: float = 0.5
## Seconds before a local player's balls go by themselves.
const AUTO_THROW: float = 10.0

## Per slot: its two ball panels and labels, its total.
var _balls: Array[PanelContainer] = []
var _die_labels: Array[Label] = []
var _sum_labels: Array[Label] = []
var _roll_buttons: Array[Button] = []
var _final: Array[PackedInt32Array] = []
## Per slot: time left shaking (> 0), -1 not thrown yet, 0 settled.
var _rolling: Array[float] = [-1.0, -1.0]
var _flicker: float = 0.0
var _done: bool = false
var _rng := RandomNumberGenerator.new()
var _result: Label
var _rows: Array[HBoxContainer] = []
var _winner: int = 0
var _names: PackedStringArray = PackedStringArray()
var _colors: Array[Color] = []
var _local: PackedInt32Array = PackedInt32Array()


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


## `local`: the seats played on this computer by a person (they throw by hand).
func setup(seed: int, initiative: int, names: PackedStringArray, colors: Array[Color],
		local: PackedInt32Array = PackedInt32Array()) -> void:
	_final = values(seed, initiative)
	_winner = initiative
	_names = names
	_colors = colors
	_local = local
	_rng.seed = seed
	# It sits outside the HUD, so it brings the game's look itself (buttons).
	theme = UiTheme.get_theme()
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
			_color(slot), Palette.FG, 24, 40.0, 18.0)
		chip.custom_minimum_size.x = maxf(chip.custom_minimum_size.x, 260.0)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(chip)
		for _d: int in 2:
			var ball := PanelContainer.new()
			ball.custom_minimum_size = BALL
			ball.pivot_offset = BALL * 0.5
			ball.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ball.add_theme_stylebox_override("panel", _ball_box(slot, false))
			var n: Label = UiTheme.label("", 40, Color("141414"))
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			ball.add_child(n)
			row.add_child(ball)
			_balls.append(ball)
			_die_labels.append(n)
		var sum: Label = UiTheme.label("", 34, Palette.GOLD)
		sum.custom_minimum_size = Vector2(70, 0)
		sum.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sum)
		_sum_labels.append(sum)
		var roll := Button.new()
		roll.text = "ROLL"
		roll.theme_type_variation = &"Primary"
		roll.add_theme_font_size_override("font_size", 24)
		roll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		roll.visible = _local.has(slot)
		var s: int = slot
		roll.pressed.connect(func() -> void: _throw(s))
		row.add_child(roll)
		_roll_buttons.append(roll)
		_rows.append(row)
	_result = UiTheme.label("", 30, Palette.GOLD)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_result)
	if _local.is_empty():
		_result.text = ""
		_throw(0)
		_throw(1)
	else:
		_result.text = "Click ROLL to throw your boće"
		# Nobody waits for ever (a match with a move timer, a player away): they throw by themselves.
		get_tree().create_timer(AUTO_THROW).timeout.connect(func() -> void:
			for slot: int in _local:
				if slot < 2:
					_throw(slot))
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func _color(slot: int) -> Color:
	return _colors[slot] if slot < _colors.size() else Palette.team(slot)


## A ball: closed it is the player's colour with a dark seam; open it is the cream inside.
func _ball_box(slot: int, open: bool) -> StyleBoxFlat:
	var sb: StyleBoxFlat = UiTheme.box(Color("f3efe7") if open else _color(slot), int(BALL.x * 0.5), Color(0, 0, 0, 0), 0, 0)
	sb.set_border_width_all(4)
	sb.border_color = _color(slot) if open else Color(0.08, 0.08, 0.08)
	return sb


func _throw(slot: int) -> void:
	if _done or _rolling[slot] != -1.0:
		return
	_rolling[slot] = ROLL_TIME * GameSettings.anim_scale()
	_roll_buttons[slot].visible = false
	# Whoever is not at this computer throws right after.
	for other: int in 2:
		if other != slot and not _local.has(other) and _rolling[other] == -1.0:
			get_tree().create_timer(OTHER_DELAY * GameSettings.anim_scale()).timeout.connect(func() -> void: _throw(other))


func _process(delta: float) -> void:
	if _done:
		return
	_flicker -= delta
	var tick: bool = _flicker <= 0.0
	if tick:
		_flicker = 0.07
	for slot: int in 2:
		if _rolling[slot] <= 0.0:
			continue
		_rolling[slot] -= delta
		for d: int in 2:
			var ball: PanelContainer = _balls[slot * 2 + d]
			# Shaking in the hand before it opens.
			ball.rotation = sin(Time.get_ticks_msec() * 0.04 + d * 1.7) * 0.35
			if tick:
				_die_labels[slot * 2 + d].text = ""
		if _rolling[slot] <= 0.0:
			_open(slot)


## The balls stop and open on their numbers.
func _open(slot: int) -> void:
	_rolling[slot] = 0.0
	var v: PackedInt32Array = _final[slot]
	for d: int in 2:
		var ball: PanelContainer = _balls[slot * 2 + d]
		ball.rotation = 0.0
		ball.add_theme_stylebox_override("panel", _ball_box(slot, true))
		_die_labels[slot * 2 + d].text = str(v[d])
		ball.scale = Vector2(1.25, 1.25)
		ball.create_tween().tween_property(ball, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sum_labels[slot].text = "= %d" % (v[0] + v[1])
	if _rolling[0] == 0.0 and _rolling[1] == 0.0:
		_settle()


func _settle() -> void:
	_rows[1 - _winner].modulate = Color(1, 1, 1, 0.45)
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


## A click throws the next local player's balls; once all are open it closes.
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		return
	for slot: int in _local:
		if slot < 2 and _rolling[slot] == -1.0:
			_throw(slot)
			return
	if _rolling[0] == 0.0 and _rolling[1] == 0.0:
		_close()
