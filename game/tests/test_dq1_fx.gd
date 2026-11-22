extends GutTest
## The fx words and rules that came with the DQ1 set (Marko 2026-11-22), each on a small card of its own written
## as card text, so the text parser is under test too.

var catalog: CardCatalog
var engine: RulesEngine

const ALPHA: String = "p0:TA-001"   # Red, {Haki}
const BRAVO: String = "p0:TA-002"   # Blue
const ECHO: String = "p1:TB-001"    # Red
const FOXTROT: String = "p1:TB-002" # Cyan

## Test cards on top of the fixtures.
const CARDS: Array = [
	{"id": "TD-001", "name": "Cinder", "type": "Hero", "color": "Cyan", "wt": 2, "stats": {"hp": 10, "dmg": 3, "pwr": 2000, "rng": 3, "kb": 2},
		"text": "Cinder ignores Terrain, except Ramp."},
	{"id": "TD-010", "name": "Scorch", "type": "Action", "color": "Red", "cost": 1, "traits": ["General"],
		"text": "Postroll Phase: The Terrain of a Stage your Hero stands on becomes Fire."},
]


func before_all() -> void:
	var doc: Dictionary = JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/cards.json")))
	var list: Array = JsonUtil.as_array(doc.get("cards", []))
	list.append_array(CARDS)
	doc["cards"] = list
	catalog = CardCatalog.from_doc(doc)
	engine = RulesEngine.new(catalog)


## Alpha (activated) and Echo (activated) on the map, far apart; the first stage of each player is placed and
## revealed, Alpha stands on player 1's. `third`: the third hero of player 2 (a test hero).
func _state(third: String = "TB-003") -> GameState:
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var decks: Array = [
		{"name": "A", "heroes": ["TA-001", "TA-002", "TA-003"], "cards": {"TX-010": 40}, "stages": ["TS-003", "TS-002", "TS-001"], "cores": []},
		{"name": "B", "heroes": ["TB-001", "TB-002", third], "cards": {"TX-010": 40}, "stages": ["TS-006", "TS-005", "TS-004"], "cores": []},
	]
	var s: GameState = engine.start_match(settings, decks, 3)
	s.active = {0: ALPHA, 1: ECHO}
	for st: StageState in s.stages:
		st.placed = false
	var plain: StageState = _stage(s, "TS-003")
	plain.placed = true
	plain.revealed = true
	plain.center = Hex.offset_to_axial(8, 10)
	_on_map(s, ALPHA, Hex.offset_to_axial(8, 10))
	_on_map(s, ECHO, Hex.offset_to_axial(8, 2))
	s.phase = GameState.PHASE_POSTROLL
	s.to_act = 0
	s.player(0).energy = 10
	s.player(1).energy = 10
	return s


func _stage(s: GameState, card: String) -> StageState:
	for st: StageState in s.stages:
		if st.card_id == card:
			return st
	return null


func _on_map(s: GameState, hero: String, hex: Vector2i) -> HeroState:
	var h: HeroState = s.hero(hero)
	h.zone = HeroState.ZONE_MAP
	h.hex = hex
	return h


## Plays the card from player `slot`'s hand (put there first); "" or why not.
func _play(s: GameState, slot: int, card: String, hero: String = "") -> String:
	s.player(slot).hand.append(card)
	s.to_act = slot
	var args: Dictionary = {"card": card}
	if not hero.is_empty():
		args["hero"] = hero
	return engine.apply(s, Move.make(Move.PLAY_CARD, slot, args))


func _fx_of(id: String) -> String:
	var c: CardDef = catalog.get_card(id)
	assert_eq(c.unparsed.size(), 0, "%s unparsed: %s" % [id, ", ".join(c.unparsed)])
	return c.fx


# --- Fire terrain ---------------------------------------------------------------------

