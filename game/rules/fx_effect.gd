class_name FxEffect
extends RefCounted
## One effect of a card in the fx language (docs/fx-keywords.md). A card's `fx` field holds
## one effect per line; FxTextParser writes the same language from the card text.
##
##   WHEN [ONCE] [OPTIONAL] [RANGE] [IF COND [ARG]]: ACTION; ACTION; ...
##   ACTION = VERB [TARGET] [ARGS...]      e.g. BUFF SELF PWR 2000 TURN
##
## WHEN:  PLAY (as the card is played), PREROLL / ROLL / POSTROLL / BATTLE / END (an Action
##        is playable only then; a hero, equipment, evolution, assist or stage ability fires
##        or may be used then), PASSIVE (while in play), REVEAL (stage turned face up).
## Flags: ONCE = once per turn, OPTIONAL = "may" (used through the use_ability move),
##        RANGE = targets must be within the hero's range.
##        LAUNCH = its knockback is a physical hit in the "mixed" knockback mode (GDD 10).
## IF:    ACTIVATED (the hero is activated this turn), WIN (runs after the hero's side wins
##        the current battle), EQUIPPED {Trait} (an enemy in the battle has that trait).

const WHENS: Array[String] = ["PLAY", "PREROLL", "ROLL", "POSTROLL", "BATTLE", "END", "PASSIVE", "REVEAL"]
const CONDS: Array[String] = ["ACTIVATED", "WIN", "OPP_EQUIPPED", "COPIES"]
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
	"NO_CLAIM": [true, 0],      # NO_CLAIM <ME|OPP>  (no stage claim this turn)
	"ROLL_AGAIN": [false, 0],   # ROLL_AGAIN  (the activated hero rolls once more)
	"REVERSE_ROLL": [false, 0], # REVERSE_ROLL  (the activated hero goes back to where the Roll phase found it)
	"COST_DAMAGE": [false, 1],  # COST_DAMAGE <n>  (paid by SELF before the rest)
	"CHOOSE": [true, 0],        # CHOOSE <ME|OPP> [ACTION; ACTION] [ACTION; ACTION]  (that player picks a branch)
	"RECYCLE": [true, 1],       # RECYCLE <ME|OPP> <n> [TOP|BOTTOM|SHUFFLE]  (graveyard top -> deck)
	"PICK_CORE": [false, 0],    # PICK_CORE  (choose a core on the field; MOVE_CORE / TRAP_CORE use it)
	"MOVE_CORE": [false, 1],    # MOVE_CORE <n>  (the picked core, up to n hexes)
	"TRAP_CORE": [false, 1],    # TRAP_CORE <n>  (an enemy hero activating the picked core this turn takes n)
	"HOLD_HIT": [true, 0],      # HOLD_HIT SELF  (after a win: deal no DMG, double Knockback)
	"NOOP": [false, 0],         # NOOP  (nothing; a "no" branch for CHOOSE)
	"FREE_PLAY": [false, 1],    # FREE_PLAY <max cost> [{Trait}]  (play a card from hand on SELF for free)
	"SWAP": [true, 0],          # SWAP FRIENDLY [ENGAGED]  (SELF and that hero trade hexes)
	"DUEL_TOP": [false, 2],     # DUEL_TOP <STAT> <n>  (players on the stage show their top card; higher cost wins)
	"MOVE_ID": [false, 2],      # MOVE_ID <hero id> <n>  (one hero of a group move; written by the runtime)
}
const HERO_TARGETS: Array[String] = ["SELF", "EQUIPPED", "ENEMY", "FRIENDLY", "ALL_FRIENDLY", "ALL_ENEMY",
	"ALL_OTHER_IN_RANGE", "ALL_FRIENDLY_IN_RANGE", "ALL_HEROES", "EACH_HERO", "MOST_HP", "MOST_PWR"]
const PLAYER_TARGETS: Array[String] = ["ME", "OPP"]
const STATS: Array[String] = ["PWR", "DMG", "KB", "RNG", "HP"]
const COUNTERS: Array[String] = ["TRAIT_EQUIPPED", "CORES", "MISSING_HP", "ENERGY", "LOW_HP_FRIENDLY", "COUNT"]

var when: String = "PLAY"
var once: bool = false
var optional: bool = false
## LAUNCH: the knockback is a physical hit in the "mixed" knockback mode (GDD 10).
var launch: bool = false
var range: bool = false
var cond: String = ""
var cond_arg: String = ""
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
	if launch:
		head.append("LAUNCH")
	if range:
		head.append("RANGE")
	if not cond.is_empty():
		head.append("IF")
		head.append(cond)
		if not cond_arg.is_empty():
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
		"HOLD_HIT":
			return "Deal no DMG, double Knockback"
		"NOOP":
			return "Deal DMG as usual"
		"MOVE":
			return "%s moves up to %s" % [who, n]
		"KNOCKBACK":
			return "Knock %s back %s" % [who, n]
	return action_to_fx(a)


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
	var head: PackedStringArray = line.substr(0, colon).strip_edges().to_upper().split(" ", false)
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
			"LAUNCH":
				e.launch = true
			"RANGE":
				e.range = true
			"IF":
				if i + 1 >= head.size() or not CONDS.has(head[i + 1]):
					return null
				e.cond = head[i + 1]
				i += 1
				if i + 1 < head.size():
					e.cond_arg = head[i + 1]
					i += 1
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
	return e


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
