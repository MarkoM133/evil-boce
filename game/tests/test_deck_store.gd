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


## Code review 2026-11-13: the file name is Card Studio's slug for every accented letter, never a name Windows
## or Card Studio keeps for itself, and a second deck of the same slug has a name that makes its own slug.
func test_slugs_as_card_studio_makes_them_and_no_reserved_names() -> void:
	assert_eq(DeckStore.slug("Éclair Über"), "eclair-uber")
	assert_eq(DeckStore.slug("ŽŠĆČĐ žšćčđ Ñandú Ångström"), "zsccd-zsccd-nandu-angstrom")
	assert_eq(DeckStore.slug("Con"), "deck-con")
	assert_eq(DeckStore.slug("AUX"), "deck-aux")
	assert_eq(DeckStore.slug("New"), "deck-new", "Card Studio's address of the empty deck")
	assert_eq(DeckStore.slug("Console"), "console", "only the whole name")
	assert_eq(DeckStore.file_name("Nul"), "deck-nul.json")
	assert_eq(DeckStore.file_name("New"), "new.json", "fine on this computer")


func test_a_second_deck_of_the_same_slug_gets_its_own_name() -> void:
	var heroes := PackedStringArray(["OP1-001", "OP1-002", "OP1-005"])
	var cards: Dictionary = {"OP1-010": 4}
	DeckStore.save_shared(_root, "Twins", heroes, cards, 17)
	var b: String = DeckStore.save_shared(_root, "Twins", heroes, cards, 17)
	var c: String = DeckStore.save_shared(_root, "twins!", heroes, cards, 17)
	assert_eq(b, _root.path_join("decks/twins-2.json"))
	assert_eq(c, _root.path_join("decks/twins-3.json"))
	var second: Dictionary = JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(b)))
	assert_eq(str(second["name"]), "Twins (2)")
	assert_eq(DeckStore.slug(str(second["name"])), "twins-2", "its name's slug is its file")
	# A name as long as a slug may be still gets a file of its own.
	var long_name: String = "x".repeat(80)
	var l1: String = DeckStore.save_shared(_root, long_name, heroes, cards, 17)
	var l2: String = DeckStore.save_shared(_root, long_name, heroes, cards, 17)
	assert_ne(l1, l2)
	assert_true(FileAccess.file_exists(l1) and FileAccess.file_exists(l2))
