extends GutTest
## Stages and cores a player brings (GDD 7): picks, random fill, checks.

var catalog: CardCatalog


func before_all() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string("res://tests/fixtures/cards.json"))


func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 4
	return r


func test_all_random_gives_three_stages_and_two_cores_of_each_kind() -> void:
	var out: Dictionary = Loadout.random().resolve(catalog, _rng())
	var stages: PackedStringArray = out["stages"]
	var cores: PackedStringArray = out["cores"]
	assert_eq(stages.size(), 3)
	assert_eq(cores.size(), 6)
	var kinds: Array[String] = []
	for id: String in cores:
		kinds.append(catalog.get_card(id).kind)
	assert_eq(kinds, ["Buff", "Buff", "Major", "Major", "Debuff", "Debuff"])
	assert_ne(stages[0], stages[1])


func test_picks_are_kept_and_random_fills_the_rest_without_repeats() -> void:
	var l := Loadout.new()
	l.stages[1] = "TS-004"
	l.cores[3] = "CR0-003"
	for i: int in 20:
		var r := RandomNumberGenerator.new()
		r.seed = i
		var out: Dictionary = l.resolve(catalog, r)
		var stages: PackedStringArray = out["stages"]
		assert_true(stages.has("TS-004"))
		assert_eq(stages.size(), 3)
		var cores: PackedStringArray = out["cores"]
		assert_true(cores.has("CR0-003"))
		var seen: Dictionary = {}
		for id: String in stages:
			seen[id] = true
		assert_eq(seen.size(), 3, "no stage twice")


func test_problems_name_doubles_and_wrong_kinds() -> void:
	var l := Loadout.new()
	assert_eq(l.problems(catalog).size(), 0)
	l.stages[0] = "TS-001"
	l.stages[2] = "TS-001"
	l.cores[0] = "CR0-005"
	var p: PackedStringArray = l.problems(catalog)
	assert_true(p.has("the same stage twice"))
	assert_eq(p.size(), 2, str(p))


func test_round_trip_through_a_dict() -> void:
	var l := Loadout.new()
	l.stages[2] = "TS-002"
	l.cores[5] = "CR0-006"
	var back: Loadout = Loadout.from_dict(l.to_dict())
	assert_eq(back.stages, l.stages)
	assert_eq(back.cores, l.cores)
