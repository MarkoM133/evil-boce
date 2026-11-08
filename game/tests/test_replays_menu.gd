extends GutTest
## How the Replays screen sorts matches: which filter takes one, and under which day it stands.

const NOON: int = 1794139200 # 2026-11-08 12:00 UTC


func test_kinds() -> void:
	assert_eq(ReplaysMenu.kind_of({"names": ["Marko", "Bot (Easy)"], "bots": [false, true]}), "bot")
	assert_eq(ReplaysMenu.kind_of({"names": ["Player 1", "Bot (Hard)"]}), "bot", "an old replay has no bot flag")
	assert_eq(ReplaysMenu.kind_of({"names": ["Player 1", "Player 2"], "bots": [false, false]}), "local")
	assert_eq(ReplaysMenu.kind_of({"names": ["Marko", "Tarik"], "bots": [false, false]}), "online")


func test_filters() -> void:
	var online: Dictionary = {"names": ["Marko", "Tarik"], "bots": [false, false], "finished": true}
	var stopped: Dictionary = {"names": ["Marko", "Bot (Easy)"], "bots": [false, true], "finished": false}
	assert_true(ReplaysMenu.matches(online, ""))
	assert_true(ReplaysMenu.matches(online, "online"))
	assert_false(ReplaysMenu.matches(online, "bot"))
	assert_false(ReplaysMenu.matches(online, "open"))
	assert_true(ReplaysMenu.matches(stopped, "open"))
	assert_true(ReplaysMenu.matches(stopped, "bot"))


func test_days() -> void:
	assert_eq(ReplaysMenu.day_label(NOON - 3600, NOON, 0), "TODAY")
	assert_eq(ReplaysMenu.day_label(NOON - 86400, NOON, 0), "YESTERDAY")
	assert_eq(ReplaysMenu.day_label(NOON - 86400 * 7, NOON, 0), "1 NOV")
	assert_eq(ReplaysMenu.day_label(NOON - 86400 * 365, NOON, 0), "8 NOV 2025")


func test_a_day_ends_at_local_midnight() -> void:
	var late: int = NOON - 13 * 3600 # 2026-11-07 23:00 UTC, past midnight an hour ahead of UTC
	assert_eq(ReplaysMenu.day_label(late, NOON, 0), "YESTERDAY")
	assert_eq(ReplaysMenu.day_label(late, NOON, 60), "TODAY")
