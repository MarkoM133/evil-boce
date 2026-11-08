extends GutTest


func test_default_resource_loads() -> void:
	var t: PhysicsTuning = PhysicsTuning.load_default()
	assert_not_null(t)
	assert_eq(t.radius_by_wt.size(), t.mass_by_wt.size())
	assert_eq(t.radius_by_wt.size(), t.full_power_hexes_by_wt.size())


func test_wt_lookup_clamps() -> void:
	var t := PhysicsTuning.new()
	assert_eq(t.radius(1), t.radius_by_wt[0])
	assert_eq(t.radius(9), t.radius_by_wt[t.radius_by_wt.size() - 1])
	assert_true(t.is_big(4))
	assert_false(t.is_big(3))


func test_small_balls_fit_one_hex() -> void:
	var t: PhysicsTuning = PhysicsTuning.load_default()
	var inradius: float = t.hex_size * Hex.SQRT3 * 0.5
	for wt: int in [1, 2, 3]:
		assert_true(t.radius(wt) <= inradius, "WT%d fits in one hex" % wt)


func test_launch_speed_matches_range() -> void:
	var t := PhysicsTuning.new()
	for wt: int in [1, 2, 3, 4]:
		var v: float = t.launch_speed(wt)
		var metres: float = v * v / (2.0 * t.deceleration)
		assert_almost_eq(metres / t.hex_spacing(), t.full_power_hexes(wt), 0.001)


func test_a_longer_way_to_rest_is_glided() -> void:
	var t: PhysicsTuning = PhysicsTuning.new()
	var hex: float = t.hex_spacing()
	assert_eq(t.snap_duration(0.0), t.snap_time, "the usual small settle")
	assert_eq(t.snap_duration(hex * 0.5), t.snap_time)
	assert_almost_eq(t.snap_duration(hex * 1.4), 1.4 * t.snap_time_per_hex, 0.001)
	assert_eq(t.snap_duration(hex * 3.0), t.snap_time_max, "never too long")
