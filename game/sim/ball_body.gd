class_name BallBody
extends RigidBody3D
## One ball in the physics sim. It slides without friction or spin and slows down at a
## constant rate (scaled by terrain). The collider is an upright cylinder of the ball's radius,
## so every ball-to-ball contact is horizontal and hits are plain billiards weighted by mass,
## whatever the sizes. The view draws a sphere and fakes the rolling. Every roll ends in a
## RollResult.

signal motion_started(ball: BallBody, thrown: bool)
signal moved(delta: Vector3)
signal roll_finished(ball: BallBody, result: RollResult)

enum Motion { RESTING, MOVING, SNAPPING, OUT }

const LAYER_GROUND: int = 1
const LAYER_BALLS: int = 2
## Physics frames between two path samples.
const PATH_EVERY: int = 3
## Frames below stop speed before the ball counts as stopped.
const REST_FRAMES: int = 4

var ball_id: String = ""
var wt: int = 2
var motion: Motion = Motion.RESTING
## Hex the ball rests on, or is snapping to.
var cell: Vector2i = Vector2i.ZERO
var world: BallWorld
var tuning: PhysicsTuning

var _cylinder: CylinderShape3D
var _result: RollResult
var _entered_map: bool = false
var _slow_frames: int = 0
var _frame: int = 0
var _last_pos: Vector3 = Vector3.ZERO
var _grounded: bool = false
var _snap_tween: Tween


func setup(id: String, wt_: int, world_: BallWorld) -> void:
	ball_id = id
	world = world_
	tuning = world_.tuning
	collision_layer = LAYER_BALLS
	collision_mask = LAYER_GROUND | LAYER_BALLS
	axis_lock_angular_x = true
	axis_lock_angular_y = true
	axis_lock_angular_z = true
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	var mat := PhysicsMaterial.new()
	mat.friction = 0.0
	# Bounces add up per contact, so each ball carries half of the ball-to-ball bounce.
	mat.bounce = tuning.ball_bounce * 0.5
	physics_material_override = mat
	_cylinder = CylinderShape3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = _cylinder
	add_child(shape)
	body_entered.connect(_on_body_entered)
	set_wt(wt_)


func radius() -> float:
	return tuning.radius(wt)


func is_big() -> bool:
	return tuning.is_big(wt)


func set_wt(value: int) -> void:
	wt = clampi(value, 1, 9)
	var r: float = radius()
	_cylinder.radius = r
	_cylinder.height = 2.0 * r
	mass = tuning.mass(wt)
	if motion == Motion.RESTING and is_inside_tree():
		global_position.y = radius()


## Teleports the ball to rest at `pos` (ground level is y = 0).
func place(pos: Vector3) -> void:
	_kill_snap()
	freeze = false
	linear_velocity = Vector3.ZERO
	global_position = Vector3(pos.x, radius(), pos.z)
	_last_pos = global_position
	cell = world.hex_at(global_position)
	motion = Motion.RESTING
	_result = null


## Slingshot throw. `power` 0..1, `dir` is flattened onto the table.
func launch(dir: Vector3, power: float) -> void:
	var p: float = clampf(power, 0.0, 1.0)
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	_kill_snap()
	freeze = false
	_begin(true, p)
	sleeping = false
	linear_velocity = flat * tuning.launch_speed(wt) * pow(p, tuning.power_exponent)


func is_grounded() -> bool:
	return _grounded


func horizontal_speed() -> float:
	return Vector2(linear_velocity.x, linear_velocity.z).length()


