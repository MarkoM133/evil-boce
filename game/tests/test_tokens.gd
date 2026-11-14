extends GutTest
## Token cards (GDD 10, Marko 2026-11-14): made by another card or a hero ability (fx TOKEN), beside the hand
## and open to everyone, played like a card, never counted, discarded or paid as damage, gone at the turn's end.
## Scenarios 81 and 82 play them through whole turns; this file holds the single rules.

var catalog: CardCatalog
var engine: RulesEngine

const MAKER: String = "TA-060"
const TOKEN: String = "TA-060-1"


func before_all() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string("res://tests/fixtures/cards.json"))
	engine = RulesEngine.new(catalog)


func _state() -> GameState:
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var decks: Array = [
		{"name": "A", "heroes": ["TA-001", "TA-002", "TA-003"], "cards": {MAKER: 40}, "stages": [], "cores": []},
		{"name": "B", "heroes": ["TB-001", "TB-002", "TB-003"], "cards": {"TX-010": 40}, "stages": [], "cores": []},
	]
	var s: GameState = engine.start_match(settings, decks, 3)
	s.active = {0: "p0:TA-001", 1: "p1:TB-001"}
	for id: String in ["p0:TA-001", "p1:TB-001"]:
		s.hero(id).zone = HeroState.ZONE_MAP
	s.phase = GameState.PHASE_PREROLL
	return s


func test_the_card_says_it_is_a_token_and_only_an_action_can_be_one() -> void:
	assert_true(catalog.get_card(TOKEN).token)
	assert_false(catalog.get_card(MAKER).token)
	assert_true(catalog.get_card(TOKEN).is_ready())
	assert_eq(Array(catalog.get_card(MAKER).tokens_made()), [TOKEN])
	assert_true(JsonUtil.as_bool(catalog.get_card(TOKEN).to_record().get("token", false)), "a record carries it on")
	var bad: CardDef = CardDef.from_card({"id": "TA-070-1", "name": "Token Sword", "type": "Equipment", "color": "Red", "cost": 1,
		"traits": ["General"], "token": true, "text": ""})
	assert_false(bad.is_ready(), "an Equipment token is not a card the game plays")


func test_fx_reads_token_lines_but_never_in_the_end_phase_or_a_passive() -> void:
	var e: FxEffect = FxEffect.parse_line("PREROLL: TOKEN ME TA-060-1 2")
	assert_not_null(e)
	assert_eq(e.to_fx(), "PREROLL: TOKEN ME TA-060-1 2")
	assert_not_null(FxEffect.parse_line("POSTROLL ONCE OPTIONAL: TOKEN OPP TA-060-1"))
	assert_null(FxEffect.parse_line("END: TOKEN ME TA-060-1"), "it would be gone at once")
	assert_null(FxEffect.parse_line("END: CHOOSE ME [TOKEN ME TA-060-1] [NOOP]"), "not inside a branch either")
	assert_null(FxEffect.parse_line("PASSIVE: TOKEN ME TA-060-1"))
	assert_null(FxEffect.parse_line("PREROLL: TOKEN SELF TA-060-1"), "a player gets it, not a hero")
	assert_null(FxEffect.parse_line("PREROLL: TOKEN ME TA-060-1 0"))
	assert_null(FxEffect.parse_line("PREROLL: TOKEN ME"))


func test_made_beside_the_hand_and_not_in_the_end_phase() -> void:
	var s: GameState = _state()
	var hand: int = s.player(0).hand.size()
	assert_eq(engine.make_token(s, 0, TOKEN, 2), "")
	assert_eq(Array(s.player(0).tokens), [TOKEN, TOKEN])
	assert_eq(s.player(0).hand.size(), hand, "the hand is not touched")
	assert_eq(str(s.log[s.log.size() - 1].get("type", "")), "token")
	assert_ne(engine.make_token(s, 0, MAKER), "", "only a token card can be made")
	assert_ne(engine.make_token(s, 0, "NO-000-1"), "")
	s.phase = GameState.PHASE_END
	assert_eq(engine.make_token(s, 1, TOKEN), "")
	assert_true(s.player(1).tokens.is_empty(), "nothing is made in the End phase")


