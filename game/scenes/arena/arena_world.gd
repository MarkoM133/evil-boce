class_name ArenaWorld
extends BallWorld
## BallWorld backed by an Arena: map / strip / void, terrain, and snapping to the nearest free
## hex. Used by the sandbox and the match.

var arena: Arena
var terrain: TerrainMap
## Balls that occupy hexes when they rest on the map.
var bodies: Array[BallBody] = []
## Extra hexes nothing may stop on (walls).
var blocked: Dictionary[Vector2i, bool] = {}


func _init(tuning_: PhysicsTuning, arena_: Arena, terrain_: TerrainMap) -> void:
	super(tuning_)
	arena = arena_
	terrain = terrain_


func area_at(pos: Vector3) -> Area:
	return arena.area_at(pos)


func strip_at(pos: Vector3) -> int:
	return arena.strip_at(pos)


func friction_factor_at(pos: Vector3) -> float:
	return tuning.terrain_factor(terrain.at(arena.hex_at(pos)))


func push_at(pos: Vector3) -> Vector2:
	var a: Vector2i = arena.hex_at(pos)
	match terrain.at(a):
		Terrain.Type.WIND:
			return wind_vector(terrain.dir_of(a)) * tuning.wind_accel
		Terrain.Type.RAMP:
			var off: Vector2 = _from_top(pos, a)
			var r: float = hill_radius()
			if off.length() >= r:
				return Vector2.ZERO
			return off / r * tuning.hill_accel
	return Vector2.ZERO


func height_at(pos: Vector3) -> float:
	return arena.height_at(pos)


func hill_radius() -> float:
	return arena.hill_radius()


## Unit (x, z) vector of a hex direction.
func wind_vector(dir: int) -> Vector2:
	return Hex.to_world(Hex.DIRECTIONS[posmod(dir, 6)], 1.0).normalized()


func _from_top(pos: Vector3, a: Vector2i) -> Vector2:
	var top: Vector3 = arena.hex_center(terrain.center_of(a))
	return Vector2(pos.x - top.x, pos.z - top.z)


func hex_at(pos: Vector3) -> Vector2i:
	return arena.hex_at(pos)


func snap_point(ball: BallBody) -> Vector3:
	var pos: Vector3 = ball.global_position
	if arena.area_at(pos) != Area.MAP:
		return pos
	var here: Vector2i = arena.hex_at(pos)
	var options: Array[Vector2i] = Hex.spiral(here, 3)
	options.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _dist2(arena.hex_center(a), pos) < _dist2(arena.hex_center(b), pos))
	for a: Vector2i in options:
		if arena.map.contains(a) and is_free(a, ball.is_big(), ball):
			return arena.hex_center(a)
	return pos


## True when a ball of that size could rest on `center` without overlapping another ball,
## a wall or the edge of the map.
func is_free(center: Vector2i, big: bool, except: BallBody = null) -> bool:
	var mine: Array[Vector2i] = arena.map.footprint(center, big)
	for a: Vector2i in mine:
		if not arena.map.contains(a) or blocked.has(a):
			return false
	for b: BallBody in bodies:
		if b == except:
			continue
		if b.motion != BallBody.Motion.RESTING and b.motion != BallBody.Motion.SNAPPING:
			continue
		if arena.area_at(b.global_position) != Area.MAP:
			continue
		for a: Vector2i in arena.map.footprint(b.cell, b.is_big()):
			if mine.has(a):
				return false
	return true


static func _dist2(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length_squared()
