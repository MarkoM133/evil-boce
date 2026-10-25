class_name MenuLogo
extends Control
## The side strip menu's logo. Left alone for IDLE seconds (no mouse or key), it fades out and
## the last match takes its place in the logo's circle, slowly zooming in, with a line about it
## under the circle; any mouse move, key or click brings the logo back.

const IDLE: float = 8.0
const FADE: float = 0.7
## The picture zooms from 1 to 1 + ZOOM over ZOOM_TIME seconds.
const ZOOM: float = 0.18
const ZOOM_TIME: float = 30.0
## The circle's radius as a share of half the control's smaller side (the logo's ring).
const RING: float = 0.8
const POINTS: int = 96

var logo: Texture2D
var shot: Texture2D
var caption: String = ""
var _idle: float = 0.0
## 0: the logo, 1: the last match.
var _k: float = 0.0
var _zoom_t: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if shot == null:
		return
	_idle += delta
	var was: float = _k
	_k = move_toward(_k, 1.0 if _idle >= IDLE else 0.0, delta / FADE)
	_zoom_t = _zoom_t + delta if _k > 0.0 else 0.0
	if _k != was or _k > 0.0:
		queue_redraw()


func _input(event: InputEvent) -> void:
	# The window gets the odd motion event of no length (focus, other windows); not a move.
	if event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() >= 2.0:
			_idle = 0.0
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		_idle = 0.0


## Screenshots: as if left alone long enough.
func go_idle() -> void:
	_idle = IDLE


func _draw() -> void:
	var c: Vector2 = size * 0.5
	if logo != null and _k < 1.0:
		var ls: Vector2 = logo.get_size()
		var fit: float = minf(size.x / ls.x, size.y / ls.y)
		draw_texture_rect(logo, Rect2(c - ls * fit * 0.5, ls * fit), false, Color(1, 1, 1, 1.0 - _k))
	if shot == null or _k <= 0.0:
		return
	var r: float = minf(size.x, size.y) * 0.5 * RING
	var zoom: float = 1.0 + ZOOM * minf(_zoom_t / ZOOM_TIME, 1.0)
	# A square from the middle of the picture, smaller as it zooms.
	var sz: Vector2 = shot.get_size()
	var side: float = minf(sz.x, sz.y) / zoom
	var uv_half := Vector2(side / sz.x, side / sz.y) * 0.5
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i: int in POINTS:
		var d := Vector2.from_angle(TAU * i / POINTS)
		pts.append(c + d * r)
		uvs.append(Vector2(0.5, 0.5) + d * uv_half)
	var tint := Color(1, 1, 1, _k)
	var colors := PackedColorArray()
	colors.resize(POINTS)
	colors.fill(tint)
	draw_polygon(pts, colors, uvs, shot)
	draw_arc(c, r, 0.0, TAU, POINTS, Color(Palette.ACCENT, _k), 8.0, true)
	if caption != "":
		var font: Font = UiTheme.display_heavy()
		draw_string(font, Vector2(0, c.y + r + 44.0), caption.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 20,
			Color(Palette.FG, _k))
