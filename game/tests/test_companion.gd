extends GutTest
## Companions (GDD 10, Marko 2026-11-21; the first is Coco Jumbo): an Assist puts a token next to the hero, one
## hero of its player may hide inside for energy and comes out when it is activated, the token walks by itself
## at the end of the turn, balls push it and off the table it is gone with its Assist.

var catalog: CardCatalog
var engine: RulesEngine

const TURTLE: String = "TF-030"   # COMPANION, HIDE 1 for 1 energy, WANDER 2
const SHELL: String = "TF-031"    # COMPANION, HIDE 2 for nothing, stays where it is
const ALPHA: String = "p0:TA-001"
const BRAVO: String = "p0:TA-002"
const ECHO: String = "p1:TB-001"


func before_all() -> void:
	catalog = CardCatalog.from_json_text(FileAccess.get_file_as_string("res://tests/fixtures/cards.json"))
	engine = RulesEngine.new(catalog)


## Alpha (activated) and Echo on the map, far from each other; player 1 holds both companion cards.
func _state() -> GameState:
	var settings := MatchSettings.new()
	settings.manual_setup = false
	var decks: Array = [
		{"name": "A", "heroes": ["TA-001", "TA-002", "TA-003"], "cards": {"TX-010": 40}, "stages": [], "cores": []},
		{"name": "B", "heroes": ["TB-001", "TB-002", "TB-003"], "cards": {"TX-010": 40}, "stages": [], "cores": []},
	]
	var s: GameState = engine.start_match(settings, decks, 3)
	s.active = {0: ALPHA, 1: ECHO}
	s.hero(ALPHA).zone = HeroState.ZONE_MAP
	s.hero(ALPHA).hex = Hex.offset_to_axial(8, 10)
	s.hero(ECHO).zone = HeroState.ZONE_MAP
	s.hero(ECHO).hex = Hex.offset_to_axial(8, 2)
	s.phase = GameState.PHASE_PREROLL
	s.to_act = 0
	s.player(0).hand = PackedStringArray([TURTLE, SHELL])
	s.player(0).energy = 10
	return s


## Plays the Assist and puts its companion on the first hex offered.
func _with_companion(s: GameState, card: String = TURTLE) -> CompanionState:
	assert_eq(engine.apply(s, Move.make(Move.PLAY_CARD, 0, {"card": card})), "")
	if not s.pending.is_empty():
		var options: Array = JsonUtil.as_array(s.pending[0].get("options", []))
		assert_eq(engine.apply(s, Move.make(Move.CHOOSE, 0, {"value": options[0]})), "")
	return s.companion_of(0)


## How many abilities of that card player 1 is offered now.
func _offers(s: GameState, card: String) -> int:
	var n: int = 0
	for a: Dictionary in engine.fx.usable_abilities(s, 0):
		if str(a["card"]) == card:
			n += 1
	return n


func test_the_card_reads_and_is_ready() -> void:
	var c: CardDef = catalog.get_card(TURTLE)
	assert_true(c.is_ready(), "COMPANION, HIDE and WANDER are words of the fx language")
	assert_eq(c.effects.size(), 3)
	assert_eq(c.effects[1].when, "POSTROLL")
	assert_true(c.effects[1].optional)


func test_the_assist_puts_a_companion_next_to_the_hero() -> void:
	var s: GameState = _state()
	assert_eq(engine.apply(s, Move.make(Move.PLAY_CARD, 0, {"card": TURTLE})), "")
	assert_eq(s.pending.size(), 1, "the player picks the hex")
	assert_eq(str(s.pending[0]["kind"]), "hex")
	var options: Array = JsonUtil.as_array(s.pending[0]["options"])
	assert_eq(options.size(), 6, "every hex around the hero is free")
	assert_eq(engine.apply(s, Move.make(Move.CHOOSE, 0, {"value": options[2]})), "")
	var c: CompanionState = s.companion_of(0)
	assert_not_null(c)
	assert_eq(c.hex, JsonUtil.as_hex(options[2]))
	assert_eq(Hex.distance(c.hex, s.hero(ALPHA).hex), 1)
	assert_eq(c.card_id, TURTLE)
	assert_true(s.player(0).assists.has(TURTLE))
	assert_eq(s.player(0).energy, 8, "the card's cost, nothing more")
	assert_false(s.is_free(c.hex, false), "its hex is taken")


