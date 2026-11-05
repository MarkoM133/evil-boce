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
		if l.strip_edges().to_lower().begins_with("terrain:"):
			continue
		# A bonus line is a sentence of its own, even after a bare phase ("Battle Phase:").
		if _is_bonus(l.strip_edges()) and not kept.is_empty() and _rx("[.!?]\\s*$").search(kept[kept.size() - 1]) == null:
			kept[kept.size() - 1] = kept[kept.size() - 1].strip_edges() + "."
		kept.append(l)
	text = "\n".join(kept)
	if text.strip_edges().is_empty():
		return {"fx": "", "unparsed": unparsed}
	var self_name: String = card.hero if card.type == "Evolution" and not card.hero.is_empty() else card.name
	var t: String = _normalise(text, self_name)
	# Elbaph (2026-11-05): a duel in every battle on the stage; the winner picks one hero in it for the bonus.
	var duel: RegExMatch = _rx("(?i)in a battle on this stage, each player reveals the top card of their deck\\. the player who revealed the higher[- ]cost card chooses one of their heroes in this battle\\. that hero gets \\+(\\d+) (\\w+)\\.?").search(t)
	if duel != null:
		t = t.substr(0, duel.get_start()) + "Duel for +%s %s." % [duel.get_string(1), duel.get_string(2)] + t.substr(duel.get_end())
	# Egghead (2026-11-05): the player with more Energy picks one of their heroes in the battle for the bonus.
	var rich: RegExMatch = _rx("(?i)the player with (?:more|the most) energy chooses one of their heroes in this battle\\. that hero gets \\+(\\d+) (\\w+)\\.?").search(t)
	if rich != null:
		t = t.substr(0, rich.get_start()) + "Most energy pick for +%s %s." % [rich.get_string(1), rich.get_string(2)] + t.substr(rich.get_end())
	# A colour bonus sentence ("Red Bonus: …", 2026-11-01) leans on the sentence before it.
	var prev: FxEffect = null
	var prev_sentence: String = ""
	var prev_line: int = -1
	# "Choose an Opponent's Hero in Range." names the target of the next sentence ("Knock them back 3 spaces.").
	var chosen: String = ""
	var chosen_head: String = ""
	for raw_sentence: String in _sentences(t):
		var sentence: String = raw_sentence
		var low: String = sentence.to_lower()
		# A sentence that only spells out a rule the fx word already holds (FULL_HIT: no cards from the hand).
		if _rx("^your opponent (?:can't|cannot|can not) discard cards to (?:reduce|lower|pay) (?:it|this|that|the damage)$").search(low) != null:
			continue
		var cm: RegExMatch = _rx("^((?:\\[range\\] )?(?:start|preroll|roll|postroll|battle|end)(?: phase)?(?: once per turn)?: )?choose (an opponent's hero|a friendly hero)( in range)?$").search(low)
		if cm != null:
			chosen = cm.get_string(2) + cm.get_string(3)
			chosen_head = sentence.substr(0, cm.get_string(1).length())
			continue
		if not chosen.is_empty():
			sentence = chosen_head + _rx("\\b(them|they|it)\\b").sub(sentence, chosen)
			low = sentence.to_lower()
			chosen = ""
			chosen_head = ""
		# A follow-on sentence adds to the effect before it (Marko 2026-11-05): "If he does, a friendly Hero in Range
		# heals 2 HP." (Giorno), "If an Opponent's Hero activates that Core this turn, they take 3 DMG." (Life Giver).
		var fm: RegExMatch = _rx("^if (?:he|she|it) does, (.*)$|^if (?:you|they) do, (.*)$").search(low)
		var trap: RegExMatch = _rx("^if an opponent's hero activates that core this turn,? (?:they take|it takes) (\\d+) dmg$").search(low)
		if prev != null and prev_line >= 0 and (fm != null or trap != null):
			var tail: FxEffect = null
			if trap != null:
				tail = FxEffect.new()
				tail.actions = [_act("TRAP_CORE", "", [trap.get_string(1)])]
			else:
				var rest: String = fm.get_string(1) if not fm.get_string(1).is_empty() else fm.get_string(2)
				tail = _parse_sentence(rest[0].to_upper() + rest.substr(1), card)
			if tail != null and not tail.actions.is_empty():
				prev.actions.append_array(tail.actions)
				prev.range = prev.range or tail.range
				lines[prev_line] = prev.to_fx()
				prev_sentence = sentence
				continue
		var e: FxEffect = _parse_sentence(sentence, card, prev, prev_sentence)
		if e == null:
			unparsed.append(sentence)
		else:
			lines.append(e.to_fx())
		if not _is_bonus(sentence):
			prev = e
			prev_line = lines.size() - 1 if e != null else -1
			prev_sentence = sentence
	return {"fx": "\n".join(lines), "unparsed": unparsed}


