extends GutTest
## How the bar at the top of a battle splits (BattleTug.share_of).


func test_level_sits_on_the_middle() -> void:
	assert_eq(BattleTug.share_of(4000, 4000), 0.5)
	assert_eq(BattleTug.share_of(0, 0), 0.5)


func test_the_bar_follows_the_totals() -> void:
	assert_almost_eq(BattleTug.share_of(6000, 4000), 0.6, 0.001)
	assert_almost_eq(BattleTug.share_of(4000, 6000), 0.4, 0.001)


func test_the_side_behind_keeps_room_for_its_total_and_the_mark() -> void:
	assert_eq(BattleTug.share_of(9000, 1000), 1.0 - BattleTug.MIN_SHARE)
	assert_eq(BattleTug.share_of(1000, 9000), BattleTug.MIN_SHARE)
	assert_eq(BattleTug.share_of(0, 3000), BattleTug.MIN_SHARE)
