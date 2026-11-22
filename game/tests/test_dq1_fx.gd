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
	{"id": "TD-020", "name": "Crowd Blast", "type": "Action", "color": "Red", "cost": 1, "traits": ["General"],
		"text": "Battle Phase: Your Hero gets +4000 Power for each Opponent's Hero in this Battle."},
	{"id": "TD-021", "name": "Grey Burst", "type": "Action", "color": "None", "bonusColors": ["Red"], "cost": 1, "traits": ["General"], "bonus": {"pwr": 1000},
		"text": "Battle Phase:\nRed Bonus: Your Hero gets +1000 Power for each Opponent's Hero in this Battle instead."},
	{"id": "TD-022", "name": "Grey Sweep", "type": "Action", "color": "None", "bonusColors": ["Red"], "cost": 1, "traits": ["General"], "bonus": {"pwr": 1000},
		"text": "Battle Phase:\nRed Bonus: If there are at least 2 Opponent's Heroes in this Battle, your Hero gets an additional +2 DMG."},
	{"id": "TD-023", "name": "Last Stand", "type": "Action", "color": "Red", "cost": 1, "traits": ["General"],
		"text": "Battle Phase: Your Hero gets +2000 Power and +1 DMG for each HP they have."},
	{"id": "TD-024", "name": "Old Wounds", "type": "Action", "color": "Red", "cost": 1, "traits": ["General"],
		"text": "Battle Phase: Your Hero gets +1000 Power for each HP they are missing."},
	{"id": "TD-025", "name": "Echoes", "type": "Action", "color": "Red", "cost": 1, "traits": ["General"],
		"text": "Battle Phase: Your Hero gets +1000 Power for each 3 {Haki} cards in your graveyard."},
	{"id": "TD-026", "name": "Reckoning", "type": "Action", "color": "Red", "cost": 1, "traits": ["General"], "bonus": {"dmg": 3},
		"text": "Battle Phase: Play this card only if you have at least 3 {Haki} cards in your graveyard. Put 3 of them on the bottom of your deck."},
	{"id": "TD-027", "name": "Victory Lap", "type": "Action", "color": "Red", "cost": 1, "traits": ["General"],
		"text": "Preroll Phase: Play this card only if you claimed a Stage last turn.\nDraw 3 cards."},
	{"id": "TD-028", "name": "Brute", "type": "Hero", "color": "Blue", "wt": 2, "stats": {"hp": 10, "dmg": 3, "pwr": 2000, "rng": 3, "kb": 2},
		"text": "Battle Phase: Brute gets +3000 Power if an Opponent's Hero in this Battle has 8000 Power or more."},
	{"id": "TD-029", "name": "Twinblade", "type": "Hero", "color": "Green", "wt": 2, "stats": {"hp": 10, "dmg": 3, "pwr": 2000, "rng": 3, "kb": 2},
		"text": "Twinblade gets +2 Knockback if you have more {Haki} than {Gear Second} cards in your graveyard, or +2 DMG if you have more {Gear Second} than {Haki}."},
	{"id": "TD-030", "name": "Counterflame", "type": "Action", "color": "Red", "cost": 2, "traits": ["General"], "bonus": {"pwr": 3000},
		"text": "Battle Phase: This card costs 1 Energy less if your Opponent played a {Haki} card this turn."},
	{"id": "TD-031", "name": "Even Blade", "type": "Action", "color": "Red", "cost": 1, "traits": ["General"], "bonus": {"pwr": 3000},
		"text": "Battle Phase: If after playing this card you have the same Power as your Opponent, your Hero gets an additional +2000 Power."},
	{"id": "TD-032", "name": "Spite", "type": "Action", "color": "Red", "cost": 1, "traits": ["General"],
		"text": "Battle Phase: If you lose this Battle and your Hero falls below 4 HP, an Opponent's Hero in this Battle takes 2 DMG."},
	{"id": "TD-033", "name": "Packleader", "type": "Hero", "color": "Purple", "wt": 2, "stats": {"hp": 10, "dmg": 3, "pwr": 2000, "rng": 3, "kb": 2},
		"text": "Battle Phase: Whenever Packleader wins a Battle with another friendly Hero in it, draw a card."},
	{"id": "TD-034", "name": "Fireproof", "type": "Hero", "color": "Green", "wt": 2, "stats": {"hp": 10, "dmg": 3, "pwr": 2000, "rng": 3, "kb": 2},
		"text": "Battle Phase: Fireproof takes 2 less DMG if your Opponent played a {Haki} or {Gear Second} card in this Battle."},
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


