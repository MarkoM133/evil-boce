class_name InitiativeDice
extends Control
## Who starts (GDD 7, Marko 2026-10-26): before setup each player rolls two dice on screen and
## the higher total goes first. The engine has already drawn the initiative; the dice only show
## it: the values come from the match seed, so a host and its guests see the same roll, and
## the player the engine picked always has the higher total.
## The dice are two closed balls in the player's colour (playtest 2026-10-30: they fell by
## themselves): a local player throws them with ROLL or a click, they open and their numbers
## run like a slot machine, slower and slower, until they stop on the throw (Marko 2026-11-02).
## Bots and remote players throw right after; with no local player both go at once.

signal finished

const ROLL_TIME: float = 1.6
## Seconds between two numbers on a die: at the start of the run and just before it stops.
const SPIN_FAST: float = 0.045
const SPIN_SLOW: float = 0.26
const HOLD_TIME: float = 1.6
const BALL := Vector2(72, 72)
## How long a bot or remote player waits after the local throw.
const OTHER_DELAY: float = 0.5
## Seconds before a local player's balls go by themselves.
const AUTO_THROW: float = 10.0
const FOOT_H: float = 56.0

## Per slot: its two ball panels and labels, its total.
var _balls: Array[PanelContainer] = []
var _die_labels: Array[Label] = []
var _sum_labels: Array[Label] = []
## "Click [ROLL] to throw your boće": the button is in the sentence (Marko 2026-11-09), one for
## whoever throws next at this computer.
var _ask: HBoxContainer
var _final: Array[PackedInt32Array] = []
## Per slot: time left shaking (> 0), -1 not thrown yet, 0 settled.
var _rolling: Array[float] = [-1.0, -1.0]
## Per die: seconds until its number changes again.
var _spin_left: Array[float] = [0.0, 0.0, 0.0, 0.0]
## The running numbers only (the throw itself comes from the seed).
var _spin_rng := RandomNumberGenerator.new()
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
	_spin_rng.randomize()
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
		_rows.append(row)
	# The sentence and the result share one line's room, so nothing jumps when one replaces the other.
	var foot := Control.new()
	foot.custom_minimum_size = Vector2(0, FOOT_H)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(foot)
	_result = UiTheme.label("", 30, Palette.GOLD)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	foot.add_child(_result)
	_ask = HBoxContainer.new()
	_ask.alignment = BoxContainer.ALIGNMENT_CENTER
	_ask.add_theme_constant_override("separation", 14)
	_ask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ask.visible = false
	foot.add_child(_ask)
	_ask.add_child(UiTheme.label("Click", 30, Palette.GOLD))
	var roll := Button.new()
	roll.text = "ROLL"
	roll.theme_type_variation = &"Primary"
	roll.add_theme_font_size_override("font_size", 24)
	roll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	roll.focus_mode = Control.FOCUS_NONE
	roll.pressed.connect(_throw_next)
	_ask.add_child(roll)
	_ask.add_child(UiTheme.label("to throw your boće", 30, Palette.GOLD))
	if _local.is_empty():
		_throw(0)
		_throw(1)
	else:
		_ask.visible = true
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
	_ask.visible = _next_local() >= 0
	# Open at once: the numbers run inside.
	for d: int in 2:
		_balls[slot * 2 + d].add_theme_stylebox_override("panel", _ball_box(slot, true))
		_die_labels[slot * 2 + d].text = str(_spin_rng.randi_range(1, 6))
		# The second die runs a little longer than the first.
		_spin_left[slot * 2 + d] = SPIN_FAST * (1 + d)
	# Whoever is not at this computer throws right after.
	for other: int in 2:
		if other != slot and not _local.has(other) and _rolling[other] == -1.0:
			get_tree().create_timer(OTHER_DELAY * GameSettings.anim_scale()).timeout.connect(func() -> void: _throw(other))


## The next seat at this computer that has not thrown yet, or -1.
func _next_local() -> int:
	for slot: int in _local:
		if slot < 2 and _rolling[slot] == -1.0:
			return slot
	return -1


func _throw_next() -> void:
	var slot: int = _next_local()
	if slot >= 0:
		_throw(slot)


func _process(delta: float) -> void:
	if _done:
		return
	for slot: int in 2:
		if _rolling[slot] <= 0.0:
			continue
		_rolling[slot] -= delta
		var total: float = maxf(ROLL_TIME * GameSettings.anim_scale(), 0.01)
		var k: float = clampf(1.0 - _rolling[slot] / total, 0.0, 1.0)
		for d: int in 2:
			var i: int = slot * 2 + d
			var ball: PanelContainer = _balls[i]
			# A wobble that dies down as the numbers slow.
			ball.rotation = sin(Time.get_ticks_msec() * 0.04 + d * 1.7) * 0.18 * (1.0 - k)
			_spin_left[i] -= delta
			if _spin_left[i] > 0.0:
				continue
			# Slower and slower, like a reel coming to rest.
			_spin_left[i] = lerpf(SPIN_FAST, SPIN_SLOW, k * k) * GameSettings.anim_scale()
			var label: Label = _die_labels[i]
			var n: int = _spin_rng.randi_range(1, 5)
			if n >= label.text.to_int():
				n += 1
			label.text = str(n)
			ball.scale = Vector2(1.08, 1.08)
			ball.create_tween().tween_property(ball, "scale", Vector2.ONE, 0.06)
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
	if _next_local() >= 0:
		_throw_next()
		return
	if _rolling[0] == 0.0 and _rolling[1] == 0.0:
		_close()
