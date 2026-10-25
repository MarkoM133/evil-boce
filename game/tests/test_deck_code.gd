extends GutTest

var catalog: CardCatalog


func before_all() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string("res://tests/fixtures/cards.json"))


static func _ok(d: Dictionary) -> bool:
	return JsonUtil.as_bool(d["ok"])


func test_decode_and_encode_round_trip() -> void:
	var d: Dictionary = DeckCode.decode(" EB1|v6|TA-001,TA-002,TA-003|TX-010*4,TX-011*2,TX-010*1 ")
	assert_true(_ok(d), str(d["error"]))
	assert_eq(JsonUtil.as_int(d["version"]), 6)
	assert_eq(JsonUtil.as_strings(d["heroes"]), PackedStringArray(["TA-001", "TA-002", "TA-003"]))
	var cards: Dictionary = d["cards"]
	assert_eq(JsonUtil.as_int(cards["TX-010"]), 5, "repeated ids add up")
	assert_eq(JsonUtil.as_int(cards["TX-011"]), 2)
	var code: String = DeckCode.encode(JsonUtil.as_strings(d["heroes"]), cards, 6)
	assert_eq(code, "EB1|v6|TA-001,TA-002,TA-003|TX-010*5,TX-011*2")


func test_encode_sorts_numerically() -> void:
	var code: String = DeckCode.encode(PackedStringArray(["TA-001"]), {"TX-010": 1, "TX-002": 1, "TX-0100": 1}, 1)
	assert_eq(code, "EB1|v1|TA-001|TX-002*1,TX-010*1,TX-0100*1")


func test_decode_rejects_bad_codes() -> void:
	assert_false(_ok(DeckCode.decode("XX1|v1||")))
	assert_false(_ok(DeckCode.decode("EB1|6|TA-001|")))
	assert_false(_ok(DeckCode.decode("EB1|v6|TA-001")))
	assert_false(_ok(DeckCode.decode("EB1|v6|TA-001|TX-010*x")))
	var empty: Dictionary = DeckCode.decode("EB1|v6||")
	assert_true(_ok(empty))
	assert_eq(JsonUtil.as_strings(empty["heroes"]).size(), 0)


func test_check_deck() -> void:
	var heroes := PackedStringArray(["TA-001", "TA-002", "TA-003"])
	var good: Dictionary = {"TA-040": 4, "TA-020": 4, "TA-030": 2, "TA-012": 2, "TX-011": 4, "TA-041": 4, "TA-042": 4,
		"TA-021": 4, "TA-022": 4, "TA-023": 4, "TA-031": 2, "TA-032": 2}
	assert_eq(DeckCode.check(catalog, heroes, good), PackedStringArray(), "a legal deck")
	var errs: PackedStringArray = DeckCode.check(catalog, PackedStringArray(["TA-001", "TA-001"]), {"TA-040": 5, "TB-012": 1, "TS-001": 1, "TB-050": 1})
	var text: String = "\n".join(errs)
	assert_true(text.contains("pick 3 heroes"), text)
	assert_true(text.contains("picked twice"), text)
	assert_true(text.contains("at most 4"), text)
	assert_true(text.contains("Evolution for a hero who isn't in the deck"), text)
	assert_true(text.contains("can't go in a deck"), text)
	assert_true(text.contains("not a color"), text)
	assert_true(text.contains("the deck needs 40"), text)
