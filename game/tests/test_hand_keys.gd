extends GutTest
## How a hand card is told apart from one rebuild of the hand to the next (MatchHud.hand_keys).


func test_copies_of_a_card_are_told_apart() -> void:
	assert_eq(MatchHud.hand_keys(0, PackedStringArray(["A", "B", "A"])), PackedStringArray(["0|A#0", "0|B#0", "0|A#1"]))


func test_playing_a_copy_loses_only_the_last_key() -> void:
	var before: PackedStringArray = MatchHud.hand_keys(1, PackedStringArray(["A", "A", "B"]))
	var after: PackedStringArray = MatchHud.hand_keys(1, PackedStringArray(["A", "B"]))
	assert_true(after.has(before[0]))
	assert_true(after.has(before[2]))
	assert_false(after.has(before[1]))


func test_the_copy_played_is_the_one_that_goes_missing() -> void:
	var before: Dictionary[String, Dictionary] = {"0|A#0": {"x": 10.0}, "0|A#1": {"x": 20.0}, "0|A#2": {"x": 30.0}, "0|B#0": {"x": 40.0}}
	MatchHud.played_copy_last(before, "0|A#0")
	assert_eq(JsonUtil.as_float(before["0|A#2"]["x"]), 10.0, "the left copy was played and leaves from the left")
	assert_eq(JsonUtil.as_float(before["0|A#0"]["x"]), 20.0)
	assert_eq(JsonUtil.as_float(before["0|A#1"]["x"]), 30.0)
	assert_eq(JsonUtil.as_float(before["0|B#0"]["x"]), 40.0)
