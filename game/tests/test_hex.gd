extends GutTest


func test_distance() -> void:
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(0, 0)), 0)
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(3, 0)), 3)
	assert_eq(Hex.distance(Vector2i(0, 0), Vector2i(2, -3)), 3)
	assert_eq(Hex.distance(Vector2i(-1, 2), Vector2i(2, -1)), 3)


func test_neighbours_are_one_step_away() -> void:
	for n: Vector2i in Hex.neighbors(Vector2i(4, -2)):
		assert_eq(Hex.distance(n, Vector2i(4, -2)), 1)


func test_ring_and_spiral_sizes() -> void:
	assert_eq(Hex.ring(Vector2i.ZERO, 0).size(), 1)
	for r: int in [1, 2, 3, 5]:
		var ring: Array[Vector2i] = Hex.ring(Vector2i(2, 1), r)
		assert_eq(ring.size(), 6 * r)
		for a: Vector2i in ring:
			assert_eq(Hex.distance(a, Vector2i(2, 1)), r)
	assert_eq(Hex.spiral(Vector2i.ZERO, 1).size(), 7)
	assert_eq(Hex.spiral(Vector2i.ZERO, 3).size(), 37)


func test_world_round_trip() -> void:
	for a: Vector2i in Hex.spiral(Vector2i(1, -1), 4):
		var p: Vector2 = Hex.to_world(a, 1.3)
		assert_eq(Hex.from_world(p, 1.3), a)
		# A point just inside the hex still maps to it.
		assert_eq(Hex.from_world(p + Vector2(0.5, 0.3), 1.3), a)


func test_direction_angles() -> void:
	for i: int in 6:
		var p: Vector2 = Hex.to_world(Hex.DIRECTIONS[i], 1.0)
		assert_almost_eq(angle_difference(p.angle(), deg_to_rad(60.0 * i)), 0.0, 0.0001)


func test_offset_round_trip() -> void:
	for row: int in range(-3, 5):
		for col: int in range(-3, 5):
			var a: Vector2i = Hex.offset_to_axial(col, row)
			assert_eq(Hex.axial_to_offset(a), Vector2i(col, row))
