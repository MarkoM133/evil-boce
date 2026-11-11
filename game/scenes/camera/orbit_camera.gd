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

## Off while the pause menu is up.
var keys_on: bool = true
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
## The home view looks from the far (red) side: turned half round, its target mirrored.
var _home_flipped: bool = false
var _near_bias: float = 0.06
var _extent := Vector2(40, 40)
var _home_distance: float = 30.0
## A short shake (a KO): how much is left of it and how hard it started.
var _shake_t: float = 0.0
var _shake_time: float = 0.0
var _shake_amp: float = 0.0


func _init() -> void:
	camera = Camera3D.new()
	camera.fov = 38.0
	camera.near = 0.1
	camera.far = 400.0
	add_child(camera)


## Sets the default view for a table of `extent` (x, z) size; the near strip is at the bottom.
## `near_bias` moves the view centre towards the near strip (fraction of the table depth) and
## `zoom` scales the distance; the match uses more of both so the HUD does not cover the strip.
func frame_table(extent: Vector2, near_bias: float = 0.06, zoom: float = 1.25) -> void:
	bounds = extent * 0.5
	_extent = extent
	_near_bias = near_bias
	_home_target = Vector3(0, 0, extent.y * near_bias * (-1.0 if _home_flipped else 1.0))
	_home_distance = maxf(extent.x, extent.y) * zoom
	reset_view(true)


## Home view from the red side (true) or the blue side, at once (online playtest 2026-11-07: the
## guest on red looked at the table from blue).
func set_flipped(on: bool) -> void:
	_home_flipped = on
	_home_target = Vector3(0, 0, _extent.y * _near_bias * (-1.0 if on else 1.0))
	reset_view(true)


## The home view is from the red side.
func is_flipped() -> bool:
	return _home_flipped


func reset_view(instant: bool = false) -> void:
	target = _home_target
	yaw = PI if _home_flipped else 0.0
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


func _held(key: Key) -> bool:
	return keys_on and Input.is_key_pressed(key)


func _process(delta: float) -> void:
	var move := Vector2.ZERO
	if _held(KEY_A) or _held(KEY_LEFT):
		move.x -= 1.0
	if _held(KEY_D) or _held(KEY_RIGHT):
		move.x += 1.0
	if _held(KEY_W) or _held(KEY_UP):
		move.y += 1.0
	if _held(KEY_S) or _held(KEY_DOWN):
		move.y -= 1.0
	if move != Vector2.ZERO:
		_pan(move.normalized() * distance * 0.9 * delta)
	if _held(KEY_Q):
		yaw += 1.6 * delta
	if _held(KEY_E):
		yaw -= 1.6 * delta
	var a: float = 1.0 - exp(-SMOOTH * delta)
	_cur_target = _cur_target.lerp(target, a)
	_cur_yaw = lerp_angle(_cur_yaw, yaw, a)
	_cur_pitch = lerpf(_cur_pitch, pitch, a)
	_cur_distance = lerpf(_cur_distance, distance, a)
	if _shake_t > 0.0:
		_shake_t = maxf(_shake_t - delta, 0.0)
	_apply()


## A short jolt of the view, fading out over `time` seconds (a KO on the table).
func shake(amp: float = 0.35, time: float = 0.28) -> void:
	if not GameSettings.effect("shake"):
		return
	_shake_amp = amp
	_shake_time = time
	_shake_t = time


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
	var jolt := Vector3.ZERO
	if _shake_t > 0.0 and _shake_time > 0.0:
		var k: float = _shake_t / _shake_time
		jolt = Vector3(randf_range(-1.0, 1.0), randf_range(-0.6, 0.6), randf_range(-1.0, 1.0)) \
			* _shake_amp * k * k * (_cur_distance / 30.0)
	camera.transform = Transform3D(Basis.looking_at(-off, Vector3.UP), _cur_target + off * _cur_distance + jolt)
