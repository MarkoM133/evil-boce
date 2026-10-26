class_name FxTextParser
extends RefCounted
## Reads card text written with the phrases from the card text guide and writes fx lines
## (FxEffect). Sentences it does not understand come back in `unparsed`; such a card needs a
## hand-written `fx` in the web app before it is playable.

const PHASES: Dictionary[String, String] = {
	"start": "START", "preroll": "PREROLL", "roll": "ROLL", "postroll": "POSTROLL", "battle": "BATTLE", "end": "END",
}
const STAT_WORDS: Dictionary[String, String] = {
	"power": "PWR", "pwr": "PWR", "[pwr]": "PWR",
	"dmg": "DMG", "damage": "DMG", "[dmg]": "DMG",
	"kb": "KB", "knockback": "KB", "[kb]": "KB",
	"range": "RNG", "rng": "RNG", "[rng]": "RNG",
	"hp": "HP", "[hp]": "HP",
}

static var _re: Dictionary[String, RegEx] = {}
## Traits of the sentence being parsed, in their original case ({Sword}, not {sword}).
static var _traits: PackedStringArray = PackedStringArray()


## {"fx": String (one line per sentence), "unparsed": PackedStringArray}
static func parse(card: CardDef) -> Dictionary:
	var lines := PackedStringArray()
	var unparsed := PackedStringArray()
	var text: String = card.text.replace("\r", "")
	# The stage terrain line is data, not an effect.
	var kept := PackedStringArray()
	for l: String in text.split("\n"):
		if not l.strip_edges().to_lower().begins_with("terrain:"):
			kept.append(l)
	text = "\n".join(kept)
	if text.strip_edges().is_empty():
		return {"fx": "", "unparsed": unparsed}
	var self_name: String = card.hero if card.type == "Evolution" and not card.hero.is_empty() else card.name
	var t: String = _normalise(text, self_name)
	for sentence: String in _sentences(t):
		var e: FxEffect = _parse_sentence(sentence, card)
		if e == null:
			unparsed.append(sentence)
		else:
			lines.append(e.to_fx())
	return {"fx": "\n".join(lines), "unparsed": unparsed}


static func _normalise(text: String, self_name: String) -> String:
	var t: String = text
	if not self_name.is_empty():
		var first: String = self_name.split(",")[0].strip_edges()
		t = t.replace(self_name + "'s", "SELF's").replace(self_name, "SELF")
		if first != self_name:
			t = t.replace(first + "'s", "SELF's").replace(first, "SELF")
	t = t.replace("\n- ", " | ").replace("\n", " ")
	t = _rx("\\s+").sub(t, " ", true).strip_edges()
	return t


static func _sentences(t: String) -> PackedStringArray:
	var out := PackedStringArray()
	for s: String in _rx("(?<=[.!?])\\s+(?=[A-Z\\[])").sub(t, "\n", true).split("\n"):
		var x: String = s.strip_edges().trim_suffix(".").strip_edges()
		if not x.is_empty():
			out.append(x)
	return out


static func _parse_sentence(sentence: String, card: CardDef) -> FxEffect:
	var e := FxEffect.new()
	var s: String = sentence
	_traits = PackedStringArray()
	for tm: RegExMatch in _rx("\\{(\\w+)\\}").search_all(s):
		_traits.append(tm.get_string(1))
	if s.begins_with("[Range] ") or s.begins_with("[Range]"):
		e.range = true
		s = s.trim_prefix("[Range]").strip_edges()
	var m: RegExMatch = _rx("^(Preroll|Roll|Postroll|Battle|End)(?: Phase)?( Once Per Turn)?:\\s*(.*)$").search(s)
	if m != null:
		e.when = PHASES[m.get_string(1).to_lower()]
		e.once = not m.get_string(2).is_empty()
		s = m.get_string(3).strip_edges()
	elif card.type == "Action":
		e.when = "PLAY"
	else:
		e.when = "PASSIVE"
	var low: String = s.to_lower()
	m = _rx("^when this stage is revealed, (.*)$").search(low)
	if m != null:
		e.when = "REVEAL"
		low = m.get_string(1)
	m = _rx("^while self is activated, (.*)$").search(low)
	if m != null:
		e.when = "PASSIVE"
		e.cond = "ACTIVATED"
		low = m.get_string(1)
	m = _rx("^if you win this battle, (.*)$").search(low)
	if m != null:
		e.cond = "WIN"
		low = m.get_string(1)
	m = _rx("^if self (?:is|was) activated(?: this turn)?, (.*)$").search(low)
	if m != null:
		e.cond = "ACTIVATED"
		low = m.get_string(1)
	m = _rx("^(.*?),? if the equipped hero is activated$").search(low)
	if m != null:
		e.cond = "ACTIVATED"
		low = m.get_string(1)
	if low.begins_with("self may ") or low.begins_with("you may ") or low.begins_with("may "):
		e.optional = true
		low = _rx("^(?:self |you )?may (?:choose to )?").sub(low, "")
	elif low.contains(" may "):
		e.optional = true
		low = low.replace(" may ", " ")
	if low.is_empty():
		return e
	var actions: Array[Dictionary] = _clause(low)
	if actions.is_empty():
		return null
	e.actions = actions
	return e


