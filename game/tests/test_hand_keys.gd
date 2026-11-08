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
