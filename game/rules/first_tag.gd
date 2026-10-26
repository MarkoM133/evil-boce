class_name FirstTag
extends RefCounted
## The first tag rule (GDD 10, 2026-10-26): a card's first tag says who may
## take it. "General": any hero of the card's colour. A hero alias ("Giorno", "Giorno &
## Bucciarati"): only those heroes. A trait from the trait list (data/traits.json): a hero of the
## card's colour that has the trait, on its own card or on an Evolution card in the deck.
## Anything else is not valid. Case and edge spaces do not count. The web app has the same rule
## (js/tags.js); both run the cases in tests/fixtures/first_tag_cases.json.

const GENERAL: String = "general"
const HEROES: String = "heroes"
const TRAIT: String = "trait"
const INVALID: String = "invalid"
const HERO_JOIN: String = "&"


static func norm(s: String) -> String:
	return s.strip_edges().to_lower()


## The names a first tag may use for this hero: the card's name and its aliases.
static func aliases_of(hero: CardDef) -> PackedStringArray:
	var out := PackedStringArray([norm(hero.name)])
	for a: String in hero.aliases:
		if not norm(a).is_empty() and not out.has(norm(a)):
			out.append(norm(a))
	return out


## What the first tag means: {kind, tag, heroes: [names], trait}.
static func kind_of(catalog: CardCatalog, card: CardDef) -> Dictionary:
	var tag: String = card.traits[0].strip_edges() if not card.traits.is_empty() else ""
	if tag.is_empty():
		return {"kind": INVALID, "tag": tag}
	if norm(tag) == GENERAL:
		return {"kind": GENERAL, "tag": tag}
	var heroes: Array[CardDef] = catalog.of_type("Hero")
	var named := PackedStringArray()
	var all_found: bool = true
	for part: String in tag.split(HERO_JOIN, false):
		var p: String = norm(part)
		if p.is_empty():
			continue
		var found: CardDef = null
		for h: CardDef in heroes:
			if aliases_of(h).has(p):
				found = h
				break
		if found == null:
			all_found = false
			break
		if not named.has(found.name):
			named.append(found.name)
	if all_found and not named.is_empty():
		return {"kind": HEROES, "tag": tag, "heroes": named}
	for t: String in catalog.trait_names:
		if norm(t) == norm(tag):
			return {"kind": TRAIT, "tag": tag, "trait": t}
	return {"kind": INVALID, "tag": tag}


## Whether a hero or Evolution card carries the trait (a tag equal to its name).
static func has_trait(card: CardDef, trait_name: String) -> bool:
	for t: String in card.traits:
		if norm(t) == norm(trait_name):
			return true
	return false


## May `card` go in a deck with these heroes and these Evolution cards in it?
## {ok, why, needs: [ids of Evolution cards that would let it in]}.
static func deck_verdict(catalog: CardCatalog, card: CardDef, heroes: Array[CardDef], evolutions: Array[CardDef] = []) -> Dictionary:
	var colors := PackedStringArray()
	var names := PackedStringArray()
	for h: CardDef in heroes:
		colors.append(h.color)
		names.append(h.name)
	if card.type == "Evolution":
		if names.has(card.hero):
			return _ok()
		return _no("Evolution for a hero who isn't in the deck")
	if not colors.has(card.color):
		return _no("color %s is not a color of the chosen heroes" % card.color)
	var k: Dictionary = kind_of(catalog, card)
	var same: Array[CardDef] = heroes.filter(func(h: CardDef) -> bool: return h.color == card.color)
	var same_names := PackedStringArray()
	for h: CardDef in same:
		same_names.append(h.name)
	match str(k["kind"]):
		GENERAL:
			return _ok()
		HEROES:
			var only: PackedStringArray = k["heroes"]
			for n: String in same_names:
				if only.has(n):
					return _ok()
			return _no("only for %s" % " or ".join(only))
		TRAIT:
			var t: String = k["trait"]
			for h: CardDef in same:
				if has_trait(h, t):
					return _ok()
			for e: CardDef in evolutions:
				if same_names.has(e.hero) and has_trait(e, t):
					return _ok()
			var needs := PackedStringArray()
			var needs_names := PackedStringArray()
			for e: CardDef in catalog.of_type("Evolution"):
				if same_names.has(e.hero) and has_trait(e, t):
					needs.append(e.id)
					needs_names.append(e.name)
			if not needs.is_empty():
				return {"ok": false, "why": "Requires %s" % " or ".join(needs_names), "needs": needs}
			return _no("needs a %s hero with %s" % [card.color, t])
	var tag: String = str(k.get("tag", ""))
	return _no(("first tag \"%s\" is not General, a hero or a known trait" % tag) if not tag.is_empty() else "the card has no tags")


static func _ok() -> Dictionary:
	return {"ok": true, "why": "", "needs": PackedStringArray()}


static func _no(why: String) -> Dictionary:
	return {"ok": false, "why": why, "needs": PackedStringArray()}


## The ids in `ids` that are Evolution cards, as cards.
static func evolutions_in(catalog: CardCatalog, ids: Array) -> Array[CardDef]:
	var out: Array[CardDef] = []
	for id: Variant in ids:
		var c: CardDef = catalog.get_card(str(id))
		if c != null and c.type == "Evolution":
			out.append(c)
	return out
