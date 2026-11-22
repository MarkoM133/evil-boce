class_name FxEffect
extends RefCounted
## One effect of a card in the fx language (docs/fx-keywords.md). A card's `fx` field holds
## one effect per line; FxTextParser writes the same language from the card text.
##
##   WHEN [ONCE] [OPTIONAL] [RANGE] [INSTEAD] [BONUS [Colour]] [IF COND [ARG]]: ACTION; ACTION; ...
##   ACTION = VERB [TARGET] [ARGS...]      e.g. BUFF SELF PWR 2000 TURN
##
## WHEN:  PLAY (as the card is played), PREROLL / ROLL / POSTROLL / BATTLE / END (an Action
##        is playable only then; a hero, equipment, evolution, assist or stage ability fires
##        or may be used then), PASSIVE (while in play), REVEAL (stage turned face up),
##        PLAYED (a card in play: each time a card is played; IF TAG … says which, CARD_HERO is the hero it was played for).
## Flags: ONCE = once per turn, OPTIONAL = "may" (used through the use_ability move),
##        RANGE = targets must be within the hero's range.
## IF:    ACTIVATED (the hero is activated this turn), WIN (runs after the hero's side wins
##        the current battle), EQUIPPED {Trait} (an enemy in the battle has that trait).
## BONUS [Colour]: a colorless card's colour bonus (2026-11-01): the effect counts only when the
##        hero the card is played for (SELF) is one of the card's bonus colours, or that colour.
## INSTEAD: the effect replaces the one right before it on the card when its own BONUS / IF
##        hold; otherwise it is skipped. Both share the WHEN of the one before.

const WHENS: Array[String] = ["PLAY", "PREROLL", "ROLL", "POSTROLL", "BATTLE", "END", "PASSIVE", "REVEAL", "PLAYED"]
const CONDS: Array[String] = ["ACTIVATED", "WIN", "OPP_EQUIPPED", "COPIES",
	# DQ1 (2026-11-22), see docs/fx-keywords.md:
	"OPP_COUNT", "OPP_PWR", "GRAVE", "GRAVE_MORE", "OPP_PLAYED", "PWR_TIED", "LOW_HP", "ON_STAGE", "CLAIMED_LAST_TURN",
	"WIN_ALLY", "LOSE_BELOW", "TAG"]