const BONUS_HEAD: String = "^((?:Cyan|Yellow|Purple|Red|Blue|Green)(?:\\s*/\\s*(?:Cyan|Yellow|Purple|Red|Blue|Green))*)\\s+Bonus:\\s*(.*)$"
const STAT_WORD: String = "(?:power|pwr|\\[pwr\\]|dmg|damage|\\[dmg\\]|kb|knockback|\\[kb\\]|range|rng|\\[rng\\]|hp|\\[hp\\])"


static func _is_bonus(sentence: String) -> bool:
	return _rx(BONUS_HEAD).search(sentence) != null


## A bonus sentence: the colours, then what the bonus is. "This card costs N less to play" is
## OWN_COST; "+N STAT" a buff on the card's hero; "It also …" an extra effect; "It … N …
## instead" the sentence before with its number swapped, replacing it (INSTEAD). Anything else
## is read as a sentence of its own. The effect takes the WHEN and flags of the sentence before.
static func _parse_bonus(colors: String, rest: String, card: CardDef, prev: FxEffect, prev_sentence: String) -> FxEffect:
	var names: PackedStringArray = colors.split("/", false)
	var e: FxEffect = null
	var low: String = rest.strip_edges().trim_suffix(".").strip_edges().to_lower()
	var instead: bool = low.ends_with(" instead")
	if instead:
		low = low.trim_suffix(" instead").strip_edges()
	var m: RegExMatch = _rx("^this card costs (\\d+) (?:energy )?(less|more)(?: to play)?$").search(low)
	if m != null:
		e = FxEffect.new()
		e.when = "PLAY"
		e.actions = [_act("OWN_COST", "", [("-" if m.get_string(2) == "less" else "") + m.get_string(1)])]
	elif _rx("^[+-]\\d+ " + STAT_WORD + "$").search(low) != null:
		var who: String = "the equipped hero gains " if card.type == "Equipment" else "self gains "
		e = FxEffect.new()
		e.when = "PASSIVE" if card.type == "Equipment" or card.type == "Assist" else (prev.when if prev != null else "PLAY")
		e.actions = _clause(who + low)
	elif instead and low.begins_with("it ") and prev != null:
		# "It heals 4 HP instead": the sentence before, its one number replaced by this one.
		var nums: Array[RegExMatch] = _rx("[+-]?\\d+").search_all(low)
		var old: Array[RegExMatch] = _rx("[+-]?\\d+").search_all(prev_sentence)
		if nums.size() == 1 and old.size() == 1:
			var swapped: String = prev_sentence.substr(0, old[0].get_start()) + nums[0].get_string() + prev_sentence.substr(old[0].get_end())
			e = _parse_sentence(swapped, card)
	else:
		var text: String = rest.strip_edges().trim_suffix(".").strip_edges()
		if instead:
			text = _rx("\\s+instead$").sub(text, "")
		# "It also …", "You also …": the extra effect; "It" is the card's hero.
		text = _rx("^(It|You|They|SELF) also ").sub(text, "$1 ")
		# "… gets an additional +1000 Power" (Marko 2026-11-05): more on top of the sentence before, with its
		# condition; the same as "It also gains +1000 Power".
		var additional: bool = _rx("\\b(gets?|gains?|takes?|heals?) an additional ").search(rest) != null
		text = _rx("\\b(gets?|gains?|takes?|heals?) an additional ").sub(text, "$1 ")
		# "They move 1 additional space" (Taunt): the same pull or push as the sentence before, N more.
		var mv: RegExMatch = _rx("^they move (\\d+) additional spaces?$").search(text.to_lower())
		if mv != null and prev != null and not prev.actions.is_empty() and str(prev.actions[prev.actions.size() - 1]["verb"]) == "KNOCKBACK":
			var pargs: PackedStringArray = prev.actions[prev.actions.size() - 1]["args"]
			var away: bool = pargs.size() < 2 or pargs[1] != "TOWARDS"
			text = ("Knockback an opponent's hero %s spaces away from you" if away else "Make an opponent's hero move %s spaces towards you") % mv.get_string(1)
			additional = true
		if text.to_lower().begins_with("it "):
			text = "SELF " + text.substr(3)
		# "They …" in a bonus line is the hero the sentence before picked.
		var they: bool = text.to_lower().begins_with("they ")
		e = _parse_sentence(text, card)
		if e != null and they and prev != null and not prev.actions.is_empty():
			var last: Dictionary = prev.actions[prev.actions.size() - 1]
			for a: Dictionary in e.actions:
				if FxEffect.HERO_TARGETS.has(str(a["target"])) and FxEffect.HERO_TARGETS.has(str(last["target"])):
					a["target"] = last["target"]
		if e != null and additional and prev != null and e.actions.size() == 1 and not prev.actions.is_empty():
			var last: Dictionary = prev.actions[prev.actions.size() - 1]
			var a: Dictionary = e.actions[0]
			var pa: PackedStringArray = last["args"]
			var aa: PackedStringArray = a["args"]
			if a["verb"] == last["verb"] and a["target"] == last["target"] and ["ENEMY", "FRIENDLY"].has(str(a["target"])) \
					and pa.size() == aa.size() and pa.size() >= 1 and pa[0].is_valid_int() and aa[0].is_valid_int():
				aa[0] = str(pa[0].to_int() + aa[0].to_int())
				a["args"] = aa
				instead = true
		if e != null and prev != null and _rx("^(?:\\[Range\\] ?)?(Start|Preroll|Roll|Postroll|Battle|End)").search(text) == null:
			e.when = prev.when
			e.range = prev.range
			e.once = prev.once
			if e.cond.is_empty():
				e.cond = prev.cond
				e.cond_arg = prev.cond_arg
	if e == null or e.actions.is_empty():
		return null
	e.bonus = true
	if names.size() == 1:
		var colour: String = names[0].strip_edges().to_upper()
		if not (card.bonus_colors.size() == 1 and card.bonus_colors[0].to_upper() == colour):
			e.bonus_color = colour
	# A bonus that lasts as long as the sentence before ("… this turn" / "They take 1 less DMG from each source").
	if prev != null and not prev.actions.is_empty():
		var prev_args: PackedStringArray = prev.actions[prev.actions.size() - 1]["args"]
		if prev_args.has("TURN"):
			for a: Dictionary in e.actions:
				var args: PackedStringArray = a["args"]
				if ["DAMAGE_MOD", "BUFF", "STATUS"].has(str(a["verb"])) and not args.has("TURN"):
					args.append("TURN")
					a["args"] = args
	e.instead = instead
	if instead and prev != null:
		e.when = prev.when
	return e


