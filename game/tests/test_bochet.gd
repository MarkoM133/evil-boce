extends GutTest
## Evil Bochet (Bochet): where a hand holds its edge when things lie near it, when a hand drums on the
## edge, when a ball it brings back waits over its spot, and where the eyes stand so that the camera sees
## them past the table.

## Half a table: 14 across, 20 along (strips included).
const EXT := Vector2(14.0, 20.0)


func test_a_hand_holds_home_while_nothing_is_near() -> void:
	assert_eq(Bochet.free_spot(12.0, PackedFloat32Array(), 8.4, 17.2), 12.0)
	assert_eq(Bochet.free_spot(12.0, PackedFloat32Array([2.0, 16.0]), 8.4, 17.2), 12.0, "far enough on both sides")


func test_a_hand_walks_to_the_nearest_free_stretch_and_keeps_to_its_walk() -> void:
	# A ball under the hand: up first at each distance, CLEAR away at least.
	assert_almost_eq(Bochet.free_spot(12.0, PackedFloat32Array([12.0]), 8.4, 17.2), 15.2, 0.001)
	# No room above within the walk: the other way.
	assert_almost_eq(Bochet.free_spot(12.0, PackedFloat32Array([12.0, 16.5]), 8.4, 17.2), 8.8, 0.001)
	var z: float = Bochet.free_spot(12.0, PackedFloat32Array([12.0]), 8.4, 13.0)
	assert_true(z == INF or (z >= 8.4 and z <= 13.0), "never outside its walk")


func test_no_room_anywhere_sends_the_hand_off_the_top() -> void:
	assert_eq(Bochet.free_spot(12.0, PackedFloat32Array([9.0, 12.0, 15.0]), 8.4, 17.2), INF)


func test_a_hand_on_its_way_home_does_not_walk_past_a_ball() -> void:
	# Out of the way at 15.6, home at 12, a ball at 13 in between: it waits as near home as its stretch allows.
	assert_almost_eq(Bochet.reach_spot(15.6, 12.0, PackedFloat32Array([13.0]), 8.4, 17.2), 16.0, 0.001)
	# The ball gone: straight home.
	assert_almost_eq(Bochet.reach_spot(15.6, 12.0, PackedFloat32Array(), 8.4, 17.2), 12.0, 0.001)
	# Something comes onto it: out of the way to the nearest side.
	assert_almost_eq(Bochet.reach_spot(12.0, 12.0, PackedFloat32Array([12.5]), 8.4, 17.2), 9.2, 0.001)


func test_the_claws_over_the_rim_keep_off_balls_by_the_rim() -> void:
	assert_true(Bochet.clear_of(12.0, PackedFloat32Array([15.0]), Bochet.RIM_CLEAR))
	assert_false(Bochet.clear_of(12.0, PackedFloat32Array([13.5]), Bochet.RIM_CLEAR))
	assert_false(Bochet.path_clear(9.0, 15.0, PackedFloat32Array([12.0]), Bochet.RIM_CLEAR), "a ball on the way")
	assert_true(Bochet.path_clear(9.0, 12.0, PackedFloat32Array([16.0]), Bochet.RIM_CLEAR))


func test_a_hand_drums_only_while_the_clock_runs_low() -> void:
	assert_eq(Bochet.drum_every(INF), 0.0, "no timer")
	assert_eq(Bochet.drum_every(9.0), 0.0)
	assert_eq(Bochet.drum_every(4.0), 0.9)
	assert_eq(Bochet.drum_every(1.5), 0.45, "twice as often at the end")
	assert_eq(Bochet.drum_every(0.0), 0.0, "time is up")


func test_a_ball_is_held_over_its_spot_while_its_ring_out_is_being_paid() -> void:
	var s := GameState.new()
	s.pending = [{"type": RulesEngine.DECISION_DAMAGE, "player": 0, "by": "ring_out", "amount": 1,
		"targets": ["p0:h1"], "ring_out": true}]
	assert_true(Bochet.ring_pending(s, "p0:h1"))
	assert_false(Bochet.ring_pending(s, "p0:h2"), "another ball is not waiting")
	s.pending = [{"type": RulesEngine.DECISION_DAMAGE, "player": 0, "by": "battle", "amount": 1,
		"targets": ["p0:h1"], "ring_out": false}]
	assert_false(Bochet.ring_pending(s, "p0:h1"), "damage from a battle is not the ring-out's")
	s.pending = []
	assert_false(Bochet.ring_pending(s, "p0:h1"))


func test_the_eyes_stand_further_out_as_the_view_turns_away() -> void:
	assert_almost_eq(Bochet.eyes_out(Vector3(0, 30, 50)), Bochet.EYES_NEAR, 0.001, "home view")
	assert_almost_eq(Bochet.eyes_out(Vector3(50, 30, 0)), Bochet.EYES_TURNED, 0.001, "from the side")


func test_the_eyes_are_seen_from_their_own_side_not_through_the_table() -> void:
	var at := Vector3(0, Bochet.EYES_DOWN, EXT.y + Bochet.EYES_NEAR)
	assert_true(Bochet.eyes_seen(at, Vector3(0, 40, 50), EXT), "from behind them, over the near edge")
	assert_false(Bochet.eyes_seen(at, Vector3(0, 40, -50), EXT), "from the far side the table is in the way")
	assert_false(Bochet.eyes_seen(Vector3(0, Bochet.EYES_DOWN, EXT.y - 2.0), Vector3(0, 40, 50), EXT), "never under the table")
