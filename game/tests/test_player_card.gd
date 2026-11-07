extends GutTest
## What a player card shows the other side of an online lobby (PlayerCard.picks).


## A random deck drawn after one hero pick but not shown yet: the other side sees only that
## hero, the drawn two stay "" ("?"), as on the owner's own card (online playtest 2026-11-07).
func test_hidden_random_deck_shows_only_the_picked_heroes() -> void:
	var card := PlayerCard.new()
	autofree(card)
	card.chosen = PackedStringArray(["OP1-001", "", ""])
	card.built = {"name": "Random · Luffy", "heroes": ["OP1-001", "OP1-004", "JO1-002"], "cards": {}}
	card._show_built = false
	var p: Dictionary = card.picks()
	assert_eq(JsonUtil.as_strings(p["heroes"]), PackedStringArray(["OP1-001", "", ""]))
	assert_eq(str(p["deck_name"]), "Random · Luffy")


## After BUILD or REROLL the owner sees the whole deck, and so does the other side.
func test_shown_random_deck_shows_every_hero() -> void:
	var card := PlayerCard.new()
	autofree(card)
	card.chosen = PackedStringArray(["OP1-001", "", ""])
	card.built = {"name": "Random · Luffy", "heroes": ["OP1-001", "OP1-004", "JO1-002"], "cards": {}}
	card._show_built = true
	assert_eq(JsonUtil.as_strings(card.picks()["heroes"]), PackedStringArray(["OP1-001", "OP1-004", "JO1-002"]))