# --- counters, conditions, play requirements --------------------------------------------

## A battle between Alpha and Echo (and whoever else is named), next to each other, in its card round.
func _battle(s: GameState, also: PackedStringArray = PackedStringArray()) -> void:
	_on_map(s, ECHO, s.hero(ALPHA).hex + Hex.DIRECTIONS[0])
	var ids: Array = [ALPHA, ECHO]
	var at: int = 1
	for id: String in also:
		_on_map(s, id, s.hero(ALPHA).hex + Hex.DIRECTIONS[at])
		ids.append(id)
		at += 1
	s.phase = GameState.PHASE_BATTLE
	s.battles = [{"heroes": ids, "resolved": false}]
	s.battle_index = 0
	s.round_over = false
	s.passed = PackedInt32Array()
	s.to_act = 0


func _grave(s: GameState, slot: int, cards: Array) -> void:
	for c: Variant in cards:
		s.player(slot).graveyard.append(str(c))


func test_counters_read() -> void:
	assert_eq(_fx_of("TD-020"), "BATTLE: BUFF SELF PWR 4000 PER OPP_IN_BATTLE")
	assert_eq(_fx_of("TD-021"), "BATTLE:\nBATTLE INSTEAD BONUS: BUFF SELF PWR 1000 PER OPP_IN_BATTLE")
	assert_eq(_fx_of("TD-022"), "BATTLE:\nBATTLE BONUS IF OPP_COUNT 2: BUFF SELF DMG 2")
	assert_eq(_fx_of("TD-023"), "BATTLE: BUFF SELF PWR 2000 PER HP; BUFF SELF DMG 1 PER HP")
	assert_eq(_fx_of("TD-024"), "BATTLE: BUFF SELF PWR 1000 PER MISSING_HP 1")
	assert_eq(_fx_of("TD-025"), "BATTLE: BUFF SELF PWR 1000 PER GRAVE {Haki} 3")
	assert_eq(_fx_of("TD-026"), "BATTLE: REQUIRE GRAVE {Haki} 3\nPLAY: RECYCLE ME 3 BOTTOM {Haki}")
	assert_eq(_fx_of("TD-027"), "PREROLL: REQUIRE CLAIMED_LAST_TURN\nPLAY: DRAW ME 3")
	assert_eq(_fx_of("TD-028"), "PASSIVE IF OPP_PWR 8000: BUFF SELF PWR 3000")
	assert_eq(_fx_of("TD-029"), "PASSIVE IF GRAVE_MORE {Haki} {Gear Second}: BUFF SELF KB 2\nPASSIVE IF GRAVE_MORE {Gear Second} {Haki}: BUFF SELF DMG 2")
	assert_eq(_fx_of("TD-030"), "BATTLE IF OPP_PLAYED TURN {Haki}: OWN_COST -1")
	assert_eq(_fx_of("TD-031"), "BATTLE IF PWR_TIED: BUFF SELF PWR 2000")
	assert_eq(_fx_of("TD-032"), "BATTLE IF LOSE_BELOW 4: DAMAGE ENEMY 2")
	assert_eq(_fx_of("TD-033"), "BATTLE IF WIN_ALLY: DRAW ME 1")
	assert_eq(_fx_of("TD-034"), "PASSIVE IF OPP_PLAYED BATTLE {Haki} {Gear Second}: DAMAGE_MOD SELF -2")
	# The fx line reads back with every word of its condition.
	var e: FxEffect = FxEffect.parse_line("PASSIVE IF GRAVE_MORE {Avan Style} {Dark Army}: BUFF SELF KB 2")
	assert_eq(e.cond, "GRAVE_MORE")
	assert_eq(Array(e.cond_args), ["{Avan Style}", "{Dark Army}"])
	assert_eq(e.to_fx(), "PASSIVE IF GRAVE_MORE {Avan Style} {Dark Army}: BUFF SELF KB 2")


