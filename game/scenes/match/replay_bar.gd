class_name ReplayBar
extends PanelContainer
## Controls for watching a recorded match (GDD 2): step through phases, play / pause, speed,
## continue from the shown phase, leave.

signal step_pressed(delta: int)
signal jump_pressed(to_end: bool)
signal play_toggled
signal speed_changed(speed: float)
signal continue_pressed
signal exit_pressed

const SPEEDS: Array[float] = [1.0, 2.0, 4.0]

var _label: Label
var _play: Button
var _speed: Button
var _continue: Button
var _speed_i: int = 0


func _init() -> void:
	# Centred at the bottom of the screen, 860 px wide.
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -430
	offset_right = 430
	offset_top = -78
	offset_bottom = -18
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	_button(row, "⏮", "First phase", func() -> void: jump_pressed.emit(false))
	_button(row, "◀", "Previous phase (Left)", func() -> void: step_pressed.emit(-1))
	_play = _button(row, "▶", "Play / pause (Space)", func() -> void: play_toggled.emit())
	_button(row, "▶▶", "Next phase (Right)", func() -> void: step_pressed.emit(1))
	_button(row, "⏭", "Last phase", func() -> void: jump_pressed.emit(true))
	_speed = _button(row, "1×", "Speed", _next_speed)
	_label = Label.new()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", UiTheme.display_bold())
	_label.add_theme_font_size_override("font_size", 18)
	row.add_child(_label)
	_continue = _button(row, "Continue from here", "Start a new match from this phase (the replay stays as it is)",
		func() -> void: continue_pressed.emit())
	_button(row, "Exit", "Back to the replay list", func() -> void: exit_pressed.emit())


func show_frame(index: int, count: int, turn: int, phase: String) -> void:
	var where: String = "SETUP" if turn == 0 else "TURN %d" % turn
	_label.text = "%s  ·  %s   (%d / %d)" % [where, phase.to_upper(), index + 1, count]


func set_playing(on: bool) -> void:
	_play.text = "❚❚" if on else "▶"


func _next_speed() -> void:
	_speed_i = (_speed_i + 1) % SPEEDS.size()
	_speed.text = "%d×" % int(SPEEDS[_speed_i])
	speed_changed.emit(SPEEDS[_speed_i])


func _button(parent: Control, text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## Without "Continue from here" (a replay the host watches with its table: "continue online"
## is not there yet, and a local match would leave the table waiting).
func hide_continue() -> void:
	_continue.visible = false
