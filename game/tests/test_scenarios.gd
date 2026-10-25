extends GutTest
## Runs every JSON scenario in tests/scenarios/ through the rules engine. A scenario is
## {"name": ..., "steps": [...]}; the step kinds are listed in docs/rules.md.

const SCENARIO_DIR: String = "res://tests/scenarios"
const FIXTURE: String = "res://tests/fixtures/cards.json"
const MAX_PASSES: int = 16

var catalog: CardCatalog
var engine: RulesEngine
var state: GameState


func before_all() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string(FIXTURE))
	engine = RulesEngine.new(catalog)


func test_fixture_loaded() -> void:
	assert_true(catalog.has("TA-001"))
	assert_eq(catalog.get_card("TS-001").terrain, Terrain.Type.ICE)
	assert_eq(catalog.of_type("Core").size(), 6, "placeholder cores")


func test_scenarios() -> void:
	var files: PackedStringArray = DirAccess.get_files_at(SCENARIO_DIR)
	files.sort()
	var count: int = 0
	for f: String in files:
		if not f.ends_with(".json"):
			continue
		count += 1
		_run_scenario(SCENARIO_DIR.path_join(f))
	assert_true(count > 0, "found scenarios")


func _run_scenario(path: String) -> void:
	var doc: Dictionary = JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	var name: String = str(doc.get("name", path.get_file()))
	state = null
	var steps: Array = JsonUtil.as_array(doc.get("steps", []))
	for i: int in steps.size():
		var step: Dictionary = JsonUtil.as_dict(steps[i])
		var tag: String = "%s step %d" % [name, i + 1]
		if step.has("setup"):
			_setup(JsonUtil.as_dict(step["setup"]))
		elif step.has("set"):
			_set_paths(JsonUtil.as_dict(step["set"]))
		elif step.has("move"):
			var m: Move = Move.from_dict(JsonUtil.as_dict(step["move"]))
			var err: String = engine.apply(state, m)
			if step.has("error"):
				var want: String = str(step["error"])
				assert_true(err.contains(want), "%s: expected refusal containing \"%s\", got \"%s\"" % [tag, want, err])
			else:
				assert_eq(err, "", "%s: move %s refused: %s" % [tag, JSON.stringify(step["move"]), err])
		elif step.has("roll"):
			var o: RollOutcome = RollOutcome.from_dict(JsonUtil.as_dict(step["roll"]))
			var err: String = engine.apply_roll(state, o)
			assert_eq(err, "", "%s: roll refused: %s" % [tag, err])
		elif step.has("pass_round"):
			var n: int = 0
			var phase: String = state.phase
			var battle: int = state.battle_index
			while not state.round_over and state.pending.is_empty() and n < MAX_PASSES \
					and state.phase == phase and state.battle_index == battle:
				var err: String = engine.apply(state, Move.make(Move.PASS, state.to_act))
				assert_eq(err, "", "%s: pass by %d refused: %s" % [tag, state.to_act, err])
				if not err.is_empty():
					break
				n += 1
		elif step.has("expect"):
			_expect(JsonUtil.as_dict(step["expect"]), tag)
		else:
			fail_test("%s: unknown step %s" % [tag, JSON.stringify(step)])


func _setup(opts: Dictionary) -> void:
	var settings: MatchSettings = MatchSettings.from_dict(JsonUtil.as_dict(opts.get("settings", {})))
	if not opts.has("settings") or not JsonUtil.as_dict(opts["settings"]).has("manual_setup"):
		settings.manual_setup = false
	var decks: Array = JsonUtil.as_array(opts.get("decks", []))
	if decks.is_empty():
		decks = default_decks()
	state = engine.start_match(settings, decks, JsonUtil.as_int(opts.get("seed", 1), 1))


static func default_decks() -> Array:
	var cards: Dictionary = {"TX-010": 20, "TX-011": 20}
	return [
		{"name": "A", "heroes": ["TA-001", "TA-002", "TA-003"], "cards": cards,
			"stages": ["TS-001", "TS-002", "TS-003"],
			"cores": ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]},
		{"name": "B", "heroes": ["TB-001", "TB-002", "TB-003"], "cards": cards,
			"stages": ["TS-004", "TS-005", "TS-006"],
			"cores": ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]},
	]


## Rewrites parts of the state through its JSON form: {"heroes.p0:TA-001.hex": [4, 8], ...}.
func _set_paths(changes: Dictionary) -> void:
	var d: Dictionary = state.to_dict()
	for path: Variant in changes:
		var keys: PackedStringArray = str(path).split(".")
		var node: Variant = d
		for i: int in keys.size() - 1:
			var cur: Dictionary = node
			if not cur.has(keys[i]):
				cur[keys[i]] = {}
			node = cur[keys[i]]
		var leaf: Dictionary = node
		leaf[keys[keys.size() - 1]] = changes[path]
	state = GameState.from_dict(d)


func _expect(checks: Dictionary, tag: String) -> void:
	var d: Dictionary = state.to_dict()
	for path: Variant in checks:
		var got: Variant = _lookup(d, str(path))
		var want: Variant = checks[path]
		assert_true(_same(got, want), "%s: %s is %s, expected %s" % [tag, path, JSON.stringify(got), JSON.stringify(want)])


static func _lookup(d: Dictionary, path: String) -> Variant:
	var node: Variant = d
	for key: String in path.split("."):
		if node is Dictionary:
			var cur: Dictionary = node
			if not cur.has(key):
				return null
			node = cur[key]
		elif node is Array:
			var arr: Array = node
			if not key.is_valid_int() or key.to_int() >= arr.size():
				return null
			node = arr[key.to_int()]
		else:
			return null
	return node


## Loose comparison; an expected {"$size": n} or {"$has": x} checks an array's size or contents.
static func _same(a: Variant, b: Variant) -> bool:
	if b is Dictionary and a is Array:
		var want: Dictionary = b
		var arr: Array = a
		if want.has("$size"):
			return arr.size() == JsonUtil.as_int(want["$size"])
		if want.has("$has"):
			for v: Variant in arr:
				if _same(v, want["$has"]):
					return true
			return false
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(JsonUtil.as_float(a), JsonUtil.as_float(b))
	if a is Array and b is Array:
		var x: Array = a
		var y: Array = b
		if x.size() != y.size():
			return false
		for i: int in x.size():
			if not _same(x[i], y[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		var x: Dictionary = a
		var y: Dictionary = b
		for k: Variant in y:
			if not x.has(k) or not _same(x[k], y[k]):
				return false
		return true
	return str(a) == str(b)