func test_everyone_sees_it_and_it_survives_a_save() -> void:
	var s: GameState = _state()
	engine.make_token(s, 0, TOKEN)
	var back: GameState = GameState.from_dict(JsonUtil.as_dict(JSON.parse_string(JSON.stringify(s.to_dict()))))
	assert_eq(Array(back.player(0).tokens), [TOKEN])
	var seen: GameState = GameState.from_dict(NetProtocol.redact(s.to_dict(), 1, catalog))
	assert_eq(Array(seen.player(0).tokens), [TOKEN], "the opponent sees the token")
	assert_eq(seen.player(0).hand[0], NetProtocol.PLACEHOLDER_CARD, "but not the hand")
	assert_eq(seen.player(0).hand.size(), s.player(0).hand.size(), "and the hand count has no token in it")


func test_a_token_is_not_a_card_in_the_hand() -> void:
	var s: GameState = _state()
	s.player(1).hand = PackedStringArray()
	engine.make_token(s, 1, TOKEN)
	# A discard effect finds nothing to take.
	var e: FxEffect = FxEffect.parse_line("PREROLL: DISCARD OPP 1")
	assert_eq(engine.fx.run(s, {"player": 0, "hero": "p0:TA-001", "card": "TX-010", "stage": ""}, e), "")
	assert_true(s.pending.is_empty(), "nobody is asked to pick a card")
	assert_eq(Array(s.player(1).tokens), [TOKEN])
	assert_true(s.player(1).graveyard.is_empty())
	# A ring-out costs 1 DMG or a card: with only a token the damage lands at once.
	var h: HeroState = s.hero("p1:TB-001")
	var hp: int = h.hp
	engine.ring_out(s, h, "edge")
	assert_true(s.pending.is_empty(), "no choice: there is no card to give")
	assert_eq(h.hp, hp - RulesEngine.RING_OUT_DAMAGE)
	# Nor is it a free play.
	assert_true(engine.fx._free_play_options(s, 1, PackedStringArray(["9"])).is_empty())


func test_no_deck_takes_a_token() -> void:
	var heroes: Array[CardDef] = [catalog.get_card("TA-001")]
	assert_true(JsonUtil.as_bool(FirstTag.deck_verdict(catalog, catalog.get_card(MAKER), heroes)["ok"]))
	var v: Dictionary = FirstTag.deck_verdict(catalog, catalog.get_card(TOKEN), heroes)
	assert_false(JsonUtil.as_bool(v["ok"]))
	assert_string_contains(str(v["why"]), "token")
	var errors: PackedStringArray = DeckCode.check(catalog, PackedStringArray(["TA-001", "TA-002", "TA-003"]), {TOKEN: 1})
	assert_string_contains(", ".join(errors), "token")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var deck: Dictionary = DeckCode.random_deck(catalog, rng)
	for id: Variant in JsonUtil.as_dict(deck.get("cards", {})):
		assert_false(catalog.get_card(str(id)).token, "a random deck never holds a token")


func test_a_record_carries_the_tokens_its_cards_can_make() -> void:
	var decks: Array = [{"heroes": ["TA-001"], "stages": [], "cores": [], "cards": {MAKER: 2}}]
	var used: Dictionary = MatchRecorder._used_cards(catalog, decks)
	assert_true(used.has(TOKEN), "the token is in no deck, yet a match carried on from the record must know it")
	assert_true(JsonUtil.as_bool(JsonUtil.as_dict(used[TOKEN]).get("token", false)))
	assert_false(used.has("TA-061-1"), "a token no card of the match makes stays out")