## Actions for one clause; [] when nothing matched. Clauses joined by "and" or "," are read
## one by one when the whole does not match.
static func _clause(low: String) -> Array[Dictionary]:
	var direct: Array[Dictionary] = _match(low)
	if not direct.is_empty():
		return direct
	var tail: String = ""
	var m: RegExMatch = _rx("^(.*?)( until the end of the turn| this turn)$").search(low)
	var body: String = low
	if m != null:
		body = m.get_string(1)
		tail = m.get_string(2)
	for sep: String in [" and ", ", "]:
		if not body.contains(sep):
			continue
		var parts: PackedStringArray = body.split(sep)
		var all: Array[Dictionary] = []
		for p: String in parts:
			var sub: Array[Dictionary] = _match(p.strip_edges() + tail)
			if sub.is_empty():
				all.clear()
				break
			all.append_array(sub)
		if not all.is_empty():
			return all
	return []


static func _match(low: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var m: RegExMatch

	# Opponent chooses between two lists.
	m = _rx("^your opponent chooses: \\| (.*) \\| (.*)$").search(low)
	if m != null:
		var a: Array[Dictionary] = _clause(m.get_string(1).strip_edges())
		var b: Array[Dictionary] = _clause(m.get_string(2).strip_edges())
		if a.is_empty() or b.is_empty():
			return out
		out.append({"verb": "CHOOSE", "target": "OPP", "args": PackedStringArray(), "branches": [a, b]})
		return out

	m = _rx("^as an additional cost, take (\\d+) dmg$").search(low)
	if m != null:
		return [_act("COST_DAMAGE", "", [m.get_string(1)])]

	# Stat bonuses: "<subject> gains +2000 Power [and +1 DMG] [for every X] [until the end of the turn]"
	m = _rx("^(.*?)(?:gains?|has|have|get)?\\s*((?:[+-]\\d+ (?:power|pwr|\\[pwr\\]|dmg|damage|\\[dmg\\]|kb|knockback|\\[kb\\]|range|rng|\\[rng\\]|hp|\\[hp\\])(?:,? and |, )?)+)(?: for every (.+?))?( until the end of the turn| this turn)?$").search(low)
	if m != null:
		var target: String = _subject(m.get_string(1))
		if not target.is_empty():
			var per: PackedStringArray = _counter(m.get_string(3))
			if m.get_string(3).is_empty() or not per.is_empty():
				var dur: bool = not m.get_string(4).is_empty()
				for pair: RegExMatch in _rx("([+-]\\d+) (power|pwr|\\[pwr\\]|dmg|damage|\\[dmg\\]|kb|knockback|\\[kb\\]|range|rng|\\[rng\\]|hp|\\[hp\\])").search_all(m.get_string(2)):
					var args: Array = [STAT_WORDS[pair.get_string(2)], pair.get_string(1).trim_prefix("+")]
					if dur:
						args.append("TURN")
					if not per.is_empty():
						args.append("PER")
						args.append_array(per)
					out.append(_act("BUFF", target, args))
				return out

	m = _rx("^(.*?)\\s*takes? ([+-]\\d+) dmg from all sources( this turn)?$").search(low)
	if m != null:
		var target: String = _subject(m.get_string(1))
		if not target.is_empty():
			var args: Array = [m.get_string(2).trim_prefix("+")]
			if not m.get_string(3).is_empty():
				args.append("TURN")
			return [_act("DAMAGE_MOD", target, args)]

	m = _rx("^(.*?)\\s*takes? (\\d+ dmg|dmg)$").search(low)
	if m != null:
		var target: String = _subject(m.get_string(1))
		if not target.is_empty():
			var n: String = m.get_string(2).trim_suffix(" dmg")
			return [_act("DAMAGE", target, [n.to_upper()])]

	m = _rx("^(?:deactivate a core to )?(.*?)\\s*heals? (\\d+) hp$").search(low)
	if m == null:
		# "heal a friendly Hero 2 HP": verb first, then the target.
		m = _rx("^(?:deactivate a core to )?heal (.+?) (\\d+) hp$").search(low)
	if m != null:
		var target: String = _subject(m.get_string(1))
		if not target.is_empty():
			if low.begins_with("deactivate a core to "):
				out.append(_act("DEACTIVATE_CORE", "SELF", ["1"]))
			out.append(_act("HEAL", target, [m.get_string(2)]))
			return out

	m = _rx("^(.*?)\\s*move up to (\\d+) spaces?$").search(low)
	if m != null:
		# Only the card's own hero moves for now; group moves need per-hero choices.
		if _subject(m.get_string(1)) == "SELF":
			return [_act("MOVE", "SELF", [m.get_string(2)])]

	m = _rx("^knockback an opponent's hero (\\d+) spaces?(?: in the opposite direction of your hero| away from (?:your hero|you))?$").search(low)
	if m != null:
		return [_act("KNOCKBACK", "ENEMY", [m.get_string(1), "AWAY"])]
	m = _rx("^make an opponent's hero move (\\d+) spaces? towards you$").search(low)
	if m != null:
		return [_act("KNOCKBACK", "ENEMY", [m.get_string(1), "TOWARDS"])]

	m = _rx("^(.*?)\\s*(?:is )?immune to knockback( this turn)?$").search(low)
	if m != null:
		var target: String = _subject(m.get_string(1))
		if not target.is_empty():
			return [_act("STATUS", target, ["IMMUNE_KB", "TURN"])]

	m = _rx("^place a wall(?: \\(line of (\\d+)\\))?$").search(low)
	if m != null:
		return [_act("WALL", "", [m.get_string(1)] if not m.get_string(1).is_empty() else [])]
	if low == "reveal a core":
		return [_act("REVEAL_CORE", "", [])]
	if low == "activate a core":
		return [_act("ACTIVATE_CORE", "", [])]
	m = _rx("^deactivate (?:a core|up to (\\d+) cores)$").search(low)
	if m != null:
		return [_act("DEACTIVATE_CORE", "SELF", [m.get_string(1) if not m.get_string(1).is_empty() else "1"])]

	m = _rx("^(?:you |they )?(?:must )?(charge|discharge) (\\d+) energy$").search(low)
	if m != null:
		var who: String = "OPP" if low.begins_with("they ") else "ME"
		return [_act(m.get_string(1).to_upper(), who, [m.get_string(2)])]

	m = _rx("^your \\{(\\w+)\\} cards cost (\\d+) less(?: to play)?$").search(low)
	if m != null:
		return [_act("COST", "ME", ["-" + m.get_string(2), "{%s}" % m.get_string(1)])]
	m = _rx("^your opponent's cards have \\+(\\d+) cost$").search(low)
	if m != null:
		return [_act("COST", "OPP", [m.get_string(1)])]
	m = _rx("^all of your opponent's (\\w+) phase cards cost (\\d+) more energy this turn$").search(low)
	if m != null:
		return [_act("COST", "OPP", [m.get_string(2), m.get_string(1).to_upper(), "TURN"])]

	m = _rx("^(?:you )?roll (?:the activated hero|self|him|her|this hero) (?:again|one additional time)(?: when activated)?$").search(low)
	if m != null:
		return [_act("ROLL_AGAIN", "", [])]
	m = _rx("^(?:you may )?(?:reverse (?:the|this) roll|return (?:the activated hero|self|him|her|this hero) to where (?:it|he|she) (?:was|stood) before (?:the|this) roll)$").search(low)
	if m != null:
		return [_act("REVERSE_ROLL", "", [])]

	if low == "your opponent must discard a card":
		return [_act("DISCARD", "OPP", ["1"])]
	m = _rx("^(?:you )?draw (\\d+) cards?$").search(low)
	if m != null:
		return [_act("DRAW", "ME", [m.get_string(1)])]
	if low == "remove an evolution from your opponent's hero":
		return [_act("REMOVE_EVO", "ENEMY", [])]
	m = _rx("^your opponent cannot (?:take|claim) a stage this turn$").search(low)
	if m != null:
		return [_act("NO_CLAIM", "OPP", [])]
	return out


## Target for a sentence subject; "" when the subject is unknown.
static func _subject(raw: String) -> String:
	var s: String = raw.strip_edges().trim_suffix(",").strip_edges()
	match s:
		"", "self", "this hero", "your hero", "he", "she", "you", "self's", "i":
			return "SELF"
		"the equipped hero", "equipped hero":
			return "EQUIPPED"
		"an opponent's hero", "your opponent's hero", "their hero", "the opponent's hero", "they":
			return "ENEMY"
		"a friendly hero", "friendly hero":
			return "FRIENDLY"
		"all friendly heroes", "all friendly characters", "friendly heroes":
			return "ALL_FRIENDLY"
		"all other heroes in range", "all other heroes in self's range":
			return "ALL_OTHER_IN_RANGE"
		"all friendly heroes in range", "all friendly characters in self's range", "all friendly heroes in self's range", "all friendly characters in range":
			return "ALL_FRIENDLY_IN_RANGE"
		"each hero", "all heroes":
			return "EACH_HERO"
		"the hero with more hp":
			return "MOST_HP"
		"the hero with more power":
			return "MOST_PWR"
	return ""


## PER counter for "for every X"; [] when unknown.
static func _counter(raw: String) -> PackedStringArray:
	var s: String = raw.strip_edges()
	if s.is_empty():
		return PackedStringArray()
	var m: RegExMatch = _rx("^\\{(\\w+)\\} (?:equipped|they have equipped)$").search(s)
	if m != null:
		return PackedStringArray(["TRAIT_EQUIPPED", "{%s}" % m.get_string(1)])
	m = _rx("^equipped \\{(\\w+)\\}(?: they have)?$").search(s)
	if m != null:
		return PackedStringArray(["TRAIT_EQUIPPED", "{%s}" % m.get_string(1)])
	if _rx("^activated core(?: they have)?$").search(s) != null:
		return PackedStringArray(["CORES"])
	m = _rx("^(\\d+) missing hp$").search(s)
	if m != null:
		return PackedStringArray(["MISSING_HP", m.get_string(1)])
	if _rx("^charged energy(?: their player has)?$").search(s) != null:
		return PackedStringArray(["ENERGY"])
	m = _rx("^friendly (?:character|hero) who has (\\d+) or less hp$").search(s)
	if m != null:
		return PackedStringArray(["LOW_HP_FRIENDLY", m.get_string(1)])
	return PackedStringArray()


static func _act(verb: String, target: String, args: Array) -> Dictionary:
	var packed := PackedStringArray()
	for a: Variant in args:
		packed.append(_trait_case(str(a)))
	return {"verb": verb, "target": target, "args": packed}


## "{sword}" back to "{Sword}" as the card wrote it.
static func _trait_case(token: String) -> String:
	if not token.begins_with("{"):
		return token
	var name: String = token.trim_prefix("{").trim_suffix("}")
	for t: String in _traits:
		if t.to_lower() == name.to_lower():
			return "{%s}" % t
	return token


static func _rx(pattern: String) -> RegEx:
	if not _re.has(pattern):
		var r := RegEx.new()
		r.compile(pattern)
		_re[pattern] = r
	return _re[pattern]
