extends GutTest
## The throw preview the bot uses (TerrainPhysics.roll_path) against plain ground and terrain.

var tuning: PhysicsTuning
var map: HexMap


func before_all() -> void:
	tuning = PhysicsTuning.load_default()
	map = HexMap.new(23, tuning.hex_size)


func _len(path: PackedVector2Array) -> float:
	return path[0].distance_to(path[path.size() - 1])


## From a few hexes before the centre, straight across it (along -z).
func _throw(tm: TerrainMap, power: float) -> PackedVector2Array:
	var from: Vector2 = map.to_world(map.center_cell()) + Vector2(0, 6.0 * tuning.hex_spacing())
	return TerrainPhysics.roll_path(tm, map, tuning, 2, from, Vector2(0, -1), power)


func test_plain_ground_matches_the_tuned_range() -> void:
	var hexes: float = _len(_throw(TerrainMap.new(), 0.5)) / tuning.hex_spacing()
	assert_almost_eq(hexes, tuning.full_power_hexes(2) * 0.5, 0.5)


func test_mud_stops_short_and_ice_carries_on() -> void:
	var plain: float = _len(_throw(TerrainMap.new(), 0.4))
	var c: Vector2i = map.center_cell()
	var mud := TerrainMap.new()
	for d: Vector2i in [Vector2i(0, 0), Vector2i(1, -2), Vector2i(0, 2), Vector2i(-1, 4)]:
		mud.set_patch(c + d, Terrain.Type.MUD, map)
	var ice := TerrainMap.new()
	for d: Vector2i in [Vector2i(0, 0), Vector2i(1, -2), Vector2i(0, 2), Vector2i(-1, 4)]:
		ice.set_patch(c + d, Terrain.Type.ICE, map)
	assert_lt(_len(_throw(mud, 0.4)), plain)
	assert_gt(_len(_throw(ice, 0.4)), plain)


func test_wind_bends_the_path_sideways() -> void:
	var tm := TerrainMap.new()
	var c: Vector2i = map.center_cell()
	for d: Vector2i in [Vector2i(0, 0), Vector2i(1, -2), Vector2i(0, 2), Vector2i(-1, 4), Vector2i(2, -4)]:
		tm.set_patch(c + d, Terrain.Type.WIND, map, 0)
	var path: PackedVector2Array = _throw(tm, 0.6)
	assert_gt(path[path.size() - 1].x - path[0].x, 0.3, "pushed towards +x")


func test_a_path_off_the_map_stops_just_outside() -> void:
	var from: Vector2 = map.to_world(map.center_cell())
	var path: PackedVector2Array = TerrainPhysics.roll_path(TerrainMap.new(), map, tuning, 2, from, Vector2(1, 0), 1.0)
	assert_false(map.contains(map.from_world(path[path.size() - 1])))
	assert_true(map.contains(map.from_world(path[path.size() - 2])))
