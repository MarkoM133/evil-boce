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
## given), then cards of their colours (evolutions only for those heroes), a colour at a time,
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
		var cap: int = pool_capacity(_pool(catalog, draw))
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
	var pool: Array[CardDef] = _pool(catalog, picked)
	var cards: Dictionary = {}
	var total: int = 0
	while total < DECK_SIZE:
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


## Deck cards these heroes may take: their colours, evolutions only for them.
static func _pool(catalog: CardCatalog, heroes: Array[CardDef]) -> Array[CardDef]:
	var colors := PackedStringArray()
	var names := PackedStringArray()
	for h: CardDef in heroes:
		colors.append(h.color)
		names.append(h.name)
	var pool: Array[CardDef] = []
	for t: String in DECK_TYPES:
		for c: CardDef in catalog.of_type(t):
			if colors.has(c.color) and (t != "Evolution" or names.has(c.hero)) and _for_heroes(catalog, c, names):
				pool.append(c)
	return pool


## Heroes a card is meant for: its traits that are a hero's full name or the first word of it
## (Giorno = Giorno Giovanna; case does not matter); empty for a card any hero of its colour may
## take. Such a card goes in a deck only with that hero.
static func card_heroes(catalog: CardCatalog, c: CardDef) -> PackedStringArray:
	var out := PackedStringArray()
	for h: CardDef in catalog.of_type("Hero"):
		if c.has_trait(h.name) or c.has_trait(h.name.get_slice(" ", 0)):
			out.append(h.name)
	return out


static func _for_heroes(catalog: CardCatalog, c: CardDef, names: PackedStringArray) -> bool:
	var only: PackedStringArray = card_heroes(catalog, c)
	if only.is_empty():
		return true
	for n: String in only:
		if names.has(n):
			return true
	return false


## Most cards a deck can hold from this pool (every card at its limit).
static func pool_capacity(pool: Array[CardDef]) -> int:
	var n: int = 0
	for c: CardDef in pool:
		n += LIMITS[c.type]
	return n


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
		if not _for_heroes(catalog, c, names):
			errors.append("%s: only for %s, who isn't in the deck" % [c.name, " or ".join(card_heroes(catalog, c))])
		if n > LIMITS[c.type]:
			errors.append("%s: %d copies, but %s allows at most %d" % [c.name, n, c.type, LIMITS[c.type]])
		count += n
	if count != DECK_SIZE:
		errors.append("%d cards, the deck needs %d" % [count, DECK_SIZE])
	return errors
