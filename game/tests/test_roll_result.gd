extends GutTest


func _sample() -> RollResult:
	var r := RollResult.new()
	r.ball_id = "OP1-001#1"
	r.thrown = true
	r.power = 0.5
	r.start_hex = Vector2i(1, 2)
	r.end_hex = Vector2i(4, 2)
	r.end_area = BallWorld.Area.STRIP
	r.strip_entered = 1
	r.duration = 2.25
	r.path = PackedVector3Array([Vector3(0, 0.6, 0), Vector3(3, 0.6, 0), Vector3(3, 0.6, 4)])
	r.collisions.append("JO1-002#3")
	r.cores_picked.append("core:2")
	return r


func test_lengths_and_dict() -> void:
	var r: RollResult = _sample()
	assert_almost_eq(r.path_length(), 7.0, 0.0001)
	assert_almost_eq(r.displacement(), 5.0, 0.0001)
	var d: Dictionary = r.to_dict()
	assert_eq(str(d["ball"]), "OP1-001#1")
	assert_eq(JsonUtil.as_hex(d["end_hex"]), Vector2i(4, 2))
	assert_eq(JsonUtil.as_strings(d["collisions"]), PackedStringArray(["JO1-002#3"]))
	assert_eq(JsonUtil.as_int(d["strip_entered"]), 1)
	# Must survive a JSON round trip (replays, network).
	var back: Variant = JSON.parse_string(JSON.stringify(d))
	assert_true(back is Dictionary)


func test_from_dict_round_trip_through_json() -> void:
	var r: RollResult = _sample()
	var json: String = JSON.stringify(r.to_dict())
	var back: RollResult = RollResult.from_dict(JsonUtil.as_dict(JSON.parse_string(json)))
	assert_eq(back.ball_id, r.ball_id)
	assert_eq(back.thrown, true)
	assert_almost_eq(back.power, 0.5, 0.001)
	assert_eq(back.start_hex, Vector2i(1, 2))
	assert_eq(back.end_hex, Vector2i(4, 2))
	assert_eq(back.end_area, BallWorld.Area.STRIP as int)
	assert_eq(back.strip_entered, 1)
	assert_eq(back.collisions, PackedStringArray(["JO1-002#3"]))
	assert_eq(back.cores_picked, PackedStringArray(["core:2"]))
	assert_almost_eq(back.duration, 2.25, 0.001)
	assert_eq(back.path.size(), 3)
	assert_almost_eq(back.path[2].z, 4.0, 0.01)


func test_from_dict_tolerates_missing_keys() -> void:
	var r: RollResult = RollResult.from_dict({"ball": "x"})
	assert_eq(r.ball_id, "x")
	assert_eq(r.strip_entered, -1)
	assert_false(r.ring_out)
	assert_eq(r.path.size(), 0)
