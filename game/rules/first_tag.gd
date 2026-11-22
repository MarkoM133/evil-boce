class_name FirstTag
extends RefCounted
## The first tag rule (GDD 10, 2026-10-26): a card's first tag says who may
## take it. "General": any hero of the card's colour. A hero alias ("Giorno", "Giorno &
## Bucciarati"): only those heroes; a name after "&" that is no hero yet is skipped ("Shanks &
## Roger" is Shanks's until Roger comes). A tag a Hero or an Evolution card carries (Marko, 2026-11-16:
## any such tag; the trait list is gone from the rule, data/traits.json only describes tags): a hero of the
## card's colour that has the tag, on its own card or on an Evolution card in the deck. The code still
## calls such a tag a trait (kind "trait", the `traits` field).
## "&" joins traits too, and heroes with traits (Marko, 2026-11-15): "Mage & Brave Hero" is a hero with
## either trait, "Dai & Mage" is Dai or any hero with Mage. Each part is a hero first, else a trait; a part
## that is neither is skipped while another part counts.
## A colorless card (color "None", 2026-11-01) is for a hero of any colour; its first tag still counts.
## Anything else is not valid. Case and edge spaces do not count. The web app has the same rule
## (js/tags.js); both run the cases in tests/fixtures/first_tag_cases.json.

const GENERAL: String = "general"
const HEROES: String = "heroes"
const TRAIT: String = "trait"
## Heroes and traits in one tag ("Dai & Mage").
const MIXED: String = "mixed"
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


## What the first tag means: {kind, tag, heroes: [names], traits: [names], unknown: [parts], trait}.
## kind: general | heroes (only heroes named) | trait (only traits, one or more; `trait` is the first) |
## mixed (both) | invalid. Whoever is named in `heroes` or carries one of `traits` satisfies it.
static func kind_of(catalog: CardCatalog, card: CardDef) -> Dictionary:
	var tag: String = card.traits[0].strip_edges() if not card.traits.is_empty() else ""
	if tag.is_empty():
		return {"kind": INVALID, "tag": tag}
	if norm(tag) == GENERAL:
		return {"kind": GENERAL, "tag": tag}
	var heroes: Array[CardDef] = catalog.of_type("Hero")
	var named := PackedStringArray()
	var traits := PackedStringArray()
	var unknown := PackedStringArray()
	var parts: int = 0
	for part: String in tag.split(HERO_JOIN, false):
		var p: String = norm(part)
		if p.is_empty():
			continue
		parts += 1
		var found: CardDef = null
		for h: CardDef in heroes:
			if aliases_of(h).has(p):
				found = h
				break
		if found != null:
			if not named.has(found.name):
				named.append(found.name)
			continue
		var t: String = _trait_named(catalog, p)
		if t.is_empty():
			unknown.append(p)
		elif not traits.has(t):
			traits.append(t)
	# "Shanks & Roger": a part that is no hero and no trait yet is skipped, so the card is Shanks's until
	# Roger comes. A tag without "&" must be a hero or a trait as it is.
	if (not named.is_empty() or not traits.is_empty()) and (unknown.is_empty() or parts > 1):
		var kind: String = HEROES if traits.is_empty() else (TRAIT if named.is_empty() else MIXED)
		var out: Dictionary = {"kind": kind, "tag": tag, "heroes": named, "traits": traits, "unknown": unknown}
		if kind == TRAIT:
			out["trait"] = traits[0]
		return out
	# A tag whose own name holds an "&".
	var whole: String = _trait_named(catalog, norm(tag))
	if not whole.is_empty():
		return {"kind": TRAIT, "tag": tag, "heroes": PackedStringArray(), "traits": PackedStringArray([whole]), "unknown": PackedStringArray(), "trait": whole}
	return {"kind": INVALID, "tag": tag}


## The tag a Hero or an Evolution card carries that `normed` names, as written on the first card that has
## it (in the order of the catalog); "" if nobody carries it. Same pick as carriedTag in js/tags.js.
static func _trait_named(catalog: CardCatalog, normed: String) -> String:
	if normed.is_empty():
		return ""
	for c: CardDef in catalog.cards.values():
		if c.type != "Hero" and c.type != "Evolution":
			continue
		for t: String in c.traits:
			if norm(t) == normed:
				return t.strip_edges()
	return ""


## Whether a card carries any of the traits.
static func has_any_trait(card: CardDef, traits: PackedStringArray) -> bool:
	for t: String in traits:
		if has_trait(card, t):
			return true
	return false