## Card types as a filter word (COST, the TAG condition of a PLAYED line).
const TYPE_WORDS: Array[String] = ["ACTION", "EQUIPMENT", "EVOLUTION", "ASSIST", "COMBO"]
## Conditions known only once the battle is over: the effect waits for it (FxRuntime.on_battle_done).
const BATTLE_END_CONDS: Array[String] = ["WIN", "WIN_ALLY", "LOSE_BELOW"]
const COLORS: Array[String] = ["CYAN", "YELLOW", "PURPLE", "RED", "BLUE", "GREEN"]
## Verb -> [takes a target, number of extra args at least].
const VERBS: Dictionary[String, Array] = {
	"BUFF": [true, 2],          # BUFF <target> <STAT> <n> [TURN] [PER <COUNTER> [arg]]
	"DAMAGE": [true, 1],        # DAMAGE <target> <n|DMG>
	"HEAL": [true, 1],          # HEAL <target> <n>
	"MOVE": [true, 1],          # MOVE <target> <n>  (the player picks a hex up to n away)
	"KNOCKBACK": [true, 1],     # KNOCKBACK <target> <n> [AWAY|TOWARDS]
	"STATUS": [true, 1],        # STATUS <target> <NAME> [turns]
	"DAMAGE_MOD": [true, 1],    # DAMAGE_MOD <target> <n>  (added to damage taken; passive or TURN)
	"REMOVE_EVO": [true, 0],    # REMOVE_EVO <target>
	"WALL": [false, 0],         # WALL [n]  (player picks the hex)
	"REVEAL_CORE": [false, 0],  # REVEAL_CORE  (pick a face-down core)
	"ACTIVATE_CORE": [false, 0],# ACTIVATE_CORE  (pick a core on the field for SELF)
	"DEACTIVATE_CORE": [true, 0], # DEACTIVATE_CORE <target> [n]
	"CHARGE": [true, 1],        # CHARGE <ME|OPP> <n>
	"DISCHARGE": [true, 1],     # DISCHARGE <ME|OPP> <n>
	"DRAW": [true, 1],          # DRAW <ME|OPP> <n>
	"DISCARD": [true, 1],       # DISCARD <ME|OPP> <n>  (that player picks)
	"COST": [true, 1],          # COST <ME|OPP> <n> [{Trait}|PHASE]  (passive cost change)
	"NO_CLAIM": [true, 0],      # NO_CLAIM <ME|OPP|hero group>  (no stage claim this turn: the player, or those heroes)
	"ROLL_AGAIN": [false, 0],   # ROLL_AGAIN  (the activated hero rolls once more)
	"REVERSE_ROLL": [false, 0], # REVERSE_ROLL  (the activated hero goes back to where the Roll phase found it)
	"COST_DAMAGE": [false, 1],  # COST_DAMAGE <n>  (paid by SELF before the rest)
	"OWN_COST": [false, 1],     # OWN_COST <n>  (this card costs ±n; read when the cost is worked out)
	"CHOOSE": [true, 0],        # CHOOSE <ME|OPP> [ACTION; ACTION] [ACTION; ACTION]  (that player picks a branch)
	"RECYCLE": [true, 1],       # RECYCLE <ME|OPP> <n> [TOP|BOTTOM|SHUFFLE]  (graveyard top -> deck)
	"PICK_CORE": [false, 0],    # PICK_CORE  (choose a core on the field; MOVE_CORE / TRAP_CORE use it)
	"MOVE_CORE": [false, 1],    # MOVE_CORE <n>  (the picked core, up to n hexes)
	"TRAP_CORE": [false, 1],    # TRAP_CORE <n>  (an enemy hero activating the picked core this turn takes n)
	"HOLD_HIT": [true, 0],      # HOLD_HIT SELF  (after a win: deal no DMG, double Knockback)
	"FULL_HIT": [true, 0],      # FULL_HIT OPP  (with BATTLE IF WIN: the hit lands whole on the loser's hero, none on cards from the hand)
	"NOOP": [false, 0],         # NOOP  (nothing; a "no" branch for CHOOSE)
	"FREE_PLAY": [false, 1],    # FREE_PLAY <max cost> [{Trait}] [Type]  (play a card from hand on SELF for free)
	"SWAP": [true, 0],          # SWAP FRIENDLY [ENGAGED]  (SELF and that hero trade hexes)
	"DUEL_TOP": [false, 2],     # DUEL_TOP <STAT> <n> [PICK]  (players show their top card; higher cost gets +n: PICK = one hero the winner picks)
	"MOVE_ID": [false, 2],      # MOVE_ID <hero id> <n>  (one hero of a group move; written by the runtime)
	"COMPANION": [false, 0],    # COMPANION  (PLAY, on an Assist: its companion goes on a free hex next to the hero; the player picks)
	"HIDE": [false, 1],         # HIDE <reach> [energy]  (the Assist's companion: one hero of its player within reach hides inside, for that energy)
	"WANDER": [false, 1],       # WANDER <n>  (END: the Assist's companion walks 1..n hexes in a direction drawn by lot)
	"TOKEN": [true, 1],         # TOKEN <ME|OPP> <token card id> [n]  (that player gets n of that token beside the hand)
	"TELEPORT": [true, 1],      # TELEPORT <SELF|FRIENDLY> <n|STAGE>  (to a free hex up to n away, or on a stage in SELF's range; nothing in between matters)
	"TELEPORT_ID": [false, 2],  # TELEPORT_ID <hero id> <n|STAGE>  (the hero picked for TELEPORT FRIENDLY; written by the runtime)
	"APPROACH": [false, 1],     # APPROACH <n>  (SELF steps up to n hexes towards the nearest opponent hero of its battle)
	"RETURN_LATER": [true, 0],  # RETURN_LATER SELF  (as the End phase starts the hero goes back to where the Battle phase found it)
	"DRAIN_STAGE": [false, 1],  # DRAIN_STAGE <n>  (n of the opponents' Energy leaves the stage SELF stands on)
	"REVEAL_STAGE": [false, 0], # REVEAL_STAGE  (a face-down stage of an opponent in SELF's range turns face up)
	"CURSE_STAGE": [false, 0],  # CURSE_STAGE  (for the rest of the match no Battle Phase cards for opponents' heroes on the stage SELF stands on)
	"NEGATE_LAST": [false, 0],  # NEGATE_LAST [{Tag}] [RANGE <n>]  (the last Battle Phase card an opponent played in this battle is undone)
	"REMOVE_ASSIST": [true, 0], # REMOVE_ASSIST OPP  (one of that player's Assists goes to their graveyard; the card's player picks)
	"GAIN_ASSIST": [false, 0],  # GAIN_ASSIST  (the Assist the player removed this turn comes into play on their side)
	"EQUIP_OTHER": [false, 0],  # EQUIP_OTHER [{Tag}]  (this Equipment goes on another friendly hero in SELF's range, one with the tag)
	"DUEL_HAND": [false, 2],    # DUEL_HAND <STAT> <n> [PICK]  (each player in the battle shows a card from the hand; the higher cost gets +n)
	"SHOW_CARD": [false, 1],    # SHOW_CARD <slot>  (that player picks the card to show; written by the runtime)
	"DUEL_SHOWN": [false, 2],   # DUEL_SHOWN <STAT> <n> [PICK]  (the shown cards are compared; written by the runtime)
	"SACRIFICE": [false, 0],    # SACRIFICE  (the Assist whose line it is goes to the graveyard: "put this Assist into the graveyard")
	"SAVE_KO": [true, 0],       # SAVE_KO <target>  (passive, Assist: the first of those heroes that would be KO'd stays at 1 HP; the Assist goes to the graveyard)
	"SHIELD": [true, 1],        # SHIELD <target> <n>  (passive, Assist: when one of those heroes would take a battle hit of n or less, its player may put the Assist into the graveyard instead)
	"PREVENT": [false, 2],      # PREVENT <hero id> <n>  (the next hit of n or less on that hero this turn does nothing; written by the runtime)
	"HEAL_LATER": [true, 1],    # HEAL_LATER <target> <n>  (those heroes heal n as the End phase starts)
	"RING_OUT_DRAW": [false, 1],# RING_OUT_DRAW <n>  (if an opponent's hero is ringed out in this Battle phase, the player draws n)
	"GAIN_TAG": [true, 1],      # GAIN_TAG <target> {Tag} [TURN]  (those heroes carry the tag: while the card is in play, or this turn)
	"PAY": [false, 1],          # PAY <n>  (the player pays n Energy; without it the effect does not start)
	"PAY_HP": [true, 1],        # PAY_HP <target> <n>  (each of those heroes with more than n HP loses n; PAID are the ones that did)
	"KO": [true, 0],            # KO <target> [HP <n>]  (that hero goes down; HP n: only one with n HP or less)
	"HEAL_MOD": [true, 1],      # HEAL_MOD <target> <n> [BY]  (passive: those heroes heal n more; BY: heals from cards played for the source's hero)
	"NEXT_CARD": [false, 3],    # NEXT_CARD {Tag} <STAT> <n>  (the next card with the tag the player plays this turn gives its hero that much more)
	"WEAKEN_CARD": [false, 1],  # WEAKEN_CARD <n>  (PLAYED: the card just played gives its hero up to n less Power)
	"BOTTOM": [true, 1],        # BOTTOM <ME|OPP> <n>  (that player puts n cards from the hand on the bottom of the deck)
	"REQUIRE": [false, 1],      # REQUIRE <COND> [args]  (the card is played only when the condition holds: "Play this card only if …")
	"TERRAIN": [false, 1],      # TERRAIN <Ice|Mud|Ramp|Wind|Fire>  (the stage SELF stands on gets that terrain)
}
## A TOKEN is never made in the End phase (it would be gone at once) nor by a passive (GDD 10, 2026-11-14).
const NO_TOKEN_WHENS: Array[String] = ["END", "PASSIVE"]
const HERO_TARGETS: Array[String] = ["SELF", "EQUIPPED", "ENEMY", "FRIENDLY", "ALL_FRIENDLY", "ALL_ENEMY", "CARD_HERO", "PAID",
	"ALL_OTHER_IN_RANGE", "ALL_FRIENDLY_IN_RANGE", "ALL_ENEMY_IN_RANGE", "ALL_FRIENDLY_IN_BATTLE", "ALL_HEROES", "EACH_HERO", "MOST_HP", "MOST_PWR", "MOST_ENERGY", "MOST_ASSISTS"]
