extends GutTest
## Sounds come from files in data/audio/ named after what they are for (Marko 2026-11-15): variations,
## tuning, the music's fallback and which match events sound.

var root: String


func before_all() -> void:
	root = OS.get_user_data_dir().path_join("gut_temp_directory/sound_root")
	for sub: String in ["sfx", "music"]:
		DirAccess.make_dir_recursive_absolute(root.path_join("data/audio").path_join(sub))
	# Real (tiny) wav files: the music test plays them.
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 8000
	var pcm := PackedByteArray()
	pcm.resize(16000 * 2)
	wav.data = pcm
	for f: String in ["sfx/ko.wav", "sfx/ko_2.wav", "sfx/Bump_Ball-3.wav", "music/match.wav", "music/match_op1.wav"]:
		wav.save_to_wav(root.path_join("data/audio").path_join(f))
	var note := FileAccess.open(root.path_join("data/audio/sfx/notes.txt"), FileAccess.WRITE)
	note.store_string("x")
	note.close()
	var tune := FileAccess.open(root.path_join("data/audio/sounds.json"), FileAccess.WRITE)
	tune.store_string('{"sfx": {"ko": {"volume": -3, "cooldown": 0.5}}}')
	tune.close()
	Sound.root_override = root


func after_all() -> void:
	Sound.root_override = ""


func test_a_file_name_is_the_sound_and_numbers_are_variations() -> void:
	assert_eq(Sound._key_of("ko"), "ko")
	assert_eq(Sound._key_of("ko_2"), "ko")
	assert_eq(Sound._key_of("Bump_Ball-3"), "bump_ball")
	assert_eq(Sound._key_of("match_op1"), "match_op1", "a set code is not a variation number")
	var s := Sound.new()
	s._scan()
	assert_eq(JsonUtil.as_array(s._files["sfx/ko"]).size(), 2, "ko and ko_2")
	assert_true(s._files.has("sfx/bump_ball"))
	assert_false(s._files.has("sfx/notes"), "only ogg, wav and mp3")
	assert_eq(s._setting("ko", "volume", 0.0), -3.0, "sounds.json tunes a sound")
	assert_eq(s._setting("ui_click", "volume", 0.0), -6.0, "the built-in default")
	assert_eq(s._setting("nothing", "volume", 0.0), 0.0)
	s.free()


func test_the_match_music_falls_back_to_the_plain_match() -> void:
	var s := Sound.new()
	s._scan()
	assert_true(s._files.has("music/match_op1"))
	assert_true(s._files.has("music/match"))
	assert_false(s._files.has("music/match_jo1"), "JoJo has no music of its own: match is played")
	s.free()


func test_match_events_and_their_sounds() -> void:
	var log: Array[Dictionary] = [
		{"type": "damage"}, {"type": "hand_damage"}, {"type": "ko"}, {"type": "moved"},
		{"type": "match_end", "winner": 1},
	]
	assert_eq(Sound.log_keys(log, 1), ["damage", "ko", "win"] as Array[String], "each sound once; moving is silent")
	assert_eq(Sound.log_keys([{"type": "match_end", "winner": 0}] as Array[Dictionary], 1), ["lose"] as Array[String])
	assert_eq(Sound.log_keys([{"type": "match_end", "winner": -1}] as Array[Dictionary], 1), ["tie"] as Array[String], "a draw is tie: draw is a card drawn")
	var many: Array[Dictionary] = [{"type": "damage"}, {"type": "heal"}, {"type": "ko"}, {"type": "draw"}, {"type": "combo"}, {"type": "token"}]
	assert_eq(Sound.log_keys(many, 0).size(), Sound.LOG_BURST, "a replay jumping ahead stays quiet enough")


func test_a_battle_without_music_keeps_the_match_music() -> void:
	var s := Sound.new()
	s._scan()
	add_child_autofree(s)
	s._music_to("match")
	assert_eq(s._music_key, "match")
	s._music_to("battle_op1", true)
	assert_eq(s._music_key, "match", "no battle file: the match music goes on")
	s._music_to("match_op1")
	assert_eq(s._music_key, "match_op1", "a set's own music")
	s._music_to("match_jo1")
	assert_eq(s._music_key, "match", "no JoJo music: the plain match's")
	s._music_to("battle", false)
	assert_eq(s._music_key, "", "without keep, nothing for it stops the music")
