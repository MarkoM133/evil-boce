extends GutTest
## A hero's ability that fires by itself (no "may": "If Abbacchio was activated…") leaves a
## "triggered" event, so the HUD can show the ability's name.

const FIXTURE: String = "res://tests/fixtures/cards.json"


func test_an_activated_heros_own_effect_logs_triggered() -> void:
	var engine := RulesEngine.new(CardCatalog.from_json_text(FileAccess.get_file_as_string(FIXTURE)))
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var cards: Dictionary = {"TX-010": 40}
	var s: GameState = engine.start_match(settings, [
		{"heroes": ["TA-007", "TA-002", "TA-003"], "cards": cards, "stages": [], "cores": []},
		{"heroes": ["TB-001", "TB-002", "TB-003"], "cards": cards, "stages": [], "cores": []},
	], 1)
	s.active[0] = "p0:TA-007"
	engine.fx.fire_phase(s, "end")
	var found: Array = s.log.filter(func(e: Dictionary) -> bool: return str(e.get("type", "")) == "triggered")
	assert_eq(found.size(), 1, "one triggered event")
	if found.size() == 1:
		assert_eq(str(found[0]["hero"]), "p0:TA-007")
		assert_eq(JsonUtil.as_int(found[0]["index"]), 0)
	s.active.erase(0)
	var before: int = s.log.size()
	engine.fx.fire_phase(s, "end")
	assert_eq(s.log.filter(func(e: Dictionary) -> bool: return str(e.get("type", "")) == "triggered").size(), 1,
		"not activated: nothing fires")
	assert_true(s.log.size() >= before)