const PLAYER_TARGETS: Array[String] = ["ME", "OPP"]
const STATS: Array[String] = ["PWR", "DMG", "KB", "RNG", "HP"]
const COUNTERS: Array[String] = ["TRAIT_EQUIPPED", "CORES", "MISSING_HP", "ENERGY", "LOW_HP_FRIENDLY", "LOW_HP_OTHER_FRIENDLY", "COUNT",
	"OPP_IN_BATTLE", "HP", "GRAVE"]

var when: String = "PLAY"
var once: bool = false
var optional: bool = false
var range: bool = false
var cond: String = ""
var cond_arg: String = ""
## Every word after the condition's name ("GRAVE {Avan Style} 3"); cond_arg is the first of them.
var cond_args: PackedStringArray = PackedStringArray()
var bonus: bool = false
var bonus_color: String = ""
## BONUS {Tag}: the bonus counts for a hero called that or carrying that tag (2026-11-21).
var bonus_tag: String = ""
var instead: bool = false
## Each action: {"verb": String, "target": String, "args": PackedStringArray,
## "branches": Array[Array[Dictionary]] (CHOOSE only)}.
var actions: Array[Dictionary] = []
## The fx line this came from.
var line: String = ""


func to_fx() -> String:
	var head: PackedStringArray = PackedStringArray([when])
	if once:
		head.append("ONCE")
	if optional:
		head.append("OPTIONAL")
	if range:
		head.append("RANGE")
	if instead:
		head.append("INSTEAD")
	if bonus:
		head.append("BONUS")
		if not bonus_tag.is_empty():
			head.append("{%s}" % bonus_tag)
		elif not bonus_color.is_empty():
			head.append(bonus_color)
	if not cond.is_empty():
		head.append("IF")
		head.append(cond)
		if not cond_args.is_empty():
			head.append_array(cond_args)
		elif not cond_arg.is_empty():
			head.append(cond_arg)
	var parts := PackedStringArray()
	for a: Dictionary in actions:
		parts.append(action_to_fx(a))
	if parts.is_empty():
		return " ".join(head) + ":"
	return " ".join(head) + ": " + "; ".join(parts)