func test_fire_terrain_reads() -> void:
	assert_eq(_fx_of("TD-001"), "PASSIVE: STATUS SELF IGNORE_TERRAIN")
	assert_eq(_fx_of("TD-010"), "POSTROLL: TERRAIN FIRE")
	assert_eq(Terrain.parse("Fire"), Terrain.Type.FIRE)


func test_a_card_turns_the_stage_under_the_hero_to_fire() -> void:
	var s: GameState = _state()
	assert_eq(engine.terrain(s).at(s.hero(ALPHA).hex), Terrain.Type.NONE)
	assert_eq(_play(s, 0, "TD-010"), "")
	assert_eq(_stage(s, "TS-003").terrain_override, "Fire")
	assert_eq(engine.terrain(s).at(s.hero(ALPHA).hex), Terrain.Type.FIRE)
	assert_eq(engine.terrain(s).at(s.hero(ALPHA).hex + Hex.DIRECTIONS[0]), Terrain.Type.FIRE, "the whole stage")
	# It survives a save.
	var back: GameState = GameState.from_dict(s.to_dict())
	assert_eq(engine.terrain(back).at(back.hero(ALPHA).hex), Terrain.Type.FIRE)


func test_the_card_needs_a_stage_under_the_hero() -> void:
	var s: GameState = _state()
	s.hero(ALPHA).hex = Hex.offset_to_axial(3, 10)
	assert_eq(_play(s, 0, "TD-010"), "your hero is not on a stage")
	assert_eq(s.player(0).energy, 10, "not played, nothing paid")


func test_fire_burns_each_hero_on_it_as_the_end_phase_starts() -> void:
	var s: GameState = _state()
	_stage(s, "TS-003").terrain_override = "Fire"
	_on_map(s, BRAVO, s.hero(ALPHA).hex + Hex.DIRECTIONS[1])
	var away: HeroState = s.hero(ECHO)
	engine._set_phase(s, GameState.PHASE_END)
	assert_eq(s.hero(ALPHA).hp, 9)
	assert_eq(s.hero(BRAVO).hp, 11)
	assert_eq(away.hp, 10, "not on the stage")


func test_a_hero_that_ignores_terrain_does_not_burn() -> void:
	var s: GameState = _state("TD-001")
	var cinder: HeroState = _on_map(s, "p1:TD-001", s.hero(ALPHA).hex + Hex.DIRECTIONS[2])
	_stage(s, "TS-003").terrain_override = "Fire"
	assert_true(engine.ignores_terrain(s, cinder))
	assert_false(engine.ignores_terrain(s, s.hero(ALPHA)))
	engine._set_phase(s, GameState.PHASE_END)
	assert_eq(cinder.hp, 10)
	assert_eq(s.hero(ALPHA).hp, 9)


func test_a_ball_that_ignores_terrain_rolls_as_on_plain_ground() -> void:
	var tuning := PhysicsTuning.new()
	var map := HexMap.new(23, tuning.hex_size)
	var from: Vector2 = map.to_world(Hex.offset_to_axial(11, 18))
	var plain: PackedVector2Array = TerrainPhysics.roll_path(TerrainMap.new(), map, tuning, 2, from, Vector2(0, -1), 0.6)
	var mud := TerrainMap.new()
	mud.set_patch(map.from_world(plain[plain.size() / 2]), Terrain.Type.MUD, map)
	var stuck: PackedVector2Array = TerrainPhysics.roll_path(mud, map, tuning, 2, from, Vector2(0, -1), 0.6)
	var free: PackedVector2Array = TerrainPhysics.roll_path(mud, map, tuning, 2, from, Vector2(0, -1), 0.6, 1.0 / 60.0, true)
	assert_lt(from.distance_to(stuck[stuck.size() - 1]), from.distance_to(plain[plain.size() - 1]) - 0.1, "mud stops a ball short")
	assert_almost_eq(from.distance_to(free[free.size() - 1]), from.distance_to(plain[plain.size() - 1]), 0.01)
