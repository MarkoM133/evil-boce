extends GutTest
## Settings that change how input reads: rebound keys. Works on an in-memory config.


func before_each() -> void:
	GameSettings.use_memory()


func after_all() -> void:
	# The next reader loads the real file again.
	GameSettings.in_memory = false
	GameSettings._cfg = null


func test_default_keys_read_as_themselves() -> void:
	assert_eq(GameSettings.logical_key(KEY_ESCAPE), KEY_ESCAPE)
	assert_eq(GameSettings.logical_key(KEY_SPACE), KEY_SPACE)
	assert_eq(GameSettings.logical_key(KEY_O), KEY_O)


func test_a_rebound_key_reads_as_the_default_and_frees_the_old_one() -> void:
	GameSettings.set_key("pass", KEY_ENTER)
	assert_eq(GameSettings.logical_key(KEY_ENTER), KEY_SPACE)
	assert_eq(GameSettings.logical_key(KEY_SPACE), KEY_NONE, "Space no longer passes")
	assert_eq(GameSettings.logical_key(KEY_ESCAPE), KEY_ESCAPE)
	GameSettings.reset_keys()
	assert_eq(GameSettings.logical_key(KEY_SPACE), KEY_SPACE)


func test_display_defaults() -> void:
	assert_false(GameSettings.fullscreen())
	assert_eq(GameSettings.resolution(), Vector2i(1600, 900))
	assert_eq(GameSettings.quality(), "medium")
	GameSettings.set_value("display", "quality", "ultra")
	assert_eq(GameSettings.quality(), "medium", "unknown values fall back")
	assert_almost_eq(GameSettings.volume("Music"), 0.8, 0.001)