static func action_to_fx(a: Dictionary) -> String:
	var out: PackedStringArray = PackedStringArray([str(a.get("verb", ""))])
	var target: String = str(a.get("target", ""))
	if not target.is_empty():
		out.append(target)
	out.append_array(JsonUtil.as_strings(a.get("args", [])))
	for branch: Variant in JsonUtil.as_array(a.get("branches", [])):
		var items := PackedStringArray()
		for b: Variant in JsonUtil.as_array(branch):
			items.append(action_to_fx(JsonUtil.as_dict(b)))
		out.append("[" + "; ".join(items) + "]")
	return " ".join(out)


## Plain English for one action, for buttons and choice dialogs.
static func describe(a: Dictionary) -> String:
	var verb: String = str(a.get("verb", ""))
	var target: String = str(a.get("target", ""))
	var args: PackedStringArray = JsonUtil.as_strings(a.get("args", []))
	var who: String = {"ME": "you", "OPP": "the opponent", "SELF": "your hero", "ENEMY": "an enemy hero",
		"FRIENDLY": "a friendly hero", "EQUIPPED": "the equipped hero"}.get(target, target.to_lower().replace("_", " "))
	var n: String = args[0] if not args.is_empty() else ""
	match verb:
		"BUFF":
			return "%s +%s %s" % [who, args[1] if args.size() > 1 else "", n]
		"DAMAGE":
			return "%s takes %s DMG" % [who, n]
		"HEAL":
			return "%s heals %s HP" % [who, n]
		"CHARGE":
			return "%s charge %s energy" % [who, n]
		"DISCHARGE":
			return "%s discharge %s energy" % [who, n]
		"DRAW":
			return "%s draw %s" % [who, n]
		"DISCARD":
			return "%s discard %s" % [who, n]
		"TOKEN":
			return "%s get %s token%s" % [who, args[1] if args.size() > 1 else "a", "s" if args.size() > 1 and args[1] != "1" else ""]
		"HOLD_HIT":
			return "Deal no DMG, double Knockback"
		"FULL_HIT":
			return "The whole hit lands on the hero"
		"NOOP":
			return "Deal DMG as usual"
		"MOVE":
			return "%s moves up to %s" % [who, n]
		"KNOCKBACK":
			return "Knock %s back %s" % [who, n]
	return action_to_fx(a)