func test_a_new_companion_replaces_the_old_one_with_its_assist() -> void:
	var s: GameState = _state()
	_with_companion(s, TURTLE)
	s.to_act = 0
	var c: CompanionState = _with_companion(s, SHELL)
	assert_eq(s.companions.size(), 1, "one per player")
	assert_eq(c.card_id, SHELL)
	assert_false(s.player(0).assists.has(TURTLE))
	assert_true(s.player(0).graveyard.has(TURTLE), "the old one's Assist goes with it")


func test_a_hero_next_to_it_hides_for_energy() -> void:
	var s: GameState = _state()
	var c: CompanionState = _with_companion(s)
	s.phase = GameState.PHASE_POSTROLL
	assert_eq(_offers(s, TURTLE), 1, "the companion's own ability, in Postroll")
	assert_eq(engine.fx.use_ability(s, 0, "", TURTLE, 1), "")
	var h: HeroState = s.hero(ALPHA)
	assert_true(h.is_hidden())
	assert_eq(c.inside, ALPHA)
	assert_eq(s.player(0).energy, 7, "1 energy to hide")
	assert_false(h.is_on_map())
	assert_true(engine.pass_only(s, 0), "its player has no hero to play cards for this turn")
	assert_false(engine.in_range(s, s.hero(ECHO), h), "nobody reaches it")
	assert_eq(_offers(s, TURTLE), 0, "one hero inside at a time")


func test_too_far_or_too_poor_cannot_hide() -> void:
	var s: GameState = _state()
	var c: CompanionState = _with_companion(s)
	s.phase = GameState.PHASE_POSTROLL
	s.player(0).energy = 0
	assert_eq(_offers(s, TURTLE), 0, "no energy")
	s.player(0).energy = 5
	s.hero(ALPHA).hex = Hex.neighbor(Hex.neighbor(Hex.neighbor(c.hex, 0), 0), 0)
	assert_eq(_offers(s, TURTLE), 0, "three hexes away, reach 1")


func test_the_player_picks_who_hides_when_two_are_near() -> void:
	var s: GameState = _state()
	var c: CompanionState = _with_companion(s, SHELL)
	var b: HeroState = s.hero(BRAVO)
	b.zone = HeroState.ZONE_MAP
	b.hex = Hex.neighbor(Hex.neighbor(c.hex, 3), 3)
	if s.hero_at(b.hex, b) != null:
		b.hex = Hex.neighbor(Hex.neighbor(c.hex, 1), 1)
	s.phase = GameState.PHASE_POSTROLL
	assert_eq(engine.fx.use_ability(s, 0, "", SHELL, 1), "")
	assert_eq(s.pending.size(), 1)
	assert_eq(str(s.pending[0]["kind"]), "hero")
	assert_eq(engine.apply(s, Move.make(Move.CHOOSE, 0, {"value": BRAVO})), "")
	assert_true(b.is_hidden())
	assert_eq(s.player(0).energy, 9, "this one hides for nothing")


func test_a_hidden_hero_comes_out_when_it_is_activated() -> void:
	var s: GameState = _state()
	var c: CompanionState = _with_companion(s, SHELL)
	var h: HeroState = s.hero(ALPHA)
	engine.enter_shelter(s, h, c)
	s.phase = GameState.PHASE_START
	s.active = {}
	s.only_pass = PackedInt32Array()
	assert_true(engine.selectable_heroes(s, 0).has(h), "a hidden hero can be activated")
	assert_eq(engine.apply(s, Move.make(Move.SELECT, 0, {"hero": ALPHA, "roll": false})), "")
	assert_true(h.is_on_map())
	assert_eq(Hex.distance(h.hex, c.hex), 1, "next to the companion")
	assert_eq(c.inside, "")


func test_it_walks_by_itself_and_carries_the_hero() -> void:
	var s: GameState = _state()
	var c: CompanionState = _with_companion(s)
	engine.enter_shelter(s, s.hero(ALPHA), c)
	for _i: int in 12:
		var from: Vector2i = c.hex
		engine.wander_companion(s, c, 2)
		var d: int = Hex.distance(from, c.hex)
		assert_true(d >= 1 and d <= 2, "1 or 2 hexes in a line, got %d" % d)
		assert_true(s.map().contains(c.hex), "never off the table")
		assert_eq(c.inside, ALPHA)
	assert_true(s.hero(ALPHA).is_hidden())


