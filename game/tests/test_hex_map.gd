extends GutTest


func test_cells_and_contains() -> void:
	var m := HexMap.new(17)
	assert_eq(m.cells().size(), 17 * 17)
	for a: Vector2i in m.cells():
		assert_true(m.contains(a))
	assert_false(m.contains(Hex.offset_to_axial(-1, 3)))
	assert_false(m.contains(Hex.offset_to_axial(17, 3)))
	assert_false(m.contains(Hex.offset_to_axial(4, 17)))


func test_map_is_centred() -> void:
	for n: int in [15, 17, 23]:
		var m := HexMap.new(n)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for a: Vector2i in m.cells():
			lo = lo.min(m.to_world(a))
			hi = hi.max(m.to_world(a))
		assert_almost_eq(lo.x, -hi.x, 0.001)
		assert_almost_eq(lo.y, -hi.y, 0.001)


func test_world_round_trip_on_map() -> void:
	var m := HexMap.new(15, 1.0)
	for a: Vector2i in m.cells():
		assert_eq(m.from_world(m.to_world(a)), a)


func test_footprint() -> void:
	var m := HexMap.new(17)
	assert_eq(m.footprint(m.center_cell(), false).size(), 1)
	assert_eq(m.footprint(m.center_cell(), true).size(), 7)


func test_range_counts_from_outer_hexes() -> void:
	var m := HexMap.new(23)
	var c: Vector2i = m.center_cell()
	# Small ball, range 2: the 18 hexes around it.
	assert_eq(m.range_cells(c, false, 2).size(), 6 + 12)
	# Big ball covers 7; range 1 is the next ring (18 hexes).
	var big: Array[Vector2i] = m.range_cells(c, true, 1)
	assert_eq(big.size(), 12)
	for a: Vector2i in big:
		assert_eq(Hex.distance(a, c), 2)
	assert_eq(m.range_cells(c, false, 0).size(), 0)


func test_range_is_clipped_to_map() -> void:
	var m := HexMap.new(15)
	var corner: Vector2i = Hex.offset_to_axial(0, 0)
	var cells: Array[Vector2i] = m.range_cells(corner, false, 3)
	assert_true(cells.size() < 36)
	for a: Vector2i in cells:
		assert_true(m.contains(a))
