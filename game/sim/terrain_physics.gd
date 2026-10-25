class_name TerrainPhysics
extends RefCounted
## What terrain does to a rolling ball, in map space (world x / z as a Vector2). Shared by the
## sim (ArenaWorld) and the bot's throw preview, so both see the same ground: Ice and Mud scale
## the slow-down, a Ramp hill pushes away from its top (and lifts the drawn ball), Wind pushes
## one way.


## Multiplier for the slow-down on hex `a`.
static func friction(tm: TerrainMap, tuning: PhysicsTuning, a: Vector2i) -> float:
	return tuning.terrain_factor(tm.at(a))


## Push on a rolling ball at `p` (m/s^2).
static func push(tm: TerrainMap, map: HexMap, tuning: PhysicsTuning, p: Vector2) -> Vector2:
	var a: Vector2i = map.from_world(p)
	match tm.at(a):
		Terrain.Type.WIND:
			return wind_vector(tm.dir_of(a)) * tuning.wind_accel
		Terrain.Type.RAMP:
			var off: Vector2 = p - map.to_world(tm.center_of(a))
			var r: float = hill_radius(map)
			if off.length() >= r:
				return Vector2.ZERO
			return off / r * tuning.hill_accel
	return Vector2.ZERO


## Ground height at `p` (a hill), for drawing.
static func height(tm: TerrainMap, map: HexMap, tuning: PhysicsTuning, p: Vector2) -> float:
	var a: Vector2i = map.from_world(p)
	if tm.at(a) != Terrain.Type.RAMP:
		return 0.0
	var k: float = (p - map.to_world(tm.center_of(a))).length() / hill_radius(map)
	return tuning.hill_height * maxf(0.0, 1.0 - k * k)


## A hill covers the 7-hex patch: its radius reaches the outer edge of the ring.
static func hill_radius(map: HexMap) -> float:
	return map.spacing() * 1.5


## Unit (x, z) vector of a hex direction.
static func wind_vector(dir: int) -> Vector2:
	return Hex.to_world(Hex.DIRECTIONS[posmod(dir, 6)], 1.0).normalized()


## Where a lone ball thrown from `from` along `dir` at `power` (0..1) goes, ignoring other balls:
## the same slow-down and pushes as BallBody, stepped at `dt`. Returns the points it passes
## (the last one is where it stops) and stops early once it leaves the map after entering it.
static func roll_path(tm: TerrainMap, map: HexMap, tuning: PhysicsTuning, wt: int, from: Vector2,
		dir: Vector2, power: float, dt: float = 1.0 / 60.0) -> PackedVector2Array:
	var out := PackedVector2Array([from])
	var p: Vector2 = from
	var v: Vector2 = dir.normalized() * tuning.launch_speed(wt) * pow(clampf(power, 0.0, 1.0), tuning.power_exponent)
	var entered: bool = map.contains(map.from_world(from))
	for _i: int in 1200:
		v += push(tm, map, tuning, p) * dt
		var speed: float = v.length()
		var drop: float = tuning.deceleration * friction(tm, tuning, map.from_world(p)) * dt
		if speed <= drop or speed < tuning.stop_speed:
			break
		v *= (speed - drop) / speed
		p += v * dt
		out.append(p)
		var inside: bool = map.contains(map.from_world(p))
		if inside:
			entered = true
		elif entered:
			break
	return out
