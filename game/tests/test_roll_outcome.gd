extends GutTest


func _result(id: String, thrown: bool, end_hex: Vector2i) -> RollResult:
	var r := RollResult.new()
	r.ball_id = id
	r.thrown = thrown
	r.start_hex = Vector2i.ZERO
	r.end_hex = end_hex
	r.path = PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0)])
	r.duration = 1.0
	return r


func test_order_and_lookup() -> void:
	var o := RollOutcome.new()
	o.thrower = "a"
	o.add(_result("a", true, Vector2i(3, 0)))
	o.add(_result("b", false, Vector2i(5, 0)))
	assert_eq(o.moved_ids(), PackedStringArray(["a", "b"]))
	assert_eq(o.thrower_result().end_hex, Vector2i(3, 0))
	assert_null(o.result_for("zzz"))


func test_second_leg_merges_into_one_entry() -> void:
	var o := RollOutcome.new()
	o.thrower = "a"
	var first: RollResult = _result("b", false, Vector2i(2, 0))
	first.collisions.append("a")
	o.add(first)
	var second: RollResult = _result("b", false, Vector2i(4, 0))
	second.start_hex = Vector2i(2, 0)
	second.collisions.append("c")
	o.add(second)
	assert_eq(o.results.size(), 1)
	var b: RollResult = o.result_for("b")
	assert_eq(b.start_hex, Vector2i.ZERO)
	assert_eq(b.end_hex, Vector2i(4, 0))
	assert_eq(b.collisions, PackedStringArray(["a", "c"]))
	assert_eq(b.path.size(), 4)
	assert_almost_eq(b.duration, 2.0, 0.001)


func test_json_round_trip() -> void:
	var o := RollOutcome.new()
	o.thrower = "a"
	o.duration = 3.5
	o.add(_result("a", true, Vector2i(3, 0)))
	o.add(_result("b", false, Vector2i(5, -1)))
	var back: RollOutcome = RollOutcome.from_dict(JsonUtil.as_dict(JSON.parse_string(JSON.stringify(o.to_dict()))))
	assert_eq(back.thrower, "a")
	assert_almost_eq(back.duration, 3.5, 0.001)
	assert_eq(back.moved_ids(), PackedStringArray(["a", "b"]))
	assert_eq(back.result_for("b").end_hex, Vector2i(5, -1))
	assert_true(back.thrower_result().thrown)