func test_the_bot_may_play_its_token() -> void:
	var s: GameState = _state()
	s.player(0).hand = PackedStringArray()
	engine.make_token(s, 0, TOKEN)
	assert_eq(Array(s.player(0).playable_cards()), [TOKEN])
	s.player(0).energy = 3
	s.hero("p0:TA-001").hp = 4
	s.to_act = 0
	assert_eq(engine.apply(s, Move.make(Move.PLAY_CARD, 0, {"card": TOKEN})), "")
	assert_eq(s.hero("p0:TA-001").hp, 6)
	assert_true(s.player(0).tokens.is_empty())
	assert_true(s.player(0).graveyard.is_empty(), "played, it is gone: no graveyard")


## "Create a Spark Token." (Marko 2026-11-14): the text parser reads it, and the catalog puts the token's id in.
func _text_catalog(extra: Array = []) -> CardCatalog:
	var list: Array = [
		{"id": "DQ1-010", "name": "Magical Cylinder", "type": "Action", "color": "Red", "cost": 2, "traits": ["General"],
			"text": "Preroll Phase: Create a Magical Cylinder Gush Token."},
		{"id": "DQ1-010-1", "name": "Magical Cylinder Gush", "type": "Action", "color": "Red", "cost": 1, "traits": ["General"],
			"token": true, "text": "Battle Phase: Your Hero gets +1000 Power."},
		{"id": "DQ1-001", "name": "Hero Of Sparks", "type": "Hero", "color": "Red", "stats": {"hp": 10, "dmg": 3, "pwr": 2000, "rng": 2, "kb": 2},
			"text": "Postroll Phase Once Per Turn: If Hero Of Sparks is activated, you may create 2 Spark Tokens."},
		{"id": "DQ1-001-1", "name": "Spark", "type": "Action", "color": "Red", "cost": 1, "traits": ["General"], "token": true,
			"text": "Postroll Phase: Your Hero heals 2 HP."},
	]
	list.append_array(extra)
	return CardCatalog.from_doc({"version": 1, "cards": list}, false)


func test_the_card_text_names_the_token_and_the_game_finds_its_card() -> void:
	var cat: CardCatalog = _text_catalog()
	var maker: CardDef = cat.get_card("DQ1-010")
	assert_eq(maker.fx, "PREROLL: TOKEN ME DQ1-010-1", "the token carries its maker's name and is still found")
	assert_true(maker.is_ready(), ", ".join(maker.unparsed))
	assert_eq(Array(maker.tokens_made()), ["DQ1-010-1"])
	assert_eq(maker.effects[0].line, "PREROLL: TOKEN ME DQ1-010-1", "the line a waiting effect is read from again")
	var hero: CardDef = cat.get_card("DQ1-001")
	assert_eq(hero.fx, "POSTROLL ONCE OPTIONAL IF ACTIVATED: TOKEN ME DQ1-001-1 2")
	assert_true(hero.is_ready(), ", ".join(hero.unparsed))


func test_a_token_nobody_made_a_card_for_leaves_the_card_not_ready() -> void:
	var cat: CardCatalog = _text_catalog([
		{"id": "DQ1-020", "name": "Empty Promise", "type": "Action", "color": "Red", "cost": 1, "traits": ["General"],
			"text": "Preroll Phase: Create a Ghost Token."},
		{"id": "DQ1-021", "name": "End Maker", "type": "Action", "color": "Red", "cost": 1, "traits": ["General"],
			"text": "End Phase: Create a Spark Token."},
		{"id": "DQ1-022", "name": "Borrower", "type": "Action", "color": "Red", "cost": 1, "traits": ["General"],
			"text": "Preroll Phase: Create a Spark Token."},
	])
	assert_false(cat.get_card("DQ1-020").is_ready(), "no token card is named Ghost")
	assert_string_contains(", ".join(cat.get_card("DQ1-020").unparsed), "Ghost")
	assert_false(cat.get_card("DQ1-021").is_ready(), "a token is never made in the End phase")
	assert_eq(cat.get_card("DQ1-022").fx, "PREROLL: TOKEN ME DQ1-001-1", "another card may make the hero's token")
