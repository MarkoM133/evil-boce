extends GutTest
## Decks imported from a code go into the shared folder as the web app writes them (Marko 2026-11-11, GDD 7).

var _root: String = ""


func before_each() -> void:
	_root = OS.get_user_data_dir().path_join("test_deck_store_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(_root)


func after_each() -> void:
	var dir: String = _root.path_join("decks")
	if DirAccess.dir_exists_absolute(dir):
		for f: String in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(_root)


func test_the_file_name_is_the_web_apps_slug() -> void:
	assert_eq(DeckStore.slug("Luffy & Zoro Aggro!"), "luffy-zoro-aggro")
	assert_eq(DeckStore.slug("Šešir Čaćkalica Đ"), "sesir-cackalica-d")
	assert_eq(DeckStore.slug("  --  "), "deck")
	assert_eq(DeckStore.slug("x".repeat(80)).length(), 60)


func test_an_import_goes_into_the_shared_decks_and_never_over_one() -> void:
	var heroes := PackedStringArray(["OP1-001", "OP1-002", "OP1-005"])
	var cards: Dictionary = {"OP1-010": 4}
	var a: String = DeckStore.save_shared(_root, "Straw Hats", heroes, cards, 17)
	assert_eq(a, _root.path_join("decks/straw-hats.json"))
	var d: Dictionary = JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(a)))
	assert_eq(str(d["name"]), "Straw Hats")
	assert_eq(JsonUtil.as_int(d["rev"]), 1)
	assert_eq(JsonUtil.as_int(d["catalogVersion"]), 17)
	var b: String = DeckStore.save_shared(_root, "Straw hats", heroes, cards, 17)
	assert_eq(b, _root.path_join("decks/straw-hats-2.json"), "same slug: a new file")
	var all: Array[Dictionary] = DeckStore.load_all(_root)
	var shared: int = 0
	for x: Dictionary in all:
		if not JsonUtil.as_bool(x["local"]):
			shared += 1
	assert_eq(shared, 2)
	assert_eq(DeckStore.save_shared("", "X", heroes, cards, 1), "", "no folder, no file")