func test_power_for_each_opponent_in_the_battle() -> void:
	var s: GameState = _state()
	_battle(s, PackedStringArray([FOXTROT]))
	var before: int = engine.stat(s, s.hero(ALPHA), "pwr")
	assert_eq(_play(s, 0, "TD-020"), "")
	assert_eq(engine.stat(s, s.hero(ALPHA), "pwr"), before + 8000, "two opponents")


func test_a_bonus_instead_of_the_stat_box() -> void:
	# One opponent: +1000 in place of the +1000 of the box. Two: +2000. A hero of another colour gets the box.
	var s: GameState = _state()
	_battle(s)
	var before: int = engine.stat(s, s.hero(ALPHA), "pwr")
	assert_eq(_play(s, 0, "TD-021"), "")
	assert_eq(engine.stat(s, s.hero(ALPHA), "pwr"), before + 1000)
	s = _state()
	_battle(s, PackedStringArray([FOXTROT]))
	assert_eq(_play(s, 0, "TD-021"), "")
	assert_eq(engine.stat(s, s.hero(ALPHA), "pwr"), before + 2000)
	s = _state()
	_battle(s, PackedStringArray([FOXTROT]))
	var cyan: int = engine.stat(s, s.hero(FOXTROT), "pwr")
	assert_eq(_play(s, 1, "TD-021", FOXTROT), "")
	assert_eq(engine.stat(s, s.hero(FOXTROT), "pwr"), cyan + 1000, "no bonus for Cyan: the box")


func test_a_bonus_that_needs_two_opponents() -> void:
	var s: GameState = _state()
	_battle(s)
	var dmg: int = engine.stat(s, s.hero(ALPHA), "dmg")
	assert_eq(_play(s, 0, "TD-022"), "")
	assert_eq(engine.stat(s, s.hero(ALPHA), "dmg"), dmg, "one opponent: only the box")
	s = _state()
	_battle(s, PackedStringArray([FOXTROT]))
	assert_eq(_play(s, 0, "TD-022"), "")
	assert_eq(engine.stat(s, s.hero(ALPHA), "dmg"), dmg + 2)


func test_power_for_hp_and_for_missing_hp() -> void:
	var s: GameState = _state()
	_battle(s)
	s.hero(ALPHA).hp = 4
	var pwr: int = engine.stat(s, s.hero(ALPHA), "pwr")
	var dmg: int = engine.stat(s, s.hero(ALPHA), "dmg")
	assert_eq(_play(s, 0, "TD-023"), "")
	assert_eq(engine.stat(s, s.hero(ALPHA), "pwr"), pwr + 8000)
	assert_eq(engine.stat(s, s.hero(ALPHA), "dmg"), dmg + 4)
	assert_eq(_play(s, 0, "TD-024"), "")
	assert_eq(engine.stat(s, s.hero(ALPHA), "pwr"), pwr + 8000 + 6000, "6 HP missing")


func test_power_for_cards_in_the_graveyard() -> void:
	var s: GameState = _state()
	_battle(s)
	_grave(s, 0, ["TA-049", "TA-049", "TA-049", "TA-049", "TA-049", "TA-049", "TA-049", "TX-010"])
	var pwr: int = engine.stat(s, s.hero(ALPHA), "pwr")
	assert_eq(_play(s, 0, "TD-025"), "")
	assert_eq(engine.stat(s, s.hero(ALPHA), "pwr"), pwr + 2000, "seven {Haki} cards: two threes")


