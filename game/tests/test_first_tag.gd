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


func test_the_same_answers_as_the_app() -> void:
	for c: Variant in JsonUtil.as_array(fx["cases"]):
		var d: Dictionary = JsonUtil.as_dict(c)
		var v: Dictionary = FirstTag.deck_verdict(catalog, catalog.get_card(str(d["card"])), _cards(d["heroes"]), _cards(d.get("evolutions", [])))
		assert_eq(JsonUtil.as_bool(v["ok"]), JsonUtil.as_bool(d["ok"]), "%s: %s (%s)" % [d["card"], d["why"], v["why"]])
		if d.has("needs"):
			assert_eq(JsonUtil.as_strings(v["needs"]), PackedStringArray([str(d["needs"])]), str(d["card"]))
