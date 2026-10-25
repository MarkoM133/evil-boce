extends SceneTree
## Headless physics check: throw distance per WT and power, terrain, and ball-on-ball hits.
## godot_console --headless --path game --fixed-fps 120 -s res://tools/measure_throws.gd

class FlatWorld:
	extends BallWorld
	var factor: float = 1.0
	## Wind everywhere, m/s^2 as (x, z).
	var wind := Vector2.ZERO
	## A hill: top at hill_at, radius hill_r (0 = none).
	var hill_at := Vector3.ZERO
	var hill_r: float = 0.0

	func friction_factor_at(_pos: Vector3) -> float:
		return factor

	func push_at(pos: Vector3) -> Vector2:
		var p: Vector2 = wind
		if hill_r > 0.0:
			var off := Vector2(pos.x - hill_at.x, pos.z - hill_at.z)
			if off.length() < hill_r:
				p += off / hill_r * tuning.hill_accel
		return p


var tuning: PhysicsTuning
var world: FlatWorld
var runner: RollRunner
var spacing: float = 1.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	tuning = PhysicsTuning.load_default()
	world = FlatWorld.new(tuning)
	spacing = tuning.hex_spacing()
	runner = RollRunner.new()
	root.add_child(runner)
	var ground := StaticBody3D.new()
	ground.collision_layer = BallBody.LAYER_GROUND
	var gmat := PhysicsMaterial.new()
	gmat.friction = 0.0
	gmat.bounce = 1.0
	gmat.absorbent = true
	ground.physics_material_override = gmat
	var gshape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(800, 1, 800)
	gshape.shape = box
	gshape.position = Vector3(0, -0.5, 0)
	ground.add_child(gshape)
	root.add_child(ground)
	await physics_frame

	print("")
	print("Throws on plain ground (target hexes at full power: %s)" % [tuning.full_power_hexes_by_wt])
	print("  WT  power   hexes   seconds")
	for wt: int in [1, 2, 3, 4]:
		for power: float in [1.0, 0.5, 0.1, 0.03]:
			var r: Array[float] = await _throw(wt, power)
			print("  %d   %4d%%  %6.2f   %5.2f" % [wt, roundi(power * 100.0), r[0], r[1]])

	print("")
	print("Terrain, WT2 full power")
	for t: Terrain.Type in [Terrain.Type.ICE, Terrain.Type.MUD]:
		world.factor = tuning.terrain_factor(t)
		var r: Array[float] = await _throw(2, 1.0)
		print("  %-4s  %6.2f hexes  %5.2f s" % [Terrain.name_of(t), r[0], r[1]])
	world.factor = 1.0

	print("")
	print("Wind %.1f m/s^2, WT2 thrown along -z (forward)" % tuning.wind_accel)
	print("  wind        power   forward   sideways   seconds")
	var winds: Dictionary[String, Vector2] = {"cross": Vector2(1, 0), "tail": Vector2(0, -1), "head": Vector2(0, 1)}
	for name: String in winds:
		for power: float in [1.0, 0.3]:
			world.wind = winds[name] * tuning.wind_accel
			var e: Array[float] = await _throw_end(2, power)
			print("  %-6s     %4d%%   %6.2f    %6.2f     %5.2f" % [name, roundi(power * 100.0), -e[1] / spacing, e[0] / spacing, e[2]])
	world.wind = Vector2.ZERO

	print("")
	print("Hill (radius 1.5 hexes) whose top is 3 hexes ahead; where WT2 ends, hexes from the top")
	world.hill_r = spacing * 1.5
	world.hill_at = Vector3(0, 0, -3.0 * spacing)
	for power: float in [0.15, 0.2, 0.25, 0.35, 0.6]:
		var e: Array[float] = await _throw_end(2, power)
		var from_top: float = Vector2(e[0] - world.hill_at.x, e[1] - world.hill_at.z).length() / spacing
		print("  %4d%%   %5.2f from the top   %s" % [roundi(power * 100.0), from_top,
			"on top" if from_top < 0.6 else ("on the hill" if from_top < 1.5 else "off the hill")])
	world.hill_r = 0.0

	print("")
	print("Hits at full power, target resting 4 hexes ahead (goal: WT3 into WT1 -> WT1 >= 6, WT3 < 2)")
	print("  mover -> target   mover hexes after hit   target hexes")
	for pair: Vector2i in [Vector2i(3, 1), Vector2i(1, 3), Vector2i(2, 2), Vector2i(4, 2)]:
		var h: Array[float] = await _hit(pair.x, pair.y, 4.0)
		print("  WT%d -> WT%d        %6.2f                 %6.2f" % [pair.x, pair.y, h[0], h[1]])
	print("")
	quit()


func _make(id: String, wt: int, pos: Vector3) -> BallBody:
	var b := BallBody.new()
	b.setup(id, wt, world)
	root.add_child(b)
	b.place(pos)
	runner.watch(b)
	return b


func _drop(b: BallBody) -> void:
	runner.unwatch(b)
	b.free()


## [hexes travelled, seconds]
func _throw(wt: int, power: float) -> Array[float]:
	var b: BallBody = _make("m", wt, Vector3.ZERO)
	await physics_frame
	runner.start(b, Vector3(0, 0, -1), power)
	var o: RollOutcome = await runner.finished
	var r: RollResult = o.thrower_result()
	_drop(b)
	return [r.displacement() / spacing, o.duration]


## [end x, end z, seconds] of a throw from the origin along -z.
func _throw_end(wt: int, power: float) -> Array[float]:
	var b: BallBody = _make("m", wt, Vector3.ZERO)
	await physics_frame
	runner.start(b, Vector3(0, 0, -1), power)
	var o: RollOutcome = await runner.finished
	var end: Vector3 = b.global_position
	_drop(b)
	return [end.x, end.z, o.duration]


## [mover hexes after the hit, target hexes]
func _hit(mover_wt: int, target_wt: int, gap_hexes: float) -> Array[float]:
	var m: BallBody = _make("mover", mover_wt, Vector3.ZERO)
	var target_pos := Vector3(0, 0, -gap_hexes * spacing)
	var t: BallBody = _make("target", target_wt, target_pos)
	await physics_frame
	runner.start(m, Vector3(0, 0, -1), 1.0)
	var hit_pos := Vector3.INF
	while runner.is_running():
		await physics_frame
		if hit_pos == Vector3.INF and t.horizontal_speed() > 0.01:
			hit_pos = m.global_position
	var mover_after: float = 0.0
	if hit_pos != Vector3.INF:
		mover_after = Vector2(m.global_position.x - hit_pos.x, m.global_position.z - hit_pos.z).length()
	var target_d: float = Vector2(t.global_position.x - target_pos.x, t.global_position.z - target_pos.z).length()
	_drop(m)
	_drop(t)
	return [mover_after / spacing, target_d / spacing]
