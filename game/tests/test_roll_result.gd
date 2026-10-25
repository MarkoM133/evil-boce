extends GutTest


func test_lengths_and_dict() -> void:
	var r := RollResult.new()
	r.ball_id = "OP1-001#1"
	r.thrown = true
	r.power = 0.5
	r.start_hex = Vector2i(1, 2)
	r.end_hex = Vector2i(4, 2)
	r.path = PackedVector3Array([Vector3(0, 0.6, 0), Vector3(3, 0.6, 0), Vector3(3, 0.6, 4)])
	r.collisions.append("JO1-002#3")
	assert_almost_eq(r.path_length(), 7.0, 0.0001)
	assert_almost_eq(r.displacement(), 5.0, 0.0001)
	var d: Dictionary = r.to_dict()
	assert_eq(d["ball"], "OP1-001#1")
	assert_eq(d["end_hex"], [4, 2])
	assert_eq(d["collisions"], ["JO1-002#3"])
	# Must survive a JSON round trip (replays, network).
	var back: Variant = JSON.parse_string(JSON.stringify(d))
	assert_true(back is Dictionary)