## Re-runs the snap, e.g. after the ball changed size.
func resnap() -> void:
	if motion == Motion.RESTING:
		_result = RollResult.new()
		_result.ball_id = ball_id
		_result.start_hex = cell
		_start_snap()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	_grounded = false
	for i: int in state.get_contact_count():
		if absf(state.get_contact_local_normal(i).y) > 0.6:
			_grounded = true
			break
	if not _grounded or motion == Motion.SNAPPING:
		return
	var v: Vector3 = state.linear_velocity
	# The table is flat in 1a: nothing should push a ball upwards.
	v.y = minf(v.y, 0.0)
	var speed: float = Vector2(v.x, v.z).length()
	if speed <= 0.0:
		state.linear_velocity = v
		return
	var drop: float = tuning.deceleration * world.friction_factor_at(state.transform.origin) * state.step
	var k: float = maxf(0.0, speed - drop) / speed
	state.linear_velocity = Vector3(v.x * k, v.y, v.z * k)


func _physics_process(delta: float) -> void:
	var pos: Vector3 = global_position
	var step: Vector3 = pos - _last_pos
	_last_pos = pos
	match motion:
		Motion.RESTING:
			if horizontal_speed() > tuning.stop_speed * 2.0:
				_begin(false, 0.0)
		Motion.MOVING:
			if step.length_squared() > 0.0:
				moved.emit(step)
			_track(pos, delta)
		Motion.OUT:
			if step.length_squared() > 0.0:
				moved.emit(step)


func _begin(thrown: bool, power: float) -> void:
	var pos: Vector3 = global_position
	_result = RollResult.new()
	_result.ball_id = ball_id
	_result.thrown = thrown
	_result.power = power
	_result.start_hex = world.hex_at(pos)
	_result.path.append(pos)
	_entered_map = world.area_at(pos) == BallWorld.Area.MAP
	_slow_frames = 0
	_frame = 0
	motion = Motion.MOVING
	motion_started.emit(self, thrown)


func _track(pos: Vector3, delta: float) -> void:
	_result.duration += delta
	_frame += 1
	if _frame % PATH_EVERY == 0:
		_result.path.append(pos)
	var area: BallWorld.Area = world.area_at(pos)
	if area == BallWorld.Area.MAP:
		_entered_map = true
	elif area == BallWorld.Area.STRIP and _entered_map:
		_go_out("strip")
		return
	elif area == BallWorld.Area.VOID:
		_go_out("edge")
		return
	if pos.y < -3.0:
		_go_out("fell")
		return
	if _grounded and horizontal_speed() < tuning.stop_speed:
		_slow_frames += 1
		if _slow_frames >= REST_FRAMES:
			_start_snap()
	else:
		_slow_frames = 0


func _go_out(reason: String) -> void:
	motion = Motion.OUT
	_result.ring_out = true
	_result.ring_out_reason = reason
	_result.end_area = BallWorld.Area.VOID
	_result.end_hex = world.hex_at(global_position)
	_result.path.append(global_position)
	roll_finished.emit(self, _result)


func _start_snap() -> void:
	motion = Motion.SNAPPING
	linear_velocity = Vector3.ZERO
	var pos: Vector3 = global_position
	var target: Vector3 = world.snap_point(self)
	target.y = pos.y
	cell = world.hex_at(target)
	if target.distance_to(pos) < 0.01:
		_on_snapped()
		return
	freeze = true
	_snap_tween = create_tween()
	_snap_tween.tween_property(self, "global_position", target, tuning.snap_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_snap_tween.tween_callback(_on_snapped)


func _on_snapped() -> void:
	_snap_tween = null
	freeze = false
	linear_velocity = Vector3.ZERO
	motion = Motion.RESTING
	var pos: Vector3 = global_position
	_last_pos = pos
	cell = world.hex_at(pos)
	if _result == null:
		return
	_result.end_hex = cell
	_result.end_area = world.area_at(pos)
	_result.path.append(pos)
	roll_finished.emit(self, _result)


func _kill_snap() -> void:
	if _snap_tween != null:
		_snap_tween.kill()
		_snap_tween = null


func _on_body_entered(body: Node) -> void:
	if _result == null or motion != Motion.MOVING:
		return
	if body is BallBody:
		var other := body as BallBody
		if not _result.collisions.has(other.ball_id):
			_result.collisions.append(other.ball_id)
