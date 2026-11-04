extends GutTest
## PER LOW_HP_FRIENDLY counts the hero itself; PER LOW_HP_OTHER_FRIENDLY leaves it out ("every other friendly
## Hero", Shanks 2026-11-05). KO heroes count for neither.

const FIXTURE: String = "res://tests/fixtures/cards.json"


func _hero(id: String, fx: String) -> Dictionary:
	return {"id": id, "name": id, "type": "Hero", "color": "Red", "wt": 2, "traits": ["Haki"],
		"stats": {"hp": 10, "dmg": 3, "pwr": 2000, "rng": 3, "kb": 2}, "text": "x", "fx": fx}


func _match(hero_id: String) -> Array:
	var db: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var list: Array = db["cards"]
	list.append(_hero("TL-001", "PASSIVE: BUFF SELF PWR 1000 PER LOW_HP_FRIENDLY 5"))
	list.append(_hero("TL-002", "PASSIVE: BUFF SELF PWR 1000 PER LOW_HP_OTHER_FRIENDLY 5"))
	var catalog: CardCatalog = CardCatalog.from_json_text(JSON.stringify(db))
	var engine := RulesEngine.new(catalog)
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var cards: Dictionary = {"TX-010": 20, "TX-011": 20}
	var cores: Array = ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]
	var s: GameState = engine.start_match(settings, [
		{"name": "A", "heroes": [hero_id, "TA-002", "TA-003"], "cards": cards, "stages": ["TS-001", "TS-002", "TS-003"], "cores": cores},
		{"name": "B", "heroes": ["TB-001", "TB-002", "TB-003"], "cards": cards, "stages": ["TS-004", "TS-005", "TS-006"], "cores": cores},
	], 1)
	return [engine, s]


func test_low_hp_friendly_counts_the_hero_itself() -> void:
	var m: Array = _match("TL-001")
	var engine: RulesEngine = m[0]
	var s: GameState = m[1]
	var me: HeroState = s.hero("p0:TL-001")
	assert_eq(engine.stat(s, me, "pwr"), 2000)
	me.hp = 4
	assert_eq(engine.stat(s, me, "pwr"), 3000, "it counts itself")
	s.hero("p0:TA-002").hp = 3
	assert_eq(engine.stat(s, me, "pwr"), 4000)


func test_low_hp_other_friendly_leaves_the_hero_out_and_ko_heroes_never_count() -> void:
	var m: Array = _match("TL-002")
	var engine: RulesEngine = m[0]
	var s: GameState = m[1]
	var me: HeroState = s.hero("p0:TL-002")
	me.hp = 4
	assert_eq(engine.stat(s, me, "pwr"), 2000, "not itself")
	s.hero("p0:TA-002").hp = 3
	assert_eq(engine.stat(s, me, "pwr"), 3000, "an ally with 3 HP")
	var ko: HeroState = s.hero("p0:TA-003")
	ko.hp = 0
	ko.zone = HeroState.ZONE_KO
	assert_eq(engine.stat(s, me, "pwr"), 3000, "a KO ally does not count")
	# Enemies are not friendly.
	s.hero("p1:TB-001").hp = 1
	assert_eq(engine.stat(s, me, "pwr"), 3000)
