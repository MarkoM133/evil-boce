extends SceneTree
## Headless physics check: throw distance per WT and power, terrain, and ball-on-ball hits.
## godot_console --headless --path game --fixed-fps 120 -s res://tools/measure_throws.gd

class FlatWorld:
	extends BallWorld
	var factor: float = 1.0

	func friction_factor_at(_pos: Vector3) -> float:
		return factor


var tuning: PhysicsTuning
var world: FlatWorld
var spacing: float = 1.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	tuning = PhysicsTuning.load_default()
	world = FlatWorld.new(tuning)
	spacing = tuning.hex_spacing()
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
	return b


func _settle(balls: Array[BallBody], limit: float) -> float:
	var t: float = 0.0
	while t < limit:
		await physics_frame
		t += 1.0 / Engine.physics_ticks_per_second
		var busy: bool = false
		for b: BallBody in balls:
			if b.motion == BallBody.Motion.MOVING or b.motion == BallBody.Motion.SNAPPING:
				busy = true
		if not busy and t > 0.05:
			break
	return t


## [hexes travelled, seconds]
func _throw(wt: int, power: float) -> Array[float]:
	var b: BallBody = _make("m", wt, Vector3.ZERO)
	await physics_frame
	var start: Vector3 = b.global_position
	b.launch(Vector3(0, 0, -1), power)
	var t: float = await _settle([b], 20.0)
	var d: float = Vector2(b.global_position.x - start.x, b.global_position.z - start.z).length()
	b.free()
	return [d / spacing, t]


## [mover hexes after the hit, target hexes]
func _hit(mover_wt: int, target_wt: int, gap_hexes: float) -> Array[float]:
	var m: BallBody = _make("mover", mover_wt, Vector3.ZERO)
	var target_pos := Vector3(0, 0, -gap_hexes * spacing)
	var t: BallBody = _make("target", target_wt, target_pos)
	await physics_frame
	var t_start: Vector3 = t.global_position
	m.launch(Vector3(0, 0, -1), 1.0)
	var hit_pos := Vector3.INF
	var waited: float = 0.0
	while waited < 20.0:
		await physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second
		if hit_pos == Vector3.INF and t.horizontal_speed() > 0.01:
			hit_pos = m.global_position
		var busy: bool = false
		for b: BallBody in [m, t]:
			if b.motion == BallBody.Motion.MOVING or b.motion == BallBody.Motion.SNAPPING:
				busy = true
		if not busy and waited > 0.05:
			break
	var mover_after: float = 0.0
	if hit_pos != Vector3.INF:
		mover_after = Vector2(m.global_position.x - hit_pos.x, m.global_position.z - hit_pos.z).length()
	var target_d: float = Vector2(t.global_position.x - t_start.x, t.global_position.z - t_start.z).length()
	m.free()
	t.free()
	return [mover_after / spacing, target_d / spacing]
