class_name SandboxWorld
extends BallWorld
## BallWorld backed by the arena: map / strip / void, terrain, and snapping to the nearest
## free hex.

var arena: Arena
var pieces: Array[SandboxPiece] = []


func _init(tuning_: PhysicsTuning, arena_: Arena) -> void:
	super(tuning_)
	arena = arena_


func area_at(pos: Vector3) -> Area:
	return arena.area_at(pos)


func friction_factor_at(pos: Vector3) -> float:
	return tuning.terrain_factor(arena.terrain_at(pos))


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


## True when a ball of that size could rest on `center` without overlapping another.
func is_free(center: Vector2i, big: bool, except: BallBody = null) -> bool:
	var mine: Array[Vector2i] = arena.map.footprint(center, big)
	for p: SandboxPiece in pieces:
		var b: BallBody = p.body
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
