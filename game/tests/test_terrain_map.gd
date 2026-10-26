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


func test_ramp_and_wind_parse_and_keep_their_centre_and_direction() -> void:
	assert_eq(Terrain.parse("Ramp"), Terrain.Type.RAMP)
	assert_eq(Terrain.parse(" wind "), Terrain.Type.WIND)
	assert_eq(Terrain.name_of(Terrain.Type.WIND), "Wind")
	var map := HexMap.new(17, 1.0)
	var c: Vector2i = map.center_cell()
	var tm := TerrainMap.new()
	tm.set_patch(c, Terrain.Type.RAMP, map)
	tm.set_patch(c + Vector2i(4, 0), Terrain.Type.WIND, map, 8)
	assert_eq(tm.center_of(c + Vector2i(1, 0)), c, "every hex of a hill knows its top")
	assert_eq(tm.dir_of(c + Vector2i(4, 1)), 2, "directions wrap at 6")
	assert_true(tm.has(Terrain.Type.WIND))
	var back: TerrainMap = TerrainMap.from_dict(tm.to_dict())
	assert_eq(back.cells.size(), 14)
	assert_eq(back.at(c + Vector2i(0, 1)), Terrain.Type.RAMP)
	assert_eq(back.center_of(c + Vector2i(0, 1)), c)
	assert_eq(back.dir_of(c + Vector2i(4, 0)), 2)
	tm.set_patch(c, Terrain.Type.NONE, map)
	assert_false(tm.has(Terrain.Type.RAMP))
	assert_eq(tm.center_of(c), c)


## Wind (GDD 6, 2026-10-26): the direction is drawn when the stage is revealed, kept with the
## stage, and the terrain map blows that way.
func test_a_revealed_wind_stage_keeps_its_drawn_direction() -> void:
	var catalog := CardCatalog.from_json_text(FileAccess.get_file_as_string("res://tests/fixtures/cards.json"))
	var engine := RulesEngine.new(catalog)
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var cards: Dictionary = {"TX-010": 40}
	var s: GameState = engine.start_match(settings, [
		{"heroes": ["TA-001"], "cards": cards, "stages": ["TS-001", "TS-002", "TS-003"], "cores": []},
		{"heroes": ["TB-001"], "cards": cards, "stages": ["TS-004", "TS-005", "TS-006"], "cores": []},
	], 2)
	var st: StageState = s.stages[0]
	catalog.get_card(st.card_id).terrain = Terrain.Type.WIND
	assert_eq(st.wind_dir, -1, "no direction before the reveal")
	var h: HeroState = s.hero("p0:TA-001")
	h.zone = HeroState.ZONE_MAP
	var r := RollResult.new()
	r.ball_id = h.id
	r.end_area = BallWorld.Area.MAP
	r.end_hex = st.center
	engine._apply_result(s, h, r)
	assert_true(st.revealed)
	assert_true(st.wind_dir >= 0 and st.wind_dir < 6, "a direction out of six")
	assert_eq(engine.terrain(s).dir_of(st.center), st.wind_dir, "the terrain blows that way")
	var back: GameState = GameState.from_dict(s.to_dict())
	assert_eq(back.stages[0].wind_dir, st.wind_dir, "kept in the state")