func test_boxed_in_it_stays() -> void:
	var s: GameState = _state()
	var c: CompanionState = _with_companion(s, SHELL)
	for n: Vector2i in Hex.neighbors(c.hex):
		if s.hero_at(n) == null:
			var w := WallState.new()
			w.id = "wall:%d" % (s.walls.size() + 1)
			w.hexes.append(n)
			s.walls.append(w)
	var from: Vector2i = c.hex
	engine.wander_companion(s, c, 2)
	assert_eq(c.hex, from)


func test_a_ball_pushes_it_and_off_the_table_it_is_gone() -> void:
	var s: GameState = _state()
	var c: CompanionState = _with_companion(s)
	var to: Vector2i = Hex.neighbor(Hex.neighbor(c.hex, 4), 4)
	var r := RollResult.new()
	r.ball_id = c.id
	r.end_area = BallWorld.Area.MAP
	r.end_hex = to
	engine._apply_companion_result(s, r)
	assert_eq(c.hex, to, "it rests where the sim says it stopped")
	engine.enter_shelter(s, s.hero(ALPHA), c)
	var out := RollResult.new()
	out.ball_id = c.id
	out.ring_out = true
	out.end_area = BallWorld.Area.VOID
	engine._apply_companion_result(s, out)
	assert_null(s.companion_of(0))
	assert_true(s.player(0).graveyard.has(TURTLE), "its Assist goes with it")
	assert_false(s.player(0).assists.has(TURTLE))
	var h: HeroState = s.hero(ALPHA)
	assert_eq(h.zone, HeroState.ZONE_STRIP, "the hero inside is rung out")
	assert_eq(s.pending.size(), 1, "and pays as for a ring-out: 1 DMG or a card")
	assert_eq(str(s.pending[0]["by"]), "ring_out")


func test_a_hero_stopping_on_its_hex_pushes_it_aside() -> void:
	var s: GameState = _state()
	var c: CompanionState = _with_companion(s, SHELL)
	var from: Vector2i = c.hex
	s.hero(ECHO).hex = from
	engine._unstack_companions(s)
	assert_ne(c.hex, from)
	assert_eq(Hex.distance(c.hex, from), 1)


func test_when_the_assist_leaves_the_hero_comes_out_unhurt() -> void:
	var s: GameState = _state()
	var c: CompanionState = _with_companion(s, SHELL)
	var at: Vector2i = c.hex
	var h: HeroState = s.hero(ALPHA)
	var hp: int = h.hp
	engine.enter_shelter(s, h, c)
	s.player(0).assists = PackedStringArray()
	engine._sync_companions(s)
	assert_eq(s.companions.size(), 0)
	assert_true(h.is_on_map())
	assert_eq(h.hex, at, "where the companion stood")
	assert_eq(h.hp, hp)


func test_hidden_heroes_are_no_target_and_their_cards_are_not_in_play() -> void:
	var s: GameState = _state()
	var c: CompanionState = _with_companion(s, SHELL)
	engine.enter_shelter(s, s.hero(ALPHA), c)
	var e: FxEffect = FxEffect.parse_line("PREROLL: DAMAGE ALL_ENEMY 1")
	var hit: Array[HeroState] = engine.fx._targets(s, {"player": 1, "hero": ECHO, "card": "TB-001", "stage": ""}, e, "ALL_ENEMY", null)
	assert_false(hit.has(s.hero(ALPHA)))
	for src: Dictionary in engine.fx.sources(s):
		var src_hero: HeroState = src["hero"]
		assert_true(src_hero != s.hero(ALPHA), "its ability is not a source while it hides")


func test_a_saved_match_keeps_the_companion_and_who_is_inside() -> void:
	var s: GameState = _state()
	var c: CompanionState = _with_companion(s)
	engine.enter_shelter(s, s.hero(ALPHA), c)
	var back: GameState = GameState.from_dict(s.to_dict())
	assert_eq(back.companions.size(), 1)
	assert_eq(back.companion_of(0).hex, c.hex)
	assert_eq(back.companion_of(0).inside, ALPHA)
	assert_true(back.hero(ALPHA).is_hidden())
	assert_eq(back.shelter_of(ALPHA).id, c.id)
	assert_eq(GameState.from_dict({}).companions.size(), 0, "an older record has none")