func test_a_card_that_asks_for_cards_in_the_graveyard() -> void:
	var s: GameState = _state()
	_battle(s)
	_grave(s, 0, ["TA-049", "TX-010", "TA-049"])
	assert_eq(_play(s, 0, "TD-026"), "needs 3 {Haki} cards in your graveyard")
	assert_eq(s.player(0).energy, 10)
	s.player(0).hand.remove_at(s.player(0).hand.find("TD-026"))
	_grave(s, 0, ["TA-049", "TX-010"])
	var deck: int = s.player(0).deck.size()
	assert_eq(_play(s, 0, "TD-026"), "")
	assert_eq(engine.fx.grave_count(s, 0, "Haki"), 0, "the three went back")
	assert_eq(s.player(0).deck.size(), deck + 3)
	assert_eq(s.player(0).deck[s.player(0).deck.size() - 1], "TA-049", "to the bottom")
	assert_true(s.player(0).graveyard.has("TX-010"), "other cards stay")


func test_a_card_for_the_turn_after_a_claim() -> void:
	var s: GameState = _state()
	s.phase = GameState.PHASE_PREROLL
	s.turn = 5
	assert_eq(_play(s, 0, "TD-027"), "you did not claim a stage last turn")
	s.player(0).hand.remove_at(s.player(0).hand.find("TD-027"))
	var st: StageState = _stage(s, "TS-002")
	st.placed = true
	st.center = Hex.offset_to_axial(3, 15)
	st.revealed = true
	st.claimed_by = 0
	st.terrain_until_turn = 5
	var hand: int = s.player(0).hand.size()
	assert_eq(_play(s, 0, "TD-027"), "")
	assert_eq(s.player(0).hand.size(), hand + 3)
	st.terrain_until_turn = 4
	assert_eq(_play(s, 0, "TD-027"), "you did not claim a stage last turn", "two turns ago does not count")


func test_a_bonus_against_a_strong_opponent_follows_the_battle() -> void:
	var s: GameState = _state("TD-028")
	var brute: HeroState = s.hero("p1:TD-028")
	_battle(s, PackedStringArray([brute.id]))
	var base: int = engine.stat(s, brute, "pwr")
	s.hero(ALPHA).add_bonus(s.hero(ALPHA).phase_bonus, "pwr", 5000)
	assert_eq(engine.stat(s, brute, "pwr"), base, "Alpha is at 7000")
	s.hero(ALPHA).add_bonus(s.hero(ALPHA).phase_bonus, "pwr", 1000)
	assert_eq(engine.stat(s, brute, "pwr"), base + 3000, "8000 reached: the bonus is there at once")
	s.battle_index = -1
	assert_eq(engine.stat(s, brute, "pwr"), base, "only in a battle")


func test_more_of_one_tag_than_the_other_in_the_graveyard() -> void:
	var s: GameState = _state("TD-029")
	var twin: HeroState = _on_map(s, "p1:TD-029", Hex.offset_to_axial(3, 3))
	var kb: int = engine.stat(s, twin, "kb")
	var dmg: int = engine.stat(s, twin, "dmg")
	_grave(s, 1, ["TA-049", "TA-012"])   # TA-012 carries both tags, TA-049 only {Haki}
	assert_eq(engine.stat(s, twin, "kb"), kb + 2)
	assert_eq(engine.stat(s, twin, "dmg"), dmg)
	s.player(1).graveyard = PackedStringArray(["TA-012"])
	assert_eq(engine.stat(s, twin, "kb"), kb, "a tie gives neither")
	assert_eq(engine.stat(s, twin, "dmg"), dmg)


func test_a_card_cheaper_after_a_tagged_card_of_the_opponent() -> void:
	var s: GameState = _state()
	_battle(s)
	var card: CardDef = catalog.get_card("TD-030")
	assert_eq(engine.card_cost(s, s.player(0), card, s.hero(ALPHA)), 2)
	assert_eq(_play(s, 1, "TA-049", ECHO), "")
	assert_eq(engine.card_cost(s, s.player(0), card, s.hero(ALPHA)), 1)
	assert_eq(engine.card_cost(s, s.player(1), card, s.hero(ECHO)), 2, "their own card does not count for them")