## Who the tag is for, for a refusal: "only for A or B", "needs a Red hero with X or Y", or both.
static func _who(card: CardDef, k: Dictionary) -> String:
	var only: PackedStringArray = k["heroes"]
	var traits: PackedStringArray = k["traits"]
	var with: String = ("a hero with %s" % " or ".join(traits)) if card.is_colorless() else ("a %s hero with %s" % [card.color, " or ".join(traits)])
	if traits.is_empty():
		return "only for %s" % " or ".join(only)
	if only.is_empty():
		return "needs %s" % with
	return "only for %s, or %s" % [" or ".join(only), with]


## Whether a hero or Evolution card carries the trait (a tag equal to its name).
static func has_trait(card: CardDef, trait_name: String) -> bool:
	for t: String in card.traits:
		if norm(t) == norm(trait_name):
			return true
	return false


## May `card` go in a deck with these heroes and these Evolution cards in it?
## {ok, why, needs: [ids of Evolution cards that would let it in]}.
static func deck_verdict(catalog: CardCatalog, card: CardDef, heroes: Array[CardDef], evolutions: Array[CardDef] = []) -> Dictionary:
	# A token is made by another card in play (GDD 10, 2026-11-14): no deck, pack or sideboard takes it.
	if card.token:
		return _no("a token is never in a deck")
	var colors := PackedStringArray()
	var names := PackedStringArray()
	for h: CardDef in heroes:
		colors.append(h.color)
		names.append(h.name)
	if card.type == "Evolution":
		if names.has(card.hero):
			return _ok()
		return _no("Evolution for a hero who isn't in the deck")
	if not card.is_colorless() and not colors.has(card.color):
		return _no("color %s is not a color of the chosen heroes" % card.color)
	var k: Dictionary = kind_of(catalog, card)
	var same: Array[CardDef] = heroes.filter(func(h: CardDef) -> bool: return card.plays_for_color(h.color))
	var same_names := PackedStringArray()
	for h: CardDef in same:
		same_names.append(h.name)
	match str(k["kind"]):
		GENERAL:
			return _ok()
		HEROES, TRAIT, MIXED:
			# A hero named in the tag, or one that carries one of its traits (on its card or on an Evolution in the deck).
			var only: PackedStringArray = k["heroes"]
			var traits: PackedStringArray = k["traits"]
			for n: String in same_names:
				if only.has(n):
					return _ok()
			for h: CardDef in same:
				if has_any_trait(h, traits):
					return _ok()
			for e: CardDef in evolutions:
				if same_names.has(e.hero) and has_any_trait(e, traits):
					return _ok()
			var needs := PackedStringArray()
			var needs_names := PackedStringArray()
			for e: CardDef in catalog.of_type("Evolution"):
				if same_names.has(e.hero) and has_any_trait(e, traits):
					needs.append(e.id)
					needs_names.append(e.name)
			if not needs.is_empty():
				return {"ok": false, "why": "Requires %s" % " or ".join(needs_names), "needs": needs}
			return _no(_who(card, k))
	var tag: String = str(k.get("tag", ""))
	return _no(("first tag \"%s\" is not General, a hero or a tag a hero carries" % tag) if not tag.is_empty() else "the card has no tags")


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


## May `card` be played for the hero whose base card is `base` and whose current card (the
## last evolution, else the base) is `current`? The hero's name follows it through evolutions;
## a trait is read off the current card only (GDD 10), plus the tags the hero `gained` in the match. {ok, why}.
static func play_verdict(catalog: CardCatalog, card: CardDef, base: CardDef, current: CardDef, gained: PackedStringArray = PackedStringArray()) -> Dictionary:
	if card.type == "Evolution":
		return _ok()
	var k: Dictionary = kind_of(catalog, card)
	match str(k["kind"]):
		GENERAL:
			return _ok()
		HEROES, TRAIT, MIXED:
			var only: PackedStringArray = k["heroes"]
			var traits: PackedStringArray = k["traits"]
			if base != null and only.has(base.name):
				return _ok()
			if current != null and has_any_trait(current, traits):
				return _ok()
			# A tag the hero got in the match counts as one it carries (Marko 2026-11-22).
			for g: String in gained:
				for t: String in traits:
					if norm(g) == norm(t):
						return _ok()
			if traits.is_empty():
				return _no("only for %s" % " or ".join(only))
			if only.is_empty():
				return _no("Requires %s" % " or ".join(traits))
			return _no("only for %s, or Requires %s" % [" or ".join(only), " or ".join(traits)])
	var tag: String = str(k.get("tag", ""))
	return _no(("first tag \"%s\" is not General, a hero or a tag a hero carries" % tag) if not tag.is_empty() else "the card has no tags")
