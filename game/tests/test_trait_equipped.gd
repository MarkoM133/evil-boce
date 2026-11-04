extends GutTest
## PER TRAIT_EQUIPPED {Trait} counts every equipment with the trait on the hero, the card whose
## effect it is included: Wado Ichimonji ("+1000 Power for every {Sword} equipped", itself a Sword)
## gives +1000 alone.

const FIXTURE: String = "res://tests/fixtures/cards.json"


func _equip(id: String, traits: Array, fx: String) -> Dictionary:
	return {"id": id, "name": id, "type": "Equipment", "color": "Red", "cost": 1, "traits": traits, "text": "x", "fx": fx}


func test_wado_counts_itself_and_every_other_sword() -> void:
	var db: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var list: Array = db["cards"]
	list.append(_equip("TW-001", ["Zoro", "Sword"], "PASSIVE: BUFF EQUIPPED PWR 1000 PER TRAIT_EQUIPPED {Sword}"))
	list.append(_equip("TW-002", ["General", "Sword"], ""))
	list.append(_equip("TW-003", ["General"], ""))
	var engine := RulesEngine.new(CardCatalog.from_json_text(JSON.stringify(db)))
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var cards: Dictionary = {"TX-010": 20, "TX-011": 20}
	var cores: Array = ["CR0-001", "CR0-002", "CR0-003", "CR0-004", "CR0-005", "CR0-006"]
	var s: GameState = engine.start_match(settings, [
		{"name": "A", "heroes": ["TA-001", "TA-002", "TA-003"], "cards": cards, "stages": ["TS-001", "TS-002", "TS-003"], "cores": cores},
		{"name": "B", "heroes": ["TB-001", "TB-002", "TB-003"], "cards": cards, "stages": ["TS-004", "TS-005", "TS-006"], "cores": cores},
	], 1)
	var h: HeroState = s.hero("p0:TA-001")
	var base: int = engine.stat(s, h, "pwr")
	h.equipment.append("TW-001")
	assert_eq(engine.stat(s, h, "pwr"), base + 1000, "Wado alone: itself is one Sword")
	h.equipment.append("TW-003")
	assert_eq(engine.stat(s, h, "pwr"), base + 1000, "a non-Sword does not count")
	h.equipment.append("TW-002")
	assert_eq(engine.stat(s, h, "pwr"), base + 2000, "Wado and another Sword")
	var other: HeroState = s.hero("p0:TA-002")
	var other_base: int = engine.stat(s, other, "pwr")
	other.equipment.append("TW-002")
	assert_eq(engine.stat(s, other, "pwr"), other_base, "only the hero holding Wado gets it")
