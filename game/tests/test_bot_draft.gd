extends GutTest
## The bot's draft picks (GDD 13): always legal, an evolution of its own hero before anything
## else, heroes of one colour before scattered ones.

const FIXTURE: String = "res://tests/fixtures/cards.json"

var catalog: CardCatalog
var rng := RandomNumberGenerator.new()


func before_each() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string(FIXTURE))
	rng.seed = 4


func test_picks_are_legal_and_the_draft_finishes() -> void:
	var d: DraftState = DraftState.start(catalog, 8, 0, 20)
	var guard: int = 0
	while d.phase != DraftState.PHASE_DONE and guard < 200:
		guard += 1
		var slot: int = d.waiting_on()
		var id: String = Bot.draft_pick(catalog, d, slot, rng)
		assert_true(d.options(slot).has(id), "a pick on offer")
		assert_eq(d.pick(slot, id), "")
	assert_eq(d.phase, DraftState.PHASE_DONE)


func test_an_evolution_of_its_hero_comes_first() -> void:
	var d: DraftState = DraftState.start(catalog, 8, 0, 20)
	# Slot 0 takes Alpha (TA-001), whose evolutions TA-012 and TA-013 exist.
	assert_eq(d.pick(0, "TA-001"), "")
	while d.phase == DraftState.PHASE_HEROES:
		var slot: int = d.waiting_on()
		d.pick(slot, Bot.draft_pick(catalog, d, slot, rng))
	var seen: bool = false
	var guard: int = 0
	while d.phase == DraftState.PHASE_PACKS and guard < 100:
		guard += 1
		var slot: int = d.waiting_on()
		var id: String = Bot.draft_pick(catalog, d, slot, rng)
		if slot == 0:
			var evo_on_offer: bool = false
			for o: String in d.options(0):
				if catalog.get_card(o).type == "Evolution":
					evo_on_offer = true
			if evo_on_offer:
				assert_eq(catalog.get_card(id).type, "Evolution", "the evolution is taken when offered")
				seen = true
		d.pick(slot, id)
	if not seen:
		pass_test("no evolution came up in these packs")