## An "if you win" line that must already hold when the hit is dealt (FULL_HIT): it runs as the card
## is played and only counts on a win, instead of waiting for the battle like other IF WIN lines.
func arms_on_play() -> bool:
	if cond != "WIN" or actions.is_empty():
		return false
	for a: Dictionary in actions:
		if str(a["verb"]) != "FULL_HIT":
			return false
	return true


## An effect whose condition is known only when the battle is over ("If you win this Battle, …").
func waits_for_battle() -> bool:
	return BATTLE_END_CONDS.has(cond)


## Sets the condition and its arguments.
func set_cond(name: String, args: Array = []) -> void:
	cond = name
	cond_args = PackedStringArray()
	for a: Variant in args:
		cond_args.append(str(a))
	cond_arg = cond_args[0] if not cond_args.is_empty() else ""


## Does this effect fire or become usable in `phase` (GameState phase name)?
func matches_phase(phase: String) -> bool:
	return when == phase.to_upper()


func has_verb(verb: String) -> bool:
	for a: Dictionary in actions:
		if str(a.get("verb", "")) == verb:
			return true
	return false


# --- parsing the fx language --------------------------------------------------------

## Parses every non-empty line; `errors` collects what could not be read (one per bad line).
static func parse_all(fx: String, errors: PackedStringArray = PackedStringArray()) -> Array[FxEffect]:
	var out: Array[FxEffect] = []
	for raw: String in fx.split("\n"):
		var line: String = raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var e: FxEffect = parse_line(line)
		if e == null:
			errors.append(line)
		else:
			out.append(e)
	return out


static func parse_line(line: String) -> FxEffect:
	var colon: int = line.find(":")
	if colon < 0:
		return null
	var e := FxEffect.new()
	e.line = line
	# A {Tag} in the head stays whole, and keeps its spelling for BONUS {Tag}.
	var head: PackedStringArray = _tokens(line.substr(0, colon).strip_edges().to_upper())
	var spelt: PackedStringArray = _tokens(line.substr(0, colon).strip_edges())
	if head.is_empty() or not WHENS.has(head[0]):
		return null
	e.when = head[0]
	var i: int = 1
	while i < head.size():
		match head[i]:
			"ONCE":
				e.once = true
			"OPTIONAL":
				e.optional = true
			"RANGE":
				e.range = true
			"INSTEAD":
				e.instead = true
			"BONUS":
				e.bonus = true
				if i + 1 < head.size() and COLORS.has(head[i + 1]):
					e.bonus_color = head[i + 1]
					i += 1
				elif i + 1 < head.size() and head[i + 1].begins_with("{") and head[i + 1].ends_with("}"):
					e.bonus_tag = spelt[i + 1].trim_prefix("{").trim_suffix("}").strip_edges()
					i += 1
			"IF":
				if i + 1 >= head.size() or not CONDS.has(head[i + 1]):
					return null
				e.cond = head[i + 1]
				i += 1
				# The condition is the last thing in the head: every word after its name is its argument. A {Tag}
				# keeps its spelling.
				while i + 1 < head.size():
					e.cond_args.append(spelt[i + 1] if head[i + 1].begins_with("{") else head[i + 1])
					i += 1
				if not e.cond_args.is_empty():
					e.cond_arg = e.cond_args[0]
			_:
				return null
		i += 1
	var body: String = line.substr(colon + 1).strip_edges()
	if body.is_empty():
		return e
	for part: String in _split_top(body, ";"):
		var a: Dictionary = parse_action(part.strip_edges())
		if a.is_empty():
			return null
		e.actions.append(a)
	if NO_TOKEN_WHENS.has(e.when) and _has_verb_in(e.actions, "TOKEN"):
		return null
	return e


