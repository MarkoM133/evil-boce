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


## A random deck like the app's randomFill: 3 different heroes (with `leader` among them when
## given), then cards they may take (the first tag rule, FirstTag), a colour at a time,
## up to 40 or until the pool runs out. The heroes are drawn again (a few tries) until their
## pool holds a full deck, so a random deck is short only when no draw allows 40.
## Returns {"name", "heroes": PackedStringArray, "cards": {id: n}}.
static func random_deck(catalog: CardCatalog, rng: RandomNumberGenerator, leader: String = "") -> Dictionary:
	var others: Array[CardDef] = catalog.of_type("Hero")
	var fixed: Array[CardDef] = []
	var lead: CardDef = catalog.get_card(leader) if not leader.is_empty() else null
	if lead != null and lead.is_hero():
		fixed.append(lead)
		others.erase(lead)
	var picked: Array[CardDef] = []
	var best: int = -1
	for _try: int in 40:
		var rest: Array[CardDef] = others.duplicate()
		var draw: Array[CardDef] = fixed.duplicate()
		while draw.size() < HERO_COUNT and not rest.is_empty():
			draw.append(rest.pop_at(rng.randi_range(0, rest.size() - 1)))
		var cap: int = pool_capacity(_pool(catalog, draw, hero_evolutions(catalog, draw)))
		if cap > best:
			best = cap
			picked = draw
		if cap >= DECK_SIZE:
			break
	var ids := PackedStringArray()
	var names := PackedStringArray()
	for h: CardDef in picked:
		ids.append(h.id)
		names.append(h.name)
	var cards: Dictionary = {}
	var total: int = 0
	while total < DECK_SIZE:
		# Cards an Evolution unlocks (a trait only it has) come in once that Evolution is in.
		var pool: Array[CardDef] = _pool(catalog, picked, FirstTag.evolutions_in(catalog, cards.keys()))
		# A colour first, then a card of it, so one big colour does not take the whole deck.
		var by_color: Dictionary[String, Array] = {}
		for c: CardDef in pool:
			if JsonUtil.as_int(cards.get(c.id, 0)) < LIMITS[c.type]:
				if not by_color.has(c.color):
					by_color[c.color] = []
				by_color[c.color].append(c)
		if by_color.is_empty():
			break
		var colors: Array = by_color.keys()
		var open: Array = by_color[str(colors[rng.randi_range(0, colors.size() - 1)])]
		var c: CardDef = open[rng.randi_range(0, open.size() - 1)]
		cards[c.id] = JsonUtil.as_int(cards.get(c.id, 0)) + 1
		total += 1
	return {"name": "Random (%s)" % ", ".join(names), "heroes": ids, "cards": cards}


## Deck cards these heroes may take with these Evolution cards in the deck: the first tag rule
## (FirstTag: colour, evolutions only for these heroes, General / hero / trait).
static func _pool(catalog: CardCatalog, heroes: Array[CardDef], evolutions: Array[CardDef] = []) -> Array[CardDef]:
	var pool: Array[CardDef] = []
	for t: String in DECK_TYPES:
		for c: CardDef in catalog.of_type(t):
			if JsonUtil.as_bool(FirstTag.deck_verdict(catalog, c, heroes, evolutions)["ok"]):
				pool.append(c)
	return pool


## Every Evolution card of these heroes, to see what a deck of them could unlock.
static func hero_evolutions(catalog: CardCatalog, heroes: Array[CardDef]) -> Array[CardDef]:
	var names := PackedStringArray()
	for h: CardDef in heroes:
		names.append(h.name)
	return catalog.of_type("Evolution").filter(func(e: CardDef) -> bool: return names.has(e.hero))



## Most cards a deck can hold from this pool (every card at its limit).
static func pool_capacity(pool: Array[CardDef]) -> int:
	var n: int = 0
	for c: CardDef in pool:
		n += LIMITS[c.type]
	return n


## Errors that make the deck unplayable (same rules as the app, minus the pool-size warning).
static func check(catalog: CardCatalog, heroes: PackedStringArray, cards: Dictionary, size: int = DECK_SIZE) -> PackedStringArray:
	var errors := PackedStringArray()
	if heroes.size() != HERO_COUNT:
		errors.append("pick %d heroes (now %d)" % [HERO_COUNT, heroes.size()])
	var seen: PackedStringArray = PackedStringArray()
	var colors: PackedStringArray = PackedStringArray()
	var names: PackedStringArray = PackedStringArray()
	var hero_defs: Array[CardDef] = []
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
			hero_defs.append(h)
	var evolutions: Array[CardDef] = FirstTag.evolutions_in(catalog, cards.keys().filter(func(k: Variant) -> bool: return JsonUtil.as_int(cards[k]) > 0))
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
		# Colour, Evolution and the first tag (FirstTag), the same rule as the web app.
		var v: Dictionary = FirstTag.deck_verdict(catalog, c, hero_defs, evolutions)
		if not JsonUtil.as_bool(v["ok"]):
			errors.append("%s: %s" % [c.name, str(v["why"])])
		if n > LIMITS[c.type]:
			errors.append("%s: %d copies, but %s allows at most %d" % [c.name, n, c.type, LIMITS[c.type]])
		count += n
	if count != size:
		errors.append("%d cards, the deck needs %d" % [count, size])
	return errors