static func _normalise(text: String, self_name: String) -> String:
	var t: String = text
	if not self_name.is_empty():
		var first: String = self_name.split(",")[0].strip_edges()
		t = t.replace(self_name + "'s", "SELF's").replace(self_name, "SELF")
		if first != self_name:
			t = t.replace(first + "'s", "SELF's").replace(first, "SELF")
		# The first name alone ("Giorno may …", cards name the hero only on Hero and Evolution cards, 2026-11-05).
		for word: String in first.split(" "):
			if word != first and word.length() >= 4:
				t = _rx("\\b" + word + "\\b").sub(t, "SELF", true)
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


static func _parse_sentence(sentence: String, card: CardDef, prev: FxEffect = null, prev_sentence: String = "") -> FxEffect:
	var e := FxEffect.new()
	var s: String = sentence
	var bm: RegExMatch = _rx(BONUS_HEAD).search(s)
	if bm != null:
		return _parse_bonus(bm.get_string(1), bm.get_string(2), card, prev, prev_sentence)
	_traits = PackedStringArray()
	for tm: RegExMatch in _rx("\\{(\\w+)\\}").search_all(s):
		_traits.append(tm.get_string(1))
	if s.begins_with("[Range] ") or s.begins_with("[Range]"):
		e.range = true
		s = s.trim_prefix("[Range]").strip_edges()
	var m: RegExMatch = _rx("^(Start|Preroll|Roll|Postroll|Battle|End)(?: Phase)?( Once Per Turn)?:\\s*(.*)$").search(s)
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
	# A stage's battle effect: "In a Battle on this Stage, …" (fires at the start of every battle fought on it).
	m = _rx("^in a battle on this stage, (.*)$").search(low)
	if m != null:
		e.when = "BATTLE"
		low = m.get_string(1)
	m = _rx("^while (?:self|the equipped hero) is activated, (.*)$").search(low)
	if m != null:
		e.when = "PASSIVE"
		e.cond = "ACTIVATED"
		low = m.get_string(1)
	# "If the equipped Hero is activated, lose 1 Energy." (Enma, 2026-11-05)
	m = _rx("^if the equipped hero is activated, (.*)$").search(low)
	if m != null:
		e.cond = "ACTIVATED"
		low = m.get_string(1)
	# "If the Opponent's Hero in this Battle has a {Sword} equipped, …" (Mihawk)
	m = _rx("^if (?:the|an) opponent's hero(?: in this battle)? (?:has|is equipped with) an? \\{(\\w+)\\}(?: equipped)?, (.*)$").search(low)
	if m != null:
		e.cond = "OPP_EQUIPPED"
		e.cond_arg = _trait_case("{%s}" % m.get_string(1))
		low = m.get_string(2)
	# Range rule B (Marko and Tarik 2026-11-05): range is written next to its target. "If an Opponent's Hero is
	# in Range, …" makes the whole card need an enemy in range; "a Core in Range", "an Opponent's Hero in Range" …
	# set RANGE and read on without it. Group phrases ("all other Heroes in Range") keep their own target word.
	m = _rx("^if an opponent's hero is in range, (.*)$").search(low)
	if m != null:
		e.range = true
		low = m.get_string(1)
	# "Your Opponent in Range chooses one:" (Soul Pocus): an enemy hero must be in range to play the card.
	if low.begins_with("your opponent in range chooses"):
		e.range = true
		low = low.replace("your opponent in range chooses", "your opponent chooses")
	var rr: RegEx = _rx("\\b(an opponent's hero|another friendly hero|a friendly hero|a core|that core|a wall on an empty space|a wall) in (?:range|your hero's range)\\b")
	if rr.search(low) != null:
		e.range = true
		low = rr.sub(low, "$1", true)
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
	# ", friendly or not" only spells out what ALL_OTHER_IN_RANGE already means (Fugo).
	low = _rx(",? friendly or not$").sub(low, "")
	if low.begins_with("self may ") or low.begins_with("you may ") or low.begins_with("may "):
		e.optional = true
		low = _rx("^(?:self |you )?may (?:choose to )?").sub(low, "")
	elif low.contains(" may "):
		e.optional = true
		low = low.replace(" may ", " ")
	# An Action needs no OPTIONAL: playing the card is the "may" (fx-keywords).
	if card.type == "Action":
		e.optional = false
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
	m = _rx("^your opponent chooses(?: one)?: \\| (.*) \\| (.*)$").search(low)
	if m != null:
		var a: Array[Dictionary] = _clause(m.get_string(1).strip_edges().trim_suffix("."))
		var b: Array[Dictionary] = _clause(m.get_string(2).strip_edges().trim_suffix("."))
		if a.is_empty() or b.is_empty():
			return out
		out.append({"verb": "CHOOSE", "target": "OPP", "args": PackedStringArray(), "branches": [a, b]})
		return out

	# "As an additional cost, take 3 DMG." or "…, your Hero takes 3 DMG." (Marko 2026-11-05).
	m = _rx("^as an additional cost, (?:take|your hero takes) (\\d+) dmg$").search(low)
	if m != null:
		return [_act("COST_DAMAGE", "", [m.get_string(1)])]

	# Stat bonuses: "<subject> gains +2000 Power [and +1 DMG] [for every X] [until the end of the turn]"
	m = _rx("^(.*?)(?:gains?|has|have|gets?)?\\s*((?:[+-]\\d+ (?:power|pwr|\\[pwr\\]|dmg|damage|\\[dmg\\]|kb|knockback|\\[kb\\]|range|rng|\\[rng\\]|hp|\\[hp\\])(?:,? and |, )?)+)(?: for (?:every|each) (.+?))?( until the end of the turn| this turn)?$").search(low)
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

	# "takes -1 DMG from all sources", "takes 1 less DMG from each source" (Kaido, 2026-11-05)
	m = _rx("^(.*?)\\s*takes? (?:([+-]\\d+) dmg|(\\d+) (less|more) dmg) from (?:all|each|every) sources?( this turn)?$").search(low)
	if m != null:
		var target: String = _subject(m.get_string(1))
		if not target.is_empty():
			var n: String = m.get_string(2).trim_prefix("+") if not m.get_string(2).is_empty() else ("-" if m.get_string(4) == "less" else "") + m.get_string(3)
			var args: Array = [n]
			if not m.get_string(5).is_empty():
				args.append("TURN")
			return [_act("DAMAGE_MOD", target, args)]

	m = _rx("^(.*?)\\s*takes? (\\d+ dmg|dmg)( that (?:can't|cannot) be (?:reduced|blocked))?$").search(low)
	if m != null:
		var target: String = _subject(m.get_string(1))
		if not target.is_empty():
			var n: String = m.get_string(2).trim_suffix(" dmg")
			var args: Array = [n.to_upper()]
			if not m.get_string(3).is_empty():
				args.append("TRUE")
			return [_act("DAMAGE", target, args)]

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

	# "Knockback an Opponent's Hero 3 spaces, away from your Hero" / "Knock an Opponent's Hero back 3 spaces"
	m = _rx("^knock(?:back)? an opponent's hero (?:back )?(\\d+) spaces?(?:,? (?:in the opposite direction of your hero|away from (?:your hero|you)))?$").search(low)
	if m != null:
		return [_act("KNOCKBACK", "ENEMY", [m.get_string(1), "AWAY"])]
	# "Swap your Hero with another friendly Hero that is in an Opponent's Hero's Range" (Intercept)
	m = _rx("^swap your hero with (?:another|a) friendly hero( that is in an opponent's hero's range)?$").search(low)
	if m != null:
		return [_act("SWAP", "FRIENDLY", ["ENGAGED"] if not m.get_string(1).is_empty() else [])]
	# "Move a Core up to 2 spaces" (Life Giver); the trap sentence after it adds TRAP_CORE.
	m = _rx("^move a core up to (\\d+) spaces?$").search(low)
	if m != null:
		return [_act("PICK_CORE", "", []), _act("MOVE_CORE", "", [m.get_string(1)])]
	m = _rx("^most energy pick for \\+(\\d+) (\\w+)$").search(low)
	if m != null and STAT_WORDS.has(m.get_string(2)):
		return [_act("BUFF", "MOST_ENERGY", [STAT_WORDS[m.get_string(2)], m.get_string(1), "PICK"])]
	m = _rx("^duel for \\+(\\d+) (\\w+)$").search(low)
	if m != null and STAT_WORDS.has(m.get_string(2)):
		return [_act("DUEL_TOP", "", [STAT_WORDS[m.get_string(2)], m.get_string(1), "PICK"])]
	# "Opponent's Heroes in Range can't claim a Stage this turn" (Conqueror's Haki, 2026-11-05)
	if _rx("^(?:your )?opponent's heroes in range (?:can't|cannot) claim a stage this turn$").search(low) != null:
		return [_act("NO_CLAIM", "ALL_ENEMY_IN_RANGE", [])]
	if _rx("^(?:your )?opponent's heroes (?:can't|cannot) claim a stage this turn$").search(low) != null:
		return [_act("NO_CLAIM", "OPP", [])]
	# "deactivate a Core to play a {Sword} Equipment with a cost of 3 or less without paying its cost" (Zoro)
	m = _rx("^(?:deactivate a core to )?play an? (?:\\{(\\w+)\\} )?(action|equipment|assist)?(?: card)? ?with a cost of (\\d+) or less (?:without paying its cost|for free)$").search(low)
	if m != null:
		var args: Array = [m.get_string(3)]
		if not m.get_string(1).is_empty():
			args.append("{%s}" % m.get_string(1))
		if not m.get_string(2).is_empty():
			args.append(m.get_string(2).capitalize())
		if low.begins_with("deactivate a core to "):
			out.append(_act("DEACTIVATE_CORE", "SELF", ["1"]))
		out.append(_act("FREE_PLAY", "", args))
		return out
	m = _rx("^make an opponent's hero move (\\d+) spaces? towards (?:you|your hero)$").search(low)
	if m != null:
		return [_act("KNOCKBACK", "ENEMY", [m.get_string(1), "TOWARDS"])]

	m = _rx("^(.*?)\\s*(?:is )?immune to knockback( this turn)?$").search(low)
	if m != null:
		var target: String = _subject(m.get_string(1))
		if not target.is_empty():
			return [_act("STATUS", target, ["IMMUNE_KB", "TURN"])]

	m = _rx("^place a wall(?: on an empty space)?(?: \\(line of (\\d+)\\))?$").search(low)
	if m != null:
		return [_act("WALL", "", [m.get_string(1)] if not m.get_string(1).is_empty() else [])]
	if low == "reveal a core":
		return [_act("REVEAL_CORE", "", [])]
	if low == "activate a core":
		return [_act("ACTIVATE_CORE", "", [])]
	m = _rx("^deactivate (?:a core|up to (\\d+) cores)$").search(low)
	if m != null:
		# "up to N": the player picks how many (UPTO); PER COUNT after it counts the ones taken.
		return [_act("DEACTIVATE_CORE", "SELF", [m.get_string(1), "UPTO"] if not m.get_string(1).is_empty() else ["1"])]

	# Energy: "gain 2 Energy" / "lose 2 Energy" (2026-11-05; charge / discharge still read), "they lose …" is the opponent.
	m = _rx("^(?:you |they |your opponent )?(?:must )?(gain|lose|charge|discharge) (\\d+) energy$").search(low)
	if m != null:
		var who: String = "OPP" if low.begins_with("they ") or low.begins_with("your opponent ") else "ME"
		var verb: String = "CHARGE" if m.get_string(1) in ["gain", "charge"] else "DISCHARGE"
		return [_act(verb, who, [m.get_string(2)])]

	m = _rx("^your \\{(\\w+)\\} cards cost (\\d+) (?:energy )?(less|more)(?: to play)?$").search(low)
	if m != null:
		return [_act("COST", "ME", [("-" if m.get_string(3) == "less" else "") + m.get_string(2), "{%s}" % m.get_string(1)])]
	m = _rx("^your opponent's cards (?:have \\+(\\d+) cost|cost (\\d+) (?:energy )?more)$").search(low)
	if m != null:
		return [_act("COST", "OPP", [m.get_string(1) if not m.get_string(1).is_empty() else m.get_string(2)])]
	# "All of your Opponent's Battle Phase cards cost 2 more Energy this turn" / "… cost 2 Energy more this turn"
	m = _rx("^(?:all of )?your opponent's (\\w+) phase cards cost (\\d+) (?:more energy|energy more)( this turn)?$").search(low)
	if m != null:
		var args: Array = [m.get_string(2), m.get_string(1).to_upper()]
		if not m.get_string(3).is_empty():
			args.append("TURN")
		return [_act("COST", "OPP", args)]

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
	if _rx("^remove (?:an|the top) evolution from (?:your|the) opponent's hero(?: in this battle)?$").search(low) != null:
		return [_act("REMOVE_EVO", "ENEMY", [])]
	# "After your Hero's roll, you may roll them again" (Gomu Gomu no Rocket; "may" was read above)
	if _rx("^after (?:your hero's|self's|the activated hero's|their) roll,? (?:you )?roll (?:them|him|her|it|again|self|the activated hero) ?(?:again)?$").search(low) != null:
		return [_act("ROLL_AGAIN", "", [])]
	m = _rx("^your opponent cannot (?:take|claim) a stage this turn$").search(low)
	if m != null:
		return [_act("NO_CLAIM", "OPP", [])]
	# "the Opponent's Hero in this Battle takes all of the damage" (Divine Departure, 2026-11-05).
	m = _rx("^(?:your |the )?opponent's hero(?: in this battle)? takes all (?:of )?(?:this battle's |the )?(?:battle )?damage$").search(low)
	if m != null:
		return [_act("FULL_HIT", "OPP", [])]
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
		"a friendly hero", "friendly hero", "another friendly hero":
			return "FRIENDLY"
		"all friendly heroes", "all friendly characters", "friendly heroes":
			return "ALL_FRIENDLY"
		"all other heroes in range", "all other heroes in self's range":
			return "ALL_OTHER_IN_RANGE"
		"all friendly heroes in range", "all friendly characters in self's range", "all friendly heroes in self's range", "all friendly characters in range", \
				"other friendly heroes in range", "other friendly heroes in self's range", "all other friendly heroes in range", "all other friendly heroes in self's range":
			return "ALL_FRIENDLY_IN_RANGE"
		"each hero", "all heroes", "each hero on this stage", "all heroes on this stage", "every hero on this stage":
			return "EACH_HERO"
		"the hero with more hp", "the hero on this stage with the most hp", "the hero with the most hp on this stage":
			return "MOST_HP"
		"the hero with more power", "the hero on this stage with the most power", "the hero with the most power on this stage":
			return "MOST_PWR"
		"the hero whose player has more energy", "the hero whose player has the most energy":
			return "MOST_ENERGY"
	return ""


