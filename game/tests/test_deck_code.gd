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


func test_random_deck_keeps_the_leader_and_the_rules() -> void:
	var rng := RandomNumberGenerator.new()
	for h: CardDef in catalog.of_type("Hero"):
		rng.seed = h.id.hash()
		var d: Dictionary = DeckCode.random_deck(catalog, rng, h.id)
		var heroes: PackedStringArray = JsonUtil.as_strings(d["heroes"])
		assert_true(heroes.has(h.id), "leader %s is in the deck" % h.id)
		assert_eq(heroes.size(), DeckCode.HERO_COUNT)
		for e: String in DeckCode.check(catalog, heroes, JsonUtil.as_dict(d["cards"])):
			# Only a small pool may leave the deck short; colours and evolutions always fit.
			assert_string_contains(e, "the deck needs")


func test_a_card_with_a_hero_trait_needs_that_hero() -> void:
	var doc: Dictionary = {"version": 1, "cards": [
		{"id": "H-1", "name": "Alpha", "type": "Hero", "color": "Red"},
		{"id": "H-2", "name": "Echo", "type": "Hero", "color": "Red"},
		{"id": "H-3", "name": "Bravo", "type": "Hero", "color": "Blue"},
		{"id": "H-4", "name": "Charlie", "type": "Hero", "color": "Green"},
		{"id": "Q-1", "name": "Alpha Sword", "type": "Equipment", "color": "Red", "traits": ["Sword", "ALPHA"]},
		{"id": "Q-2", "name": "Any Sword", "type": "Equipment", "color": "Red", "traits": ["Sword"]},
	]}
	var cat: CardCatalog = CardCatalog.from_doc(doc)
	assert_eq(DeckCode.card_heroes(cat, cat.get_card("Q-1")), PackedStringArray(["Alpha"]))
	assert_true(DeckCode.card_heroes(cat, cat.get_card("Q-2")).is_empty())
	var cat2: CardCatalog = CardCatalog.from_doc({"version": 1, "cards": [
		{"id": "H-9", "name": "Zeta Prime", "type": "Hero", "color": "Red"},
		{"id": "A-9", "name": "Zeta Punch", "type": "Action", "color": "Red", "traits": ["zeta"]}]})
	assert_eq(DeckCode.card_heroes(cat2, cat2.get_card("A-9")), PackedStringArray(["Zeta Prime"]), "first word counts")
	var without: PackedStringArray = DeckCode.check(cat, PackedStringArray(["H-2", "H-3", "H-4"]), {"Q-1": 1})
	assert_true(Array(without).any(func(e: String) -> bool: return e.contains("only for Alpha")), str(without))
	var with_: PackedStringArray = DeckCode.check(cat, PackedStringArray(["H-1", "H-3", "H-4"]), {"Q-1": 1})
	assert_false(Array(with_).any(func(e: String) -> bool: return e.contains("only for")), str(with_))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var d: Dictionary = DeckCode.random_deck(cat, rng, "H-2")
	if not JsonUtil.as_strings(d["heroes"]).has("H-1"):
		assert_false(JsonUtil.as_dict(d["cards"]).has("Q-1"), "no Alpha, no Alpha Sword")
