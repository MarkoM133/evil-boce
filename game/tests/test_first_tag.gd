extends GutTest
## The first tag rule on the cases the web app checks too (tests/fixtures/first_tag_cases.json):
## the game and the app must answer "may card X go with heroes Y" the same way.

var fx: Dictionary
var catalog: CardCatalog


func before_all() -> void:
	fx = JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/first_tag_cases.json")))
	catalog = CardCatalog.from_doc(fx, false)


func _cards(ids: Variant) -> Array[CardDef]:
	var out: Array[CardDef] = []
	for id: Variant in JsonUtil.as_array(ids):
		out.append(catalog.get_card(str(id)))
	return out


func test_the_kind_of_first_tag() -> void:
	for k: Variant in JsonUtil.as_array(fx["kinds"]):
		var d: Dictionary = JsonUtil.as_dict(k)
		var got: Dictionary = FirstTag.kind_of(catalog, catalog.get_card(str(d["card"])))
		assert_eq(str(got["kind"]), str(d["kind"]), str(d["card"]))
		if d.has("heroes"):
			assert_eq(JsonUtil.as_strings(got.get("heroes", [])), JsonUtil.as_strings(d["heroes"]), str(d["card"]))
		if d.has("trait"):
			assert_eq(str(got.get("trait", "")), str(d["trait"]), str(d["card"]))
		if d.has("traits"):
			assert_eq(JsonUtil.as_strings(got.get("traits", [])), JsonUtil.as_strings(d["traits"]), str(d["card"]))


func test_the_same_answers_as_the_app() -> void:
	for c: Variant in JsonUtil.as_array(fx["cases"]):
		var d: Dictionary = JsonUtil.as_dict(c)
		var v: Dictionary = FirstTag.deck_verdict(catalog, catalog.get_card(str(d["card"])), _cards(d["heroes"]), _cards(d.get("evolutions", [])))
		assert_eq(JsonUtil.as_bool(v["ok"]), JsonUtil.as_bool(d["ok"]), "%s: %s (%s)" % [d["card"], d["why"], v["why"]])
		if d.has("needs"):
			assert_eq(JsonUtil.as_strings(v["needs"]), PackedStringArray([str(d["needs"])]), str(d["card"]))
		if d.has("says"):
			assert_eq(str(v["why"]), str(d["says"]), str(d["card"]))


## "&" with traits in play (2026-11-15): the hero named, or the hero that carries one of the traits now.
func test_a_joined_tag_in_play() -> void:
	var delta: CardDef = catalog.get_card("H-DEL")
	var charlie: CardDef = catalog.get_card("H-CHA")
	var echo: CardDef = catalog.get_card("H-ECH")
	var evo: CardDef = catalog.get_card("E-DEL")
	var mix: CardDef = catalog.get_card("C-MIX")
	assert_true(JsonUtil.as_bool(FirstTag.play_verdict(catalog, mix, delta, delta)["ok"]), "Delta is named")
	assert_true(JsonUtil.as_bool(FirstTag.play_verdict(catalog, mix, charlie, charlie)["ok"]), "Charlie has Stand")
	var no: Dictionary = FirstTag.play_verdict(catalog, mix, echo, echo)
	assert_false(JsonUtil.as_bool(no["ok"]), "Echo is neither")
	assert_eq(str(no["why"]), "only for Delta, or Requires Stand")
	var two: CardDef = catalog.get_card("C-SS-N")
	assert_true(JsonUtil.as_bool(FirstTag.play_verdict(catalog, two, charlie, charlie)["ok"]), "Stand is one of the two")
	assert_eq(str(FirstTag.play_verdict(catalog, two, echo, echo)["why"]), "Requires Sword or Stand")
	var ag: CardDef = catalog.get_card("C-AG")
	assert_false(JsonUtil.as_bool(FirstTag.play_verdict(catalog, ag, delta, delta)["ok"]), "Delta before the evolution")
	assert_true(JsonUtil.as_bool(FirstTag.play_verdict(catalog, ag, delta, evo)["ok"]), "Delta evolved has Gear Second")
