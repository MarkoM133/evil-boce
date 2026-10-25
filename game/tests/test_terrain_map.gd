extends GutTest


func test_patch_paints_seven_and_clears() -> void:
	var map := HexMap.new(17)
	var tm := TerrainMap.new()
	var c: Vector2i = map.center_cell()
	tm.set_patch(c, Terrain.Type.ICE, map)
	assert_eq(tm.cells.size(), 7)
	assert_eq(tm.at(c), Terrain.Type.ICE)
	assert_eq(tm.at(Hex.neighbor(c, 2)), Terrain.Type.ICE)
	assert_eq(tm.at(c + Vector2i(2, 0)), Terrain.Type.NONE)
	tm.set_patch(c, Terrain.Type.NONE, map)
	assert_true(tm.is_empty())


func test_patch_is_clipped_to_map() -> void:
	var map := HexMap.new(15)
	var tm := TerrainMap.new()
	tm.set_patch(Hex.offset_to_axial(0, 0), Terrain.Type.MUD, map)
	assert_true(tm.cells.size() < 7)
	for a: Vector2i in tm.cells:
		assert_true(map.contains(a))


func test_json_round_trip() -> void:
	var map := HexMap.new(17)
	var tm := TerrainMap.new()
	tm.set_patch(Vector2i(3, 4), Terrain.Type.ICE, map)
	tm.set_patch(Vector2i(-2, 9), Terrain.Type.MUD, map)
	var back: TerrainMap = TerrainMap.from_dict(JsonUtil.as_dict(JSON.parse_string(JSON.stringify(tm.to_dict()))))
	assert_eq(back.cells.size(), tm.cells.size())
	for a: Vector2i in tm.cells:
		assert_eq(back.at(a), tm.at(a))


func test_terrain_names_round_trip() -> void:
	for t: Terrain.Type in [Terrain.Type.NONE, Terrain.Type.ICE, Terrain.Type.MUD]:
		assert_eq(Terrain.parse(Terrain.name_of(t)), t)
	assert_eq(Terrain.parse(" mud "), Terrain.Type.MUD)
	assert_eq(Terrain.parse("Lava"), Terrain.Type.NONE)