## PER counter for "for every X"; [] when unknown.
static func _counter(raw: String) -> PackedStringArray:
	var s: String = raw.strip_edges()
	if s.is_empty():
		return PackedStringArray()
	var m: RegExMatch = _rx("^\\{(\\w+)\\} (?:equipped|they have equipped|equipped to them)$").search(s)
	if m != null:
		return PackedStringArray(["TRAIT_EQUIPPED", "{%s}" % m.get_string(1)])
	m = _rx("^equipped \\{(\\w+)\\}(?: they have)?$").search(s)
	if m != null:
		return PackedStringArray(["TRAIT_EQUIPPED", "{%s}" % m.get_string(1)])
	if _rx("^activated core(?: they have)?$").search(s) != null:
		return PackedStringArray(["CORES"])
	# "for each deactivated Core" after "deactivate up to N Cores": how many were taken.
	if _rx("^deactivated core$").search(s) != null:
		return PackedStringArray(["COUNT"])
	m = _rx("^(\\d+) missing hp$").search(s)
	if m != null:
		return PackedStringArray(["MISSING_HP", m.get_string(1)])
	if _rx("^(?:charged )?energy(?: their player has)?$").search(s) != null:
		return PackedStringArray(["ENERGY"])
	# "friendly Hero who has 5 or less HP" / "with 5 HP or less"; "other" leaves the hero itself out.
	m = _rx("^(other )?friendly (?:character|hero) (?:who has (\\d+) or less hp|with (\\d+) hp or less)$").search(s)
	if m != null:
		var n: String = m.get_string(2) if not m.get_string(2).is_empty() else m.get_string(3)
		return PackedStringArray(["LOW_HP_OTHER_FRIENDLY" if not m.get_string(1).is_empty() else "LOW_HP_FRIENDLY", n])
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