## Walls on every free hex next to `center`.
func _wall_in(s: GameState, center: Vector2i) -> void:
	for n: Vector2i in Hex.neighbors(center):
		if s.is_free(n, false):
			var w := WallState.new()
			w.id = "wall:%d" % (s.walls.size() + 1)
			w.hexes.append(n)
			s.walls.append(w)


func test_with_no_room_next_to_the_hero_it_goes_on_the_nearest_free_hex() -> void:
	var s: GameState = _state()
	var h: HeroState = s.hero(ALPHA)
	_wall_in(s, h.hex)
	var spots: Array[Vector2i] = engine.companion_spots(s, h)
	assert_eq(spots.size(), 12, "the whole second ring is free")
	for a: Vector2i in spots:
		assert_eq(Hex.distance(a, h.hex), 2)
	assert_eq(engine.apply(s, Move.make(Move.PLAY_CARD, 0, {"card": TURTLE})), "", "the card is played all the same (Marko 2026-11-22)")
	assert_eq(str(s.pending[0]["kind"]), "hex", "the player picks among the equally near")
	assert_eq(JsonUtil.as_array(s.pending[0]["options"]).size(), 12)
	assert_eq(engine.apply(s, Move.make(Move.CHOOSE, 0, {"value": Hex.to_json(Hex.neighbor(h.hex, 0))})), "pick one of the offered options", "a walled hex next to the hero is not on offer")
	assert_eq(engine.apply(s, Move.make(Move.CHOOSE, 0, {"value": Hex.to_json(spots[5])})), "")
	assert_eq(s.companion_of(0).hex, spots[5])


func test_next_to_the_hero_comes_first() -> void:
	var s: GameState = _state()
	var h: HeroState = s.hero(ALPHA)
	var free: Vector2i = Hex.neighbor(h.hex, 2)
	_wall_in(s, h.hex)
	s.walls = s.walls.filter(func(w: WallState) -> bool: return not w.hexes.has(free))
	var spots: Array[Vector2i] = engine.companion_spots(s, h)
	assert_eq(spots.size(), 1, "one hex next to the hero is free: no farther one is offered")
	assert_eq(spots[0], free)


func test_a_hidden_hero_comes_out_on_the_nearest_free_hex_it_picks() -> void:
	var s: GameState = _state()
	var c: CompanionState = _with_companion(s, SHELL)
	var h: HeroState = s.hero(ALPHA)
	engine.enter_shelter(s, h, c)
	assert_eq(engine.shelter_exits(s, h).size(), 6, "room all round the companion: the six hexes next to it")
	_wall_in(s, c.hex)
	var exits: Array[Vector2i] = engine.shelter_exits(s, h)
	assert_eq(exits.size(), 12, "none next to it: the second ring")
	s.phase = GameState.PHASE_START
	s.active = {}
	s.only_pass = PackedInt32Array()
	var far: Vector2i = Hex.neighbor(Hex.neighbor(Hex.neighbor(c.hex, 0), 0), 0)
	assert_eq(engine.apply(s, Move.make(Move.SELECT, 0, {"hero": ALPHA, "roll": false, "hex": Hex.to_json(far)})),
		"not one of the free hexes nearest to the companion", "a farther hex is not an exit")
	assert_true(h.is_hidden(), "a refused pick leaves it inside")
	assert_eq(engine.apply(s, Move.make(Move.SELECT, 0, {"hero": ALPHA, "roll": false, "hex": Hex.to_json(exits[7])})), "")
	assert_eq(h.hex, exits[7], "the hex its player picked")
	assert_eq(Hex.distance(h.hex, c.hex), 2)
	assert_eq(c.inside, "")


func test_without_a_pick_it_takes_the_first_exit() -> void:
	var s: GameState = _state()
	var c: CompanionState = _with_companion(s, SHELL)
	var h: HeroState = s.hero(ALPHA)
	engine.enter_shelter(s, h, c)
	_wall_in(s, c.hex)
	var first: Vector2i = engine.shelter_exits(s, h)[0]
	assert_eq(engine.leave_shelter(s, h, null), "")
	assert_eq(h.hex, first)
