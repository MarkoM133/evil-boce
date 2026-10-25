class_name OrbitCamera
extends Node3D
## Free table camera: orbit (right drag, or left drag on empty table), pan (middle drag,
## WASD / arrows), zoom (wheel), Q / E to turn. Always free, in every phase (GDD 3).

const PITCH_MIN: float = deg_to_rad(18.0)
const PITCH_MAX: float = deg_to_rad(86.0)
const DIST_MIN: float = 3.0
const DIST_MAX: float = 90.0
const SMOOTH: float = 14.0

enum Drag { NONE, ORBIT, PAN }

var camera: Camera3D
## Target, yaw, pitch and distance the camera eases towards.
var target := Vector3.ZERO
var yaw: float = 0.0
var pitch: float = deg_to_rad(52.0)
var distance: float = 30.0
## Pan stays inside this half-size around the origin.
var bounds := Vector2(20, 20)

var _cur_target := Vector3.ZERO
var _cur_yaw: float = 0.0
var _cur_pitch: float = deg_to_rad(52.0)
var _cur_distance: float = 30.0
var _drag: Drag = Drag.NONE
var _home_target := Vector3.ZERO
var _home_distance: float = 30.0


func _init() -> void:
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.near = 0.1
	camera.far = 400.0
	add_child(camera)


## Sets the default view for a table of `extent` (x, z) size; the near strip is at the bottom.
func frame_table(extent: Vector2) -> void:
	bounds = extent * 0.5
	_home_target = Vector3(0, 0, extent.y * 0.06)
	_home_distance = maxf(extent.x, extent.y) * 1.25
	reset_view(true)


func reset_view(instant: bool = false) -> void:
	target = _home_target
	yaw = 0.0
	pitch = deg_to_rad(52.0)
	distance = _home_distance
	if instant:
		_snap_now()


func focus(point: Vector3, dist: float) -> void:
	target = Vector3(point.x, 0, point.z)
	distance = clampf(dist, DIST_MIN, DIST_MAX)


func begin_drag(kind: Drag) -> void:
	_drag = kind


func is_dragging() -> bool:
	return _drag != Drag.NONE


## Returns true when the event was used.
func handle_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					distance = clampf(distance * 0.88, DIST_MIN, DIST_MAX)
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					distance = clampf(distance / 0.88, DIST_MIN, DIST_MAX)
				return true
			MOUSE_BUTTON_RIGHT:
				_drag = Drag.ORBIT if mb.pressed else Drag.NONE
				return true
			MOUSE_BUTTON_MIDDLE:
				_drag = Drag.PAN if mb.pressed else Drag.NONE
				return true
			MOUSE_BUTTON_LEFT:
				if not mb.pressed and _drag != Drag.NONE:
					_drag = Drag.NONE
					return true
	elif event is InputEventMouseMotion and _drag != Drag.NONE:
		var mm := event as InputEventMouseMotion
		if _drag == Drag.ORBIT:
			yaw -= mm.relative.x * 0.006
			pitch = clampf(pitch + mm.relative.y * 0.005, PITCH_MIN, PITCH_MAX)
		else:
			var k: float = distance * 0.0016
			_pan(Vector2(-mm.relative.x * k, mm.relative.y * k))
		return true
	return false


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y -= 1.0
	if move != Vector2.ZERO:
		_pan(move.normalized() * distance * 0.9 * delta)
	if Input.is_key_pressed(KEY_Q):
		yaw += 1.6 * delta
	if Input.is_key_pressed(KEY_E):
		yaw -= 1.6 * delta
	var a: float = 1.0 - exp(-SMOOTH * delta)
	_cur_target = _cur_target.lerp(target, a)
	_cur_yaw = lerp_angle(_cur_yaw, yaw, a)
	_cur_pitch = lerpf(_cur_pitch, pitch, a)
	_cur_distance = lerpf(_cur_distance, distance, a)
	_apply()


## `d.x` right, `d.y` forward, in metres on the table.
func _pan(d: Vector2) -> void:
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	target += right * d.x + fwd * d.y
	target.x = clampf(target.x, -bounds.x, bounds.x)
	target.z = clampf(target.z, -bounds.y, bounds.y)


func _snap_now() -> void:
	_cur_target = target
	_cur_yaw = yaw
	_cur_pitch = pitch
	_cur_distance = distance
	_apply()


func _apply() -> void:
	var off := Vector3(sin(_cur_yaw) * cos(_cur_pitch), sin(_cur_pitch), cos(_cur_yaw) * cos(_cur_pitch))
	camera.transform = Transform3D(Basis.looking_at(-off, Vector3.UP), _cur_target + off * _cur_distance)
