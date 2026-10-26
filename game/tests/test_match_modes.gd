extends GutTest
## Game modes (GDD 13) as presets of MatchSettings: what each sets, how a mix is recognised,
## and the random map drawn at the start.


func test_presets_set_their_rules_and_name() -> void:
	var fast: MatchSettings = MatchSettings.preset("fast")
	assert_eq(fast.mode, "fast")
	assert_eq(fast.timer_seconds, 30)
	assert_eq(fast.deck_size, 20)
	assert_eq(fast.stages_to_win, 2)
	assert_eq(fast.map_size, 17)
	var chaos: MatchSettings = MatchSettings.preset("chaos")
	assert_eq(chaos.mode, "chaos")
	assert_false(chaos.manual_setup)
	assert_eq(chaos.map_size, MatchSettings.MAP_RANDOM)
	assert_eq(MatchSettings.preset("standard").to_dict(), MatchSettings.standard().to_dict())
	assert_eq(MatchSettings.preset("nope").mode, "custom")


func test_a_mix_is_custom_and_the_map_does_not_count() -> void:
	var s: MatchSettings = MatchSettings.preset("fast")
	assert_eq(s.mode_of(), "fast")
	s.map_size = 23
	assert_eq(s.mode_of(), "fast", "another map keeps the mode")
	s.timer_seconds = 60
	assert_eq(s.mode_of(), "custom")
	var back: MatchSettings = MatchSettings.from_dict(s.to_dict())
	assert_eq(back.mode, "fast", "the name travels as it was set")
	assert_eq(back.timer_seconds, 60)


func test_a_random_map_is_drawn_once_at_the_start() -> void:
	var s: MatchSettings = MatchSettings.preset("chaos")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	s.resolve_map(rng, GameSettings.MAP_SIZES)
	assert_true(GameSettings.MAP_SIZES.has(s.map_size))
	var picked: int = s.map_size
	s.resolve_map(rng, GameSettings.MAP_SIZES)
	assert_eq(s.map_size, picked, "a drawn map stays")
