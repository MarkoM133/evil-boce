class_name BattleTug
extends Control
## Who is ahead in a battle (Marko 2026-11-08, from the mockups): a slanted bar, the first team's
## colour against the second's, meeting where their Power splits, the totals at its ends (the side
## ahead in straw) and the difference by the meeting point, on the colour of the side behind.
## Level, the meeting point stands straight on the middle line with TIE on it. A change is animated:
## the bar slides, the totals count, the mark pops up.

## At its widest; `set_bar_width` narrows it to stand clear of the ability tabs (their width depends
## on the ability's name) beside the hero panels.
const WIDTH: float = 520.0
const MIN_WIDTH: float = 320.0
const HEIGHT: float = 34.0
const CUT: float = 12.0
const MOVE_TIME: float = 0.35
const POP_TIME: float = 0.25
## The bar never gets narrower than this for the side behind: its total and the mark must fit.
const MIN_SHARE: float = 0.3
## ... and never fewer pixels than this, on a narrowed bar.
const MIN_SIDE: float = 150.0
## From the meeting point to the mark, on either side.
const MARK_GAP_RIGHT: float = 8.0
const MARK_GAP_LEFT: float = 4.0
const MARK_FONT: int = 16
const MARK_H: float = 24.0
const MARK_CUT: float = 8.0

var bar_width: float = WIDTH
var _a: int = -1
var _b: int = -1
var _share: float = 0.5
var _lean: float = CUT * 0.5
var _shown_a: float = 0.0
var _shown_b: float = 0.0
var _mark_off: float = 0.0
var _left: Label
var _right: Label
var _mark: UiShape
var _tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left = _total(HORIZONTAL_ALIGNMENT_LEFT, 20.0)
	_right = _total(HORIZONTAL_ALIGNMENT_RIGHT, bar_width - 140.0)


func _total(align: HorizontalAlignment, x: float) -> Label:
	var l: Label = UiTheme.label("", 26)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = align
	l.position = Vector2(x, 1.0)
	l.size = Vector2(120.0, 30.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## How much of the bar the first side gets.
static func share_of(a: int, b: int) -> float:
	if a + b <= 0 or a == b:
		return 0.5
	return clampf(float(a) / float(a + b), MIN_SHARE, 1.0 - MIN_SHARE)


## How wide the bar is now; the meeting point and the right total follow at once.
func set_bar_width(w: float) -> void:
	bar_width = clampf(w, MIN_WIDTH, WIDTH)
	custom_minimum_size.x = bar_width
	size.x = bar_width
	_right.position.x = bar_width - 140.0
	_layout()


## Where the two colours meet on the bar as it is now.
func _meet_x() -> float:
	var least: float = maxf(MIN_SHARE, MIN_SIDE / bar_width)
	return bar_width * clampf(_share, least, 1.0 - least)


## A new battle: from level to its totals.
func start(a: int, b: int) -> void:
	_a = -1
	_b = -1
	_share = 0.5
	_lean = CUT * 0.5
	_shown_a = 0.0
	_shown_b = 0.0
	show_totals(a, b)


## The totals now; nothing happens when they did not change.
func show_totals(a: int, b: int) -> void:
	if a == _a and b == _b:
		return
	_a = a
	_b = b
	_left.add_theme_color_override("font_color", Palette.GOLD if a > b else Palette.FG)
	_right.add_theme_color_override("font_color", Palette.GOLD if b > a else Palette.FG)
	_new_mark()
	var goal_off: float = -_mark.custom_minimum_size.x * 0.5
	if a > b:
		goal_off = MARK_GAP_RIGHT
	elif b > a:
		goal_off = -_mark.custom_minimum_size.x - MARK_GAP_LEFT
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var time: float = MOVE_TIME * GameSettings.anim_scale()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_share, _share, share_of(a, b), time)
	_tween.tween_method(_set_lean, _lean, 0.0 if a == b else CUT * 0.5, time)
	_tween.tween_method(_set_mark_off, _mark_off, goal_off, time)
	_tween.tween_method(_set_shown_a, _shown_a, float(a), time)
	_tween.tween_method(_set_shown_b, _shown_b, float(b), time)
	_mark.scale = Vector2.ONE * 0.4
	_mark.create_tween().tween_property(_mark, "scale", Vector2.ONE, POP_TIME * GameSettings.anim_scale()).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_layout()


func _new_mark() -> void:
	if _mark != null:
		remove_child(_mark)
		_mark.queue_free()
	_mark = UiShape.chip("TIE" if _a == _b else "+%d" % absi(_a - _b), Palette.FG if _a == _b else Palette.GOLD, Color.BLACK, MARK_FONT, MARK_H, MARK_CUT)
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.pivot_offset = _mark.custom_minimum_size * 0.5
	add_child(_mark)


func _set_share(v: float) -> void:
	_share = v
	_layout()


func _set_lean(v: float) -> void:
	_lean = v
	queue_redraw()


func _set_mark_off(v: float) -> void:
	_mark_off = v
	_layout()


func _set_shown_a(v: float) -> void:
	_shown_a = v
	_left.text = str(roundi(v))


func _set_shown_b(v: float) -> void:
	_shown_b = v
	_right.text = str(roundi(v))


func _layout() -> void:
	if _mark != null:
		_mark.position = Vector2(_meet_x() + _mark_off, (HEIGHT - MARK_H) * 0.5)
	queue_redraw()


func _draw() -> void:
	var x: float = _meet_x()
	var w: float = bar_width
	# The gap closes with the lean: level, the two colours meet on the middle line.
	var gap: float = 2.0 * _lean / (CUT * 0.5)
	draw_colored_polygon(PackedVector2Array([Vector2(CUT, 0), Vector2(x + _lean, 0), Vector2(x - _lean, HEIGHT), Vector2(0, HEIGHT)]), Palette.team(0))
	draw_colored_polygon(PackedVector2Array([Vector2(x + _lean + gap, 0), Vector2(w, 0), Vector2(w - CUT, HEIGHT), Vector2(x - _lean + gap, HEIGHT)]), Palette.team(1))
	draw_rect(Rect2(w * 0.5 - 1.0, -4.0, 2.0, HEIGHT + 8.0), Palette.FG)