## Is the verb among the actions, CHOOSE branches included?
static func _has_verb_in(list: Array, verb: String) -> bool:
	for x: Variant in list:
		var a: Dictionary = JsonUtil.as_dict(x)
		if str(a.get("verb", "")) == verb:
			return true
		for branch: Variant in JsonUtil.as_array(a.get("branches", [])):
			if _has_verb_in(JsonUtil.as_array(branch), verb):
				return true
	return false


## One action; {} when it is not valid.
static func parse_action(text: String) -> Dictionary:
	var tokens: PackedStringArray = _tokens(text)
	if tokens.is_empty():
		return {}
	var verb: String = tokens[0].to_upper()
	if not VERBS.has(verb):
		return {}
	var spec: Array = VERBS[verb]
	var takes_target: bool = spec[0]
	var min_args: int = spec[1]
	var a: Dictionary = {"verb": verb, "target": "", "args": PackedStringArray()}
	var i: int = 1
	if takes_target:
		if i >= tokens.size():
			return {}
		var t: String = tokens[i].to_upper()
		if not HERO_TARGETS.has(t) and not PLAYER_TARGETS.has(t):
			return {}
		a["target"] = t
		i += 1
	var args := PackedStringArray()
	var branches: Array = []
	while i < tokens.size():
		var tok: String = tokens[i]
		if tok.begins_with("["):
			var inner: String = tok.substr(1, tok.length() - 2)
			var branch: Array = []
			for part: String in _split_top(inner, ";"):
				var b: Dictionary = parse_action(part.strip_edges())
				if b.is_empty():
					return {}
				branch.append(b)
			branches.append(branch)
		elif tok.begins_with("{") or tok.contains(":"):
			# Traits and hero ids keep their case.
			args.append(tok)
		else:
			args.append(tok.to_upper())
		i += 1
	if args.size() < min_args:
		return {}
	a["args"] = args
	if not branches.is_empty():
		a["branches"] = branches
	if verb == "CHOOSE" and branches.size() < 2:
		return {}
	if verb == "BUFF" and (not STATS.has(args[0]) or not args[1].is_valid_int()):
		return {}
	if verb == "TOKEN" and (not PLAYER_TARGETS.has(str(a["target"])) or (args.size() > 1 and (not args[1].is_valid_int() or args[1].to_int() < 1))):
		return {}
	return a


## Splits on `sep` outside [...] brackets.
static func _split_top(text: String, sep: String) -> PackedStringArray:
	var out := PackedStringArray()
	var depth: int = 0
	var cur: String = ""
	for ch: String in text:
		if ch == "[":
			depth += 1
		elif ch == "]":
			depth -= 1
		if ch == sep and depth == 0:
			out.append(cur)
			cur = ""
		else:
			cur += ch
	if not cur.strip_edges().is_empty():
		out.append(cur)
	return out


## Space-separated tokens, keeping [...] and {...} groups whole.
static func _tokens(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var cur: String = ""
	var depth: int = 0
	for ch: String in text:
		if ch == "[" or ch == "{":
			depth += 1
		elif ch == "]" or ch == "}":
			depth -= 1
		if ch == " " and depth == 0:
			if not cur.is_empty():
				out.append(cur)
			cur = ""
		else:
			cur += ch
	if not cur.is_empty():
		out.append(cur)
	return out
