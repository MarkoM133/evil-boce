extends GutTest
## The text parser on real card texts, and the fx language round trip.


func _fx(type: String, name: String, text: String, extra: Dictionary = {}) -> CardDef:
	var rec: Dictionary = {"id": "T-001", "name": name, "type": type, "text": text}
	for k: Variant in extra:
		rec[k] = extra[k]
	return CardDef.from_card(rec)


func _assert_fx(card: CardDef, want: String) -> void:
	assert_eq(card.fx, want, "text: %s" % card.text)
	assert_eq(card.unparsed.size(), 0, "unparsed: %s" % ", ".join(card.unparsed))


func test_hero_abilities() -> void:
	_assert_fx(_fx("Hero", "Pannacotta Fugo", "Postroll Phase: If Pannacotta Fugo is activated, all other Heroes in Range take 2 DMG."),
		"POSTROLL IF ACTIVATED: DAMAGE ALL_OTHER_IN_RANGE 2")
	_assert_fx(_fx("Hero", "Bruno Bucciarati", "Postroll Phase Once Per Turn: Bruno Bucciarati may move up to 2 spaces."),
		"POSTROLL ONCE OPTIONAL: MOVE SELF 2")
	# Bucciarati after the change in the card change list.
	_assert_fx(_fx("Hero", "Bruno Bucciarati", "Postroll Phase Once Per Turn: If Bruno Bucciarati is activated, he may move up to 2 spaces."),
		"POSTROLL ONCE OPTIONAL IF ACTIVATED: MOVE SELF 2")
	# Postroll range for engage cards must last the turn.
	_assert_fx(_fx("Action", "Long Shot", "Postroll Phase: Your Hero gains +2 Range until the end of the turn."),
		"POSTROLL: BUFF SELF RNG 2 TURN")
	_assert_fx(_fx("Hero", "Kaido", "Kaido takes -1 DMG from all sources."), "PASSIVE: DAMAGE_MOD SELF -1")
	_assert_fx(_fx("Hero", "Sanji", "All friendly Characters in Sanji's Range have +2000 Power."),
		"PASSIVE: BUFF ALL_FRIENDLY_IN_RANGE PWR 2000")
	_assert_fx(_fx("Hero", "Shanks", "Shanks has +1000 Power for every friendly Character who has 5 or less HP."),
		"PASSIVE: BUFF SELF PWR 1000 PER LOW_HP_FRIENDLY 5")
	_assert_fx(_fx("Hero", "Narancia Ghirga", "Postroll Phase Once Per Turn: Narancia Ghirga may choose to gain -2 Range and +2 DMG until the end of the turn."),
		"POSTROLL ONCE OPTIONAL: BUFF SELF RNG -2 TURN; BUFF SELF DMG 2 TURN")
	_assert_fx(_fx("Hero", "Luffy", "[Range] Postroll Phase Once Per Turn: Luffy may activate a Core."),
		"POSTROLL ONCE OPTIONAL RANGE: ACTIVATE_CORE")
	_assert_fx(_fx("Hero", "Big Mom", "Postroll Phase Once Per Turn: Big Mom may deactivate a Core to heal 3 HP."),
		"POSTROLL ONCE OPTIONAL: DEACTIVATE_CORE SELF 1; HEAL SELF 3")
	_assert_fx(_fx("Hero", "Giorno Giovanna", "[Range] Postroll Phase Once Per Turn: Giorno Giovanna may deactivate a Core to heal a friendly Hero 2 HP."),
		"POSTROLL ONCE OPTIONAL RANGE: DEACTIVATE_CORE SELF 1; HEAL FRIENDLY 2")


