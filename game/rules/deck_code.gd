class_name DeckCode
extends RefCounted
## The deck code shared with the web app (docs/deck-code.md): `EB1|v<n>|<heroes>|<id>*<n>,...`
## and the same checks as the app's checkDeck. A deck here is {"heroes": [ids], "cards": {id: n},
## "version": n}.

const PREFIX: String = "EB1"
const DECK_SIZE: int = 40
const HERO_COUNT: int = 3
const DECK_TYPES: Array[String] = ["Action", "Equipment", "Assist", "Evolution"]
const LIMITS: Dictionary[String, int] = {"Action": 4, "Equipment": 4, "Assist": 2, "Evolution": 2}


## {"ok": bool, "error": String, "version": int, "heroes": PackedStringArray, "cards": Dictionary}
static func decode(code: String) -> Dictionary:
	var out: Dictionary = {"ok": false, "error": "", "version": 0, "heroes": PackedStringArray(), "cards": {}}
	var parts: PackedStringArray = code.strip_edges().split("|")
	if parts.size() != 4 or parts[0] != PREFIX:
		out["error"] = "Deck code must start with %s| and have 4 parts" % PREFIX
		return out
	if not parts[1].begins_with("v") or not parts[1].substr(1).is_valid_int():
		out["error"] = "Deck code: invalid catalog version"
		return out
	out["version"] = parts[1].substr(1).to_int()
	if not parts[2].is_empty():
		out["heroes"] = parts[2].split(",")
	var cards: Dictionary = {}
	if not parts[3].is_empty():
		for item: String in parts[3].split(","):
			var star: int = item.rfind("*")
			if star <= 0 or not item.substr(star + 1).is_valid_int():
				out["error"] = "Deck code: invalid part \"%s\"" % item
				return out
			var id: String = item.substr(0, star)
			cards[id] = JsonUtil.as_int(cards.get(id, 0)) + item.substr(star + 1).to_int()
	out["cards"] = cards
	out["ok"] = true
	return out


static func encode(heroes: PackedStringArray, cards: Dictionary, version: int) -> String:
	var ids: Array[String] = []
	for k: Variant in cards:
		if JsonUtil.as_int(cards[k]) > 0:
			ids.append(str(k))
	ids.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	var items: PackedStringArray = PackedStringArray()
	for id: String in ids:
		items.append("%s*%d" % [id, JsonUtil.as_int(cards[id])])
	return "|".join([PREFIX, "v%d" % version, ",".join(heroes), ",".join(items)])


## Errors that make the deck unplayable (same rules as the app, minus the pool-size warning).
static func check(catalog: CardCatalog, heroes: PackedStringArray, cards: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if heroes.size() != HERO_COUNT:
		errors.append("pick %d heroes (now %d)" % [HERO_COUNT, heroes.size()])
	var seen: PackedStringArray = PackedStringArray()
	var colors: PackedStringArray = PackedStringArray()
	var names: PackedStringArray = PackedStringArray()
	for id: String in heroes:
		if seen.has(id):
			errors.append("the same hero is picked twice")
		seen.append(id)
		var h: CardDef = catalog.get_card(id)
		if h == null:
			errors.append("hero %s is not in the database" % id)
		elif not h.is_hero():
			errors.append("%s is not a hero" % id)
		else:
			colors.append(h.color)
			names.append(h.name)
	var count: int = 0
	for k: Variant in cards:
		var id: String = str(k)
		var n: int = JsonUtil.as_int(cards[k])
		if n <= 0:
			continue
		var c: CardDef = catalog.get_card(id)
		if c == null:
			errors.append("card %s is not in the database" % id)
			continue
		if not DECK_TYPES.has(c.type):
			errors.append("%s: %s can't go in a deck" % [c.name, c.type])
			continue
		if not colors.has(c.color):
			errors.append("%s: color %s is not a color of the chosen heroes" % [c.name, c.color])
		if c.type == "Evolution" and not names.has(c.hero):
			errors.append("%s: Evolution for a hero who isn't in the deck" % c.name)
		if n > LIMITS[c.type]:
			errors.append("%s: %d copies, but %s allows at most %d" % [c.name, n, c.type, LIMITS[c.type]])
		count += n
	if count != DECK_SIZE:
		errors.append("%d cards, the deck needs %d" % [count, DECK_SIZE])
	return errors