func test_a_bonus_when_the_powers_are_level() -> void:
	var s: GameState = _state()
	_battle(s)
	s.hero(ECHO).add_bonus(s.hero(ECHO).phase_bonus, "pwr", 3000)
	var pwr: int = engine.stat(s, s.hero(ALPHA), "pwr")
	assert_eq(_play(s, 0, "TD-031"), "")
	assert_eq(engine.stat(s, s.hero(ALPHA), "pwr"), pwr + 3000 + 2000, "level after the box, so the bonus comes too")
	assert_eq(_play(s, 0, "TD-031"), "")
	assert_eq(engine.stat(s, s.hero(ALPHA), "pwr"), pwr + 3000 + 2000 + 3000, "not level any more: only the box")


func test_less_damage_after_a_tagged_card_in_this_battle() -> void:
	var s: GameState = _state("TD-034")
	var proof: HeroState = s.hero("p1:TD-034")
	_battle(s, PackedStringArray([proof.id]))
	assert_eq(engine.fx.damage_mod(s, proof), 0)
	assert_eq(_play(s, 0, "TA-049"), "")
	assert_eq(engine.fx.damage_mod(s, proof), -2)
	assert_eq(engine.fx.damage_mod(s, s.hero(ECHO)), 0, "only the hero whose ability it is")


func test_an_effect_for_the_loser_that_fell_low() -> void:
	var s: GameState = _state()
	_battle(s)
	assert_eq(_play(s, 0, "TD-032"), "")
	assert_eq(s.deferred.size(), 1, "it waits for the battle")
	s.hero(ALPHA).hp = 3
	var members: Array[HeroState] = [s.hero(ALPHA), s.hero(ECHO)]
	var winners: Array[HeroState] = [s.hero(ECHO)]
	engine.fx.on_battle_done(s, winners, members)
	assert_eq(s.hero(ECHO).hp, 8, "the one opponent in the battle takes the 2")
	# A loser still at 4 HP or more: nothing.
	s = _state()
	_battle(s)
	assert_eq(_play(s, 0, "TD-032"), "")
	s.hero(ALPHA).hp = 4
	members = [s.hero(ALPHA), s.hero(ECHO)]
	winners = [s.hero(ECHO)]
	engine.fx.on_battle_done(s, winners, members)
	assert_eq(s.hero(ECHO).hp, 10)
	assert_eq(s.deferred.size(), 0)


func test_a_draw_for_a_win_beside_a_friend() -> void:
	var s: GameState = _state("TD-033")
	var lead: HeroState = s.hero("p1:TD-033")
	_battle(s, PackedStringArray([lead.id]))
	engine.fx.fire_phase(s, GameState.PHASE_BATTLE)
	assert_eq(s.deferred.size(), 1)
	var hand: int = s.player(1).hand.size()
	var members: Array[HeroState] = [s.hero(ALPHA), s.hero(ECHO), lead]
	var winners: Array[HeroState] = [s.hero(ECHO), lead]
	engine.fx.on_battle_done(s, winners, members)
	assert_eq(s.player(1).hand.size(), hand + 1)
	# Alone in the battle: no draw.
	s = _state("TD-033")
	lead = s.hero("p1:TD-033")
	_battle(s)
	s.battles = [{"heroes": [ALPHA, lead.id], "resolved": false}]
	_on_map(s, lead.id, s.hero(ALPHA).hex + Hex.DIRECTIONS[3])
	engine.fx.fire_phase(s, GameState.PHASE_BATTLE)
	hand = s.player(1).hand.size()
	members = [s.hero(ALPHA), lead]
	winners = [lead]
	engine.fx.on_battle_done(s, winners, members)
	assert_eq(s.player(1).hand.size(), hand)