func test_actions_and_equipment() -> void:
	_assert_fx(_fx("Action", "Barrier", "Preroll Phase: This Hero is immune to Knockback and takes -1 DMG from all sources this turn."),
		"PREROLL: STATUS SELF IMMUNE_KB TURN; DAMAGE_MOD SELF -1 TURN")
	_assert_fx(_fx("Action", "Shove", "[Range] Postroll Phase: Knockback an Opponent's Hero 3 spaces in the opposite direction of your Hero."),
		"POSTROLL RANGE: KNOCKBACK ENEMY 3 AWAY")
	_assert_fx(_fx("Action", "Pull", "Postroll Phase: Make an Opponent's Hero move 3 spaces towards you."),
		"POSTROLL: KNOCKBACK ENEMY 3 TOWARDS")
	_assert_fx(_fx("Action", "Dilemma", "[Range] Postroll Phase: Your Opponent chooses:\n- You charge 2 Energy and they discharge 2 Energy\n- Your Hero heals 3 HP and their Hero takes 3 DMG"),
		"POSTROLL RANGE: CHOOSE OPP [CHARGE ME 2; DISCHARGE OPP 2] [HEAL SELF 3; DAMAGE ENEMY 3]")
	_assert_fx(_fx("Action", "Gambit", "Battle Phase: If you win this Battle, your Opponent must discard a card."),
		"BATTLE IF WIN: DISCARD OPP 1")
	_assert_fx(_fx("Action", "Finisher", "Battle Phase: If you win this Battle, your Opponent's Hero takes DMG."),
		"BATTLE IF WIN: DAMAGE ENEMY DMG")
	_assert_fx(_fx("Action", "Rage", "Battle Phase: As an additional cost, take 3 DMG."), "BATTLE: COST_DAMAGE 3")
	_assert_fx(_fx("Action", "Encore", "Roll Phase: You may roll the activated Hero again."), "ROLL OPTIONAL: ROLL_AGAIN")
	_assert_fx(_fx("Action", "Mend", "Preroll Phase: Heal 5 HP."), "PREROLL: HEAL SELF 5")
	_assert_fx(_fx("Action", "Bricks", "[Range] Preroll Phase: Place a Wall."), "PREROLL RANGE: WALL")
	_assert_fx(_fx("Action", "Peek", "[Range] Preroll Phase: Reveal a Core."), "PREROLL RANGE: REVEAL_CORE")
	_assert_fx(_fx("Action", "Blockade", "[Range] Preroll Phase: Your Opponent cannot take a Stage this turn."), "PREROLL RANGE: NO_CLAIM OPP")
	_assert_fx(_fx("Action", "Tax", "[Range] Postroll Phase: All of your Opponent's Battle Phase cards cost 2 more Energy this turn."),
		"POSTROLL RANGE: COST OPP 2 BATTLE TURN")
	_assert_fx(_fx("Action", "Only phase", "Battle Phase:"), "BATTLE:")
	_assert_fx(_fx("Equipment", "Wado", "The equipped Hero gains +1000 Power for every {Sword} equipped."),
		"PASSIVE: BUFF EQUIPPED PWR 1000 PER TRAIT_EQUIPPED {Sword}")
	_assert_fx(_fx("Equipment", "Spike", "The equipped Hero takes +1 DMG from all sources."), "PASSIVE: DAMAGE_MOD EQUIPPED 1")
	_assert_fx(_fx("Equipment", "Drain", "Preroll Phase: You must discharge 1 Energy if the equipped Hero is activated."),
		"PREROLL IF ACTIVATED: DISCHARGE ME 1")
	_assert_fx(_fx("Assist", "Rayleigh", "Your {Haki} cards cost 1 less to play."), "PASSIVE: COST ME -1 {Haki}")
	_assert_fx(_fx("Evolution", "Giorno Requiem", "While Giorno Giovanna is activated, your Opponent's cards have +2 cost.", {"hero": "Giorno Giovanna"}),
		"PASSIVE IF ACTIVATED: COST OPP 2")
	_assert_fx(_fx("Evolution", "Kaido Dragon", "Kaido gains +1000 Power for every 3 missing HP.", {"hero": "Kaido"}),
		"PASSIVE: BUFF SELF PWR 1000 PER MISSING_HP 3")


func test_stages() -> void:
	var st: CardDef = _fx("Stage", "Whole Cake", "When this Stage is revealed, each Hero gains +1000 Power for every Activated Core they have.\nTerrain: Mud")
	_assert_fx(st, "REVEAL: BUFF EACH_HERO PWR 1000 PER CORES")
	assert_eq(st.terrain, Terrain.Type.MUD)
	_assert_fx(_fx("Stage", "Drum", "When this Stage is revealed, the Hero with more HP gains +3000 Power."), "REVEAL: BUFF MOST_HP PWR 3000")
	_assert_fx(_fx("Stage", "Shimotsuki", "Each Hero gains +1 DMG for every equipped {Sword} they have."),
		"PASSIVE: BUFF EACH_HERO DMG 1 PER TRAIT_EQUIPPED {Sword}")
	_assert_fx(_fx("Stage", "Egghead", "Each Hero gains +1000 Power for every charged Energy their player has."),
		"PASSIVE: BUFF EACH_HERO PWR 1000 PER ENERGY")


func test_unknown_text_is_reported() -> void:
	var c: CardDef = _fx("Hero", "Leone Abbacchio", "End Phase: If Leone Abbacchio was activated this turn, put the top card of your graveyard to the top of your deck.")
	assert_eq(c.unparsed.size(), 1)
	assert_false(c.is_ready())
	var two: CardDef = _fx("Action", "Mixed", "Preroll Phase: Heal 5 HP. Then sing a song.")
	assert_eq(two.fx, "PREROLL: HEAL SELF 5")
	assert_eq(two.unparsed.size(), 1)


func test_hand_written_fx_wins() -> void:
	var c: CardDef = _fx("Action", "Odd", "Something the parser cannot read.", {"fx": "PREROLL: HEAL SELF 2\nPOSTROLL RANGE: DAMAGE ENEMY 1"})
	assert_true(c.fx_hand_written)
	assert_true(c.is_ready())
	assert_eq(c.effects.size(), 2)
	assert_eq(c.effects[1].range, true)
	var bad: CardDef = _fx("Action", "Broken", "x", {"fx": "SOMETIME: DANCE"})
	assert_false(bad.is_ready())


func test_fx_language_round_trip() -> void:
	for line: String in ["POSTROLL ONCE OPTIONAL RANGE IF ACTIVATED: DAMAGE ALL_OTHER_IN_RANGE 2; HEAL SELF 1",
			"PASSIVE: BUFF EQUIPPED PWR 1000 PER TRAIT_EQUIPPED {Sword}",
			"POSTROLL RANGE: CHOOSE OPP [CHARGE ME 2; DISCHARGE OPP 2] [HEAL SELF 3; DAMAGE ENEMY 3]",
			"BATTLE IF WIN: DISCARD OPP 1", "BATTLE:"]:
		var e: FxEffect = FxEffect.parse_line(line)
		assert_not_null(e, line)
		if e != null:
			assert_eq(e.to_fx(), line)
	assert_null(FxEffect.parse_line("POSTROLL: BUFF SELF 2000"))
	assert_null(FxEffect.parse_line("NEVER: HEAL SELF 1"))
	assert_null(FxEffect.parse_line("PREROLL: HEAL 5"))
