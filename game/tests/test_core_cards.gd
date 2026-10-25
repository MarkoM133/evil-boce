extends GutTest
## Cores as the web app publishes them: the kind in a trait, the stat in `bonus`.


func _core(id: String, bonus: Dictionary, kind: String) -> CardDef:
	return CardDef.from_card({"id": id, "name": "core", "type": "Core", "bonus": bonus, "traits": [kind]})


func test_kind_comes_from_the_trait() -> void:
	assert_eq(_core("CR1-001", {"pwr": 2000}, "Buff").kind, "Buff")
	assert_eq(_core("CR1-002", {"pwr": 4000}, "Major").kind, "Major")
	assert_eq(_core("CR1-006", {"dmg": -2}, "Debuff").kind, "Debuff")


func test_family_comes_from_the_stat() -> void:
	assert_eq(_core("CR1-001", {"pwr": 2000}, "Buff").core_family(), "Power")
	assert_eq(_core("CR1-004", {"dmg": 2}, "Buff").core_family(), "Damage")
	assert_eq(_core("CR1-009", {"kb": -1}, "Debuff").core_family(), "Knockback")


func test_kind_from_the_first_line_of_the_text() -> void:
	var c: CardDef = CardDef.from_card({"id": "CR1-003", "type": "Core", "text": "Debuff\nSomething else", "bonus": {"pwr": -2000}})
	assert_eq(c.kind, "Debuff")


func test_a_kind_field_wins_over_traits() -> void:
	var c: CardDef = CardDef.from_card({"id": "CR0-001", "type": "Core", "kind": "Major", "traits": ["Buff"]})
	assert_eq(c.kind, "Major")
