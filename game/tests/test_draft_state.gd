extends GutTest
## The Draft mode (GDD 13): heroes in snake order with none shared, packs of the copy pool,
## only legal picks, skips, and decks filled to the size at the end.

const FIXTURE: String = "res://tests/fixtures/cards.json"

var catalog: CardCatalog
var rng := RandomNumberGenerator.new()


func before_each() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string(FIXTURE))
	rng.seed = 1


func _run(seed: int) -> DraftState:
	var d: DraftState = DraftState.start(catalog, seed, 0, 20)
	var guard: int = 0
	while d.phase != DraftState.PHASE_DONE and guard < 200:
		guard += 1
		var slot: int = d.waiting_on()
		var id: String = d.timeout_pick(slot, rng)
		assert_eq(d.pick(slot, id), "", "a timeout pick is legal")
	assert_eq(d.phase, DraftState.PHASE_DONE)
	return d


func test_heroes_go_in_snake_order_and_nobody_shares_one() -> void:
	var d: DraftState = DraftState.start(catalog, 3, 1)
	assert_eq(d.waiting_on(), 1, "the first picker")
	var order: PackedInt32Array = PackedInt32Array()
	for _i: int in 6:
		var slot: int = d.waiting_on()
		order.append(slot)
		assert_eq(d.pick(slot, d.options(slot)[0]), "")
	assert_eq(order, PackedInt32Array([1, 0, 0, 1, 1, 0]))
	assert_eq(d.phase, DraftState.PHASE_PACKS)
	assert_eq(PackedStringArray(d.heroes[0]).size(), 3)
	for id: String in d.heroes[0]:
		assert_false(PackedStringArray(d.heroes[1]).has(id), "no hero on both sides")
	assert_eq(d.pick(0, "TA-001"), "not your pick" if d.waiting_on() != 0 else "that card is not in the pack")


func test_only_legal_cards_and_the_rest_goes_to_the_other() -> void:
	var d: DraftState = DraftState.start(catalog, 5)
	while d.phase == DraftState.PHASE_HEROES:
		var slot: int = d.waiting_on()
		d.pick(slot, d.options(slot)[0])
	var slot: int = d.waiting_on()
	var before: int = d.current_pack().size()
	for id: String in d.options(slot):
		var c: CardDef = catalog.get_card(id)
		assert_true(d._hero_colors(slot).has(c.color), "%s is of the picker's colours" % id)
	var id: String = d.options(slot)[0]
	assert_eq(d.pick(slot, id), "")
	assert_eq(d.current_pack().size(), before - 1, "one card left the pack")
	assert_eq(JsonUtil.as_int(JsonUtil.as_dict(d.cards[slot]).get(id, 0)), 1)
	if d.waiting_on() >= 0 and d.current_pack().size() == before - 1:
		assert_ne(d.waiting_on(), slot, "the other picks next (unless it had to skip)")


func test_a_full_draft_gives_legal_decks_of_the_size() -> void:
	var d: DraftState = _run(7)
	for i: int in 2:
		var deck: Dictionary = d.decks()[i]
		var heroes: PackedStringArray = JsonUtil.as_strings(deck["heroes"])
		var cards: Dictionary = JsonUtil.as_dict(deck["cards"])
		assert_eq(heroes.size(), 3)
		var n: int = 0
		for k: Variant in cards:
			n += JsonUtil.as_int(cards[k])
		assert_eq(n, 20, "filled to the deck size")
		for e: String in DeckCode.check(catalog, heroes, cards, 20):
			fail_test("deck %d: %s" % [i, e])


func test_the_same_seed_drafts_the_same_packs_and_the_dict_round_trips() -> void:
	var a: DraftState = DraftState.start(catalog, 11)
	var b: DraftState = DraftState.start(catalog, 11)
	while a.phase == DraftState.PHASE_HEROES:
		var slot: int = a.waiting_on()
		var id: String = a.options(slot)[0]
		a.pick(slot, id)
		b.pick(slot, id)
	assert_eq(a.current_pack(), b.current_pack())
	var back: DraftState = DraftState.from_dict(a.to_dict(), catalog)
	assert_eq(back.current_pack(), a.current_pack())
	assert_eq(back.waiting_on(), a.waiting_on())
	assert_eq(back.to_dict(), a.to_dict())
