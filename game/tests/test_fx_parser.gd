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
	_assert_fx(_fx("Hero", "Shanks", "Shanks has +1000 Power for every other friendly Hero who has 5 or less HP."),
		"PASSIVE: BUFF SELF PWR 1000 PER LOW_HP_OTHER_FRIENDLY 5")
	_assert_fx(_fx("Hero", "Shanks", "Shanks gets +1000 Power for each friendly Hero with 5 HP or less."),
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
	_assert_fx(_fx("Action", "Raitei", "Battle Phase: As an additional cost, your Hero takes 3 DMG."), "BATTLE: COST_DAMAGE 3")
	_assert_fx(_fx("Action", "Divine Departure", "Battle Phase: If you win this Battle, the Opponent's Hero in this Battle takes all of the damage. Your Opponent can't discard cards to reduce it."),
		"BATTLE IF WIN: FULL_HIT OPP")
	_assert_fx(_fx("Action", "Encore", "Roll Phase: You may roll the activated Hero again."), "ROLL: ROLL_AGAIN")
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


## The card wording agreed on 2026-11-05 (range next to the target, gain / lose Energy, your Hero, additional).
func test_combo_wording_2026_11_07() -> void:
	_assert_fx(_fx("Combo", "Conquest of the Sea", "Battle Phase: Each of your Heroes in this Battle gets +3000 Power and +2 DMG."),
		"BATTLE: BUFF ALL_FRIENDLY_IN_BATTLE PWR 3000; BUFF ALL_FRIENDLY_IN_BATTLE DMG 2")


func test_wording_2026_11_05() -> void:
	var none: Dictionary = {"color": "None", "bonusColors": ["Red"]}
	_assert_fx(_fx("Action", "Observation Haki", "Preroll Phase: Reveal a Core in Range.\nCyan Bonus: This card costs 1 less.", none),
		"PREROLL RANGE: REVEAL_CORE\nPLAY BONUS CYAN: OWN_COST -1")
	_assert_fx(_fx("Action", "Conqueror's Haki", "Postroll Phase: Opponent's Heroes in Range can't claim a Stage this turn.\nRed Bonus: This card costs 1 less.", none),
		"POSTROLL: NO_CLAIM ALL_ENEMY_IN_RANGE\nPLAY BONUS: OWN_COST -1")
	_assert_fx(_fx("Action", "Jenga Cannon", "Preroll Phase: Place a Wall on an empty space in Range."), "PREROLL RANGE: WALL")
	_assert_fx(_fx("Action", "Anti-Manner Kick Course", "Postroll Phase: Knockback an Opponent's Hero in Range 3 spaces, away from your Hero."),
		"POSTROLL RANGE: KNOCKBACK ENEMY 3 AWAY")
	_assert_fx(_fx("Action", "Anti-Manner Kick Course", "Postroll Phase: Choose an Opponent's Hero in Range. Knock them back 3 spaces."),
		"POSTROLL RANGE: KNOCKBACK ENEMY 3 AWAY")
	_assert_fx(_fx("Action", "Bon Apetit", "Preroll Phase: A friendly Hero in Range heals 3 HP.\nPurple Bonus: They heal an additional 1 HP.", none),
		"PREROLL RANGE: HEAL FRIENDLY 3\nPREROLL RANGE INSTEAD BONUS PURPLE: HEAL FRIENDLY 4")
	_assert_fx(_fx("Action", "Intercept", "Postroll Phase: Swap your Hero with another friendly Hero in Range that is in an Opponent's Hero's Range.\nPurple Bonus: This card costs 1 less.", none),
		"POSTROLL RANGE: SWAP FRIENDLY ENGAGED\nPLAY BONUS PURPLE: OWN_COST -1")
	_assert_fx(_fx("Action", "Soul Pocus", "Postroll Phase: Your Opponent chooses one:\n- You gain 2 Energy and they lose 2 Energy.\n- Your Hero heals 3 HP and an Opponent's Hero in Range takes 3 DMG."),
		"POSTROLL RANGE: CHOOSE OPP [CHARGE ME 2; DISCHARGE OPP 2] [HEAL SELF 3; DAMAGE ENEMY 3]")
	_assert_fx(_fx("Hero", "Luffy", "Postroll Phase Once Per Turn: Luffy may activate a Core in Range."), "POSTROLL ONCE OPTIONAL RANGE: ACTIVATE_CORE")
	_assert_fx(_fx("Action", "Soul Pocus", "Postroll Phase: Your Opponent in Range chooses one:
- You gain 2 Energy and they lose 2 Energy.
- Your Hero heals 3 HP and an Opponent's Hero takes 3 DMG."),
		"POSTROLL RANGE: CHOOSE OPP [CHARGE ME 2; DISCHARGE OPP 2] [HEAL SELF 3; DAMAGE ENEMY 3]")
	_assert_fx(_fx("Hero", "Giorno Giovanna", "Postroll Phase Once Per Turn: Giorno may deactivate a Core. If he does, a friendly Hero in Range heals 2 HP."),
		"POSTROLL ONCE OPTIONAL RANGE: DEACTIVATE_CORE SELF 1; HEAL FRIENDLY 2")
	_assert_fx(_fx("Action", "Observation Killing", "Postroll Phase: If an Opponent's Hero is in Range, your Opponent's Battle Phase cards cost 2 Energy more this turn."),
		"POSTROLL RANGE: COST OPP 2 BATTLE TURN")
	_assert_fx(_fx("Stage", "Egghead", "Each Hero gets +1000 Power for each Energy their player has.\nTerrain: None"), "PASSIVE: BUFF EACH_HERO PWR 1000 PER ENERGY")
	_assert_fx(_fx("Stage", "Elbaph", "Battle Phase: In a Battle on this Stage, each player reveals the top card of their deck. The player who revealed the higher-cost card chooses one of their Heroes in this Battle. That Hero gets +2000 Power.\nTerrain: Ramp"),
		"BATTLE: DUEL_TOP PWR 2000 PICK")
	_assert_fx(_fx("Hero", "Sanji", "Other friendly Heroes in Sanji's Range get +2000 Power."), "PASSIVE: BUFF ALL_FRIENDLY_IN_RANGE PWR 2000")
	_assert_fx(_fx("Action", "Life Giver", "Preroll Phase: Move a Core in Range up to 2 spaces. If an Opponent's Hero activates that Core this turn, they take 3 DMG."),
		"PREROLL RANGE: PICK_CORE; MOVE_CORE 2; TRAP_CORE 3")
	_assert_fx(_fx("Equipment", "Enma", "Preroll Phase: If the equipped Hero is activated, lose 1 Energy.\nYellow Bonus: +1000 Power.", {"color": "None", "bonusColors": ["Yellow"]}),
		"PREROLL IF ACTIVATED: DISCHARGE ME 1\nPASSIVE BONUS: BUFF EQUIPPED PWR 1000")
	_assert_fx(_fx("Hero", "Kaido", "Kaido takes 1 less DMG from each source."), "PASSIVE: DAMAGE_MOD SELF -1")
	_assert_fx(_fx("Hero", "Pannacotta Fugo", "Postroll Phase: If Fugo is activated, all other Heroes in Range take 2 DMG, friendly or not."),
		"POSTROLL IF ACTIVATED: DAMAGE ALL_OTHER_IN_RANGE 2")
	_assert_fx(_fx("Hero", "Guido Mista", "Battle Phase: Mista may deactivate up to 2 Cores. If he does, he gets +1 DMG and +2000 Power for each deactivated Core until the end of the turn."),
		"BATTLE OPTIONAL: DEACTIVATE_CORE SELF 2 UPTO; BUFF SELF DMG 1 TURN PER COUNT; BUFF SELF PWR 2000 TURN PER COUNT")
	# Text standard (2026-11-05 evening): gets, for each, cost N Energy less / more, short names.
	_assert_fx(_fx("Assist", "Rayleigh", "Your {Haki} cards cost 1 Energy less.\nCyan Bonus: This card costs 1 Energy less.", {"color": "None", "bonusColors": ["Cyan"]}),
		"PASSIVE: COST ME -1 {Haki}\nPLAY BONUS: OWN_COST -1")
	_assert_fx(_fx("Evolution", "Giorno Giovanna, Requiem", "While Giorno is activated, your Opponent's cards cost 2 Energy more.", {"hero": "Giorno Giovanna"}),
		"PASSIVE IF ACTIVATED: COST OPP 2")
	_assert_fx(_fx("Hero", "Shanks", "Shanks gets +1000 Power for each other friendly Hero who has 5 or less HP."),
		"PASSIVE: BUFF SELF PWR 1000 PER LOW_HP_OTHER_FRIENDLY 5")
	_assert_fx(_fx("Stage", "Whole Cake", "When this Stage is revealed, each Hero gets +1000 Power for each activated Core they have.\nTerrain: Mud"),
		"REVEAL: BUFF EACH_HERO PWR 1000 PER CORES")
	_assert_fx(_fx("Equipment", "Wado Ichimonji", "The equipped Hero gets +1000 Power for each {Sword} equipped to them."),
		"PASSIVE: BUFF EQUIPPED PWR 1000 PER TRAIT_EQUIPPED {Sword}")
	_assert_fx(_fx("Equipment", "Gryphon", "While the equipped Hero is activated, your {Haki} cards cost 1 less.\nRed Bonus: +1000 Power.", none),
		"PASSIVE IF ACTIVATED: COST ME -1 {Haki}\nPASSIVE BONUS: BUFF EQUIPPED PWR 1000")
	_assert_fx(_fx("Assist", "Mihawk", "Battle Phase: If the Opponent's Hero in this Battle has a {Sword} equipped, your Hero gets +1000 Power.\nYellow Bonus: Your Hero gets an additional +1000 Power.", {"color": "None", "bonusColors": ["Yellow"]}),
		"BATTLE IF OPP_EQUIPPED {Sword}: BUFF SELF PWR 1000\nBATTLE BONUS IF OPP_EQUIPPED {Sword}: BUFF SELF PWR 1000")
	_assert_fx(_fx("Hero", "Zoro", "Postroll Phase Once Per Turn: Zoro may deactivate a Core to play a {Sword} Equipment with a cost of 3 or less without paying its cost."),
		"POSTROLL ONCE OPTIONAL: DEACTIVATE_CORE SELF 1; FREE_PLAY 3 {Sword} Equipment")
	_assert_fx(_fx("Action", "Full Body Armament Haki", "Preroll Phase: Your Hero is immune to Knockback this turn.\nBlue Bonus: They take 1 less DMG from each source.", {"color": "None", "bonusColors": ["Blue"]}),
		"PREROLL: STATUS SELF IMMUNE_KB TURN\nPREROLL BONUS: DAMAGE_MOD SELF -1 TURN")
	_assert_fx(_fx("Action", "Parage Shot", "Battle Phase: If you win this Battle, remove the top Evolution from the Opponent's Hero in this Battle."), "BATTLE IF WIN: REMOVE_EVO ENEMY")
	_assert_fx(_fx("Action", "Gomu Gomu no Rocket", "Roll Phase: After your Hero's roll, you may roll them again."), "ROLL: ROLL_AGAIN")
	_assert_fx(_fx("Evolution", "Luffy, Gear Second", "Roll Phase: After Luffy's roll, you may roll him again. If you do, Luffy takes 2 DMG that can't be reduced.", {"hero": "Luffy"}),
		"ROLL OPTIONAL: ROLL_AGAIN; DAMAGE SELF 2 TRUE")
	_assert_fx(_fx("Action", "Taunt", "Postroll Phase: Make an Opponent's Hero move 2 spaces towards your Hero.\nRed Bonus: They move 1 additional space.", none),
		"POSTROLL: KNOCKBACK ENEMY 2 TOWARDS\nPOSTROLL INSTEAD BONUS: KNOCKBACK ENEMY 3 TOWARDS")


func test_stages() -> void:
	var st: CardDef = _fx("Stage", "Whole Cake", "When this Stage is revealed, each Hero gains +1000 Power for every Activated Core they have.\nTerrain: Mud")
	_assert_fx(st, "REVEAL: BUFF EACH_HERO PWR 1000 PER CORES")
	assert_eq(st.terrain, Terrain.Type.MUD)
	_assert_fx(_fx("Stage", "Drum", "When this Stage is revealed, the Hero with more HP gains +3000 Power."), "REVEAL: BUFF MOST_HP PWR 3000")
	_assert_fx(_fx("Stage", "Drum", "The Hero on this Stage with the most HP gets +3000 Power.\nTerrain: Ice"), "PASSIVE: BUFF MOST_HP PWR 3000")
	_assert_fx(_fx("Stage", "Whole Cake", "Each Hero on this Stage gets +1000 Power for each activated Core they have.\nTerrain: Mud"), "PASSIVE: BUFF EACH_HERO PWR 1000 PER CORES")
	_assert_fx(_fx("Stage", "Egghead", "Battle Phase: In a Battle on this Stage, the Hero whose player has more Energy gets +3000 Power.\nTerrain: None"), "BATTLE: BUFF MOST_ENERGY PWR 3000")
	_assert_fx(_fx("Stage", "Egghead", "In a Battle on this Stage, the Hero whose player has more Energy gets +3000 Power.\nTerrain: None"), "BATTLE: BUFF MOST_ENERGY PWR 3000")
	_assert_fx(_fx("Stage", "Egghead", "Battle Phase: In a Battle on this Stage, the player with more Energy chooses one of their Heroes in this Battle. That Hero gets +3000 Power.\nTerrain: None"),
		"BATTLE: BUFF MOST_ENERGY PWR 3000 PICK")
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


func test_colour_bonus_lines() -> void:
	# Colorless cards (2026-11-01): "<Colour> Bonus:" lines, as the drafts of the twelve cards say them.
	var none: Dictionary = {"color": "None", "bonusColors": ["Red"]}
	_assert_fx(_fx("Action", "Taunt", "Postroll Phase: Make an Opponent's Hero move 2 spaces towards you.\nRed Bonus: It moves 3 spaces instead.", none),
		"POSTROLL: KNOCKBACK ENEMY 2 TOWARDS\nPOSTROLL INSTEAD BONUS: KNOCKBACK ENEMY 3 TOWARDS")
	_assert_fx(_fx("Action", "Bon Apetit", "[Range] Preroll Phase: A friendly Hero heals 3 HP.\nPurple Bonus: It heals 4 HP instead.", none),
		"PREROLL RANGE: HEAL FRIENDLY 3\nPREROLL RANGE INSTEAD BONUS PURPLE: HEAL FRIENDLY 4")
	_assert_fx(_fx("Action", "Observation Haki", "[Range] Preroll Phase: Reveal a Core.\nCyan Bonus: This card costs 1 less to play.", none),
		"PREROLL RANGE: REVEAL_CORE\nPLAY BONUS CYAN: OWN_COST -1")
	_assert_fx(_fx("Assist", "Rayleigh", "Your {Haki} cards cost 1 less to play.\nCyan Bonus: This card costs 1 less to play.", none),
		"PASSIVE: COST ME -1 {Haki}\nPLAY BONUS CYAN: OWN_COST -1")
	_assert_fx(_fx("Action", "Armament Haki", "Battle Phase:\nYellow Bonus: +1 DMG.", none), "BATTLE:\nBATTLE BONUS YELLOW: BUFF SELF DMG 1")
	# "an additional": more on top of the sentence before, under its condition (Mihawk's wording, 2026-11-05).
	_assert_fx(_fx("Action", "Extra", "Battle Phase: If you win this Battle, your Hero heals 2 HP.\nYellow Bonus: Your Hero heals an additional 1 HP.", none),
		"BATTLE IF WIN: HEAL SELF 2\nBATTLE BONUS YELLOW IF WIN: HEAL SELF 1")
	_assert_fx(_fx("Action", "Full Body Armament Haki", "Preroll Phase: This Hero is immune to Knockback this turn.\nBlue Bonus: It also takes -1 DMG from all sources this turn.", none),
		"PREROLL: STATUS SELF IMMUNE_KB TURN\nPREROLL BONUS BLUE: DAMAGE_MOD SELF -1 TURN")
	_assert_fx(_fx("Equipment", "Sandai Kitetsu", "The equipped Hero takes +1 DMG from all sources.\nYellow Bonus: +1 DMG.", none),
		"PASSIVE: DAMAGE_MOD EQUIPPED 1\nPASSIVE BONUS YELLOW: BUFF EQUIPPED DMG 1")
	_assert_fx(_fx("Equipment", "Enma", "Preroll Phase: You must discharge 1 Energy if the equipped Hero is activated.\nYellow Bonus: +1000 Power.", none),
		"PREROLL IF ACTIVATED: DISCHARGE ME 1\nPASSIVE BONUS YELLOW: BUFF EQUIPPED PWR 1000")
	# Two colours with the same bonus: no colour on the flag, the card's bonusColors decide.
	_assert_fx(_fx("Action", "Peek", "[Range] Preroll Phase: Reveal a Core.\nCyan / Purple Bonus: This card costs 1 less to play.", {"color": "None", "bonusColors": ["Cyan", "Purple"]}),
		"PREROLL RANGE: REVEAL_CORE\nPLAY BONUS: OWN_COST -1")
