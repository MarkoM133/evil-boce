class_name CardCatalog
extends RefCounted
## Card definitions by id, built from a parsed cards.json document. Placeholder cores are
## added when the document has none (see docs/private handoff, step 2).

var version: int = 0
var cards: Dictionary[String, CardDef] = {}
## The described tags (data/traits.json, or "traits" in the doc), as written there. The first tag rule does
## not read them since 2026-11-16 (any tag a hero carries counts); a match record still stores the list.
var trait_names: PackedStringArray = PackedStringArray()
## Cards per Draft pack by set code (data/sets/sets.json, edited in the web app's Card editor
## › Sets); "default" is the pack of a Draft that mixes sets.
var pack_sizes: Dictionary[String, int] = {}
## The sets' names by code, in the order of the set list ("OP1" → "One Piece").
var set_names: Dictionary[String, String] = {}
## The series a set belongs to, by code, for the sets that name one ("DQ1" → "Dragon Quest"): see series_of.
var set_series: Dictionary[String, String] = {}


static func from_doc(doc: Dictionary, with_placeholders: bool = true) -> CardCatalog:
	var cat := CardCatalog.new()
	cat.version = JsonUtil.as_int(doc.get("version", 0))
	for c: Variant in JsonUtil.as_array(doc.get("cards", [])):
		if not c is Dictionary:
			continue
		var cd: Dictionary = c
		if JsonUtil.as_bool(cd.get("deleted", false)):
			continue
		var def: CardDef = CardDef.from_card(cd)
		cat.cards[def.id] = def
	cat.set_traits(JsonUtil.as_array(doc.get("traits", [])))
	if with_placeholders and cat.of_type("Core").is_empty():
		cat.add_placeholder_cores()
	cat.resolve_tokens()
	return cat


## The described tags: [{name, description}] (data/traits.json) or plain names.
func set_traits(list: Array) -> void:
	trait_names = PackedStringArray()
	for t: Variant in list:
		var n: String = str(JsonUtil.as_dict(t).get("name", "")) if t is Dictionary else str(t)
		if not n.strip_edges().is_empty():
			trait_names.append(n.strip_edges())


## The set list: {"sets": [{code, name, number, packSize, series?}], "default": {packSize}} (data/sets/sets.json).
func set_sets(doc: Dictionary) -> void:
	pack_sizes = {}
	set_names = {}
	set_series = {}
	for s: Variant in JsonUtil.as_array(doc.get("sets", [])):
		var sd: Dictionary = JsonUtil.as_dict(s)
		var code: String = str(sd.get("code", "")).strip_edges()
		if not code.is_empty():
			set_names[code] = str(sd.get("name", code)).strip_edges()
			var series: String = str(sd.get("series", "")).strip_edges()
			if not series.is_empty():
				set_series[code] = series
		var size: int = JsonUtil.as_int(sd.get("packSize", 0))
		if not code.is_empty() and size > 0:
			pack_sizes[code] = size
	var def_size: int = JsonUtil.as_int(JsonUtil.as_dict(doc.get("default", {})).get("packSize", 0))
	if def_size > 0:
		pack_sizes["default"] = def_size


## The series a card belongs to: its set's series ("Dragon Quest" for DQ1 and DQ2), else its set's own name, else
## the set code. What the hero picker groups by (Marko 2026-11-27: sets are named after what they are about, so two
## sets of one series no longer share a name).
func series_of(card_id: String) -> String:
	var code: String = set_of(card_id)
	if set_series.has(code):
		return set_series[code]
	return set_names[code] if set_names.has(code) and not set_names[code].is_empty() else code


## Every series, once, in the order of the set list (a series stands where its first set does).
func series_order() -> PackedStringArray:
	var out := PackedStringArray()
	for code: String in set_names:
		var series: String = series_of(code)
		if not out.has(series):
			out.append(series)
	return out


## The set code of a card id ("OP1-012" → "OP1").
static func set_of(card_id: String) -> String:
	return card_id.get_slice("-", 0)


static func from_json_text(text: String, with_placeholders: bool = true) -> CardCatalog:
	var parsed: Variant = JSON.parse_string(text)
	return from_doc(JsonUtil.as_dict(parsed), with_placeholders)


func has(id: String) -> bool:
	return cards.has(id)


func get_card(id: String) -> CardDef:
	return cards.get(id)


func of_type(type: String) -> Array[CardDef]:
	var out: Array[CardDef] = []
	for d: CardDef in cards.values():
		if d.type == type:
			out.append(d)
	out.sort_custom(func(a: CardDef, b: CardDef) -> bool: return a.id < b.id)
	return out


## Token names in parsed card texts become token card ids, now that every card is here (CardDef.resolve_tokens).
func resolve_tokens() -> void:
	for d: CardDef in cards.values():
		d.resolve_tokens(self)


## The id of the token card with this name, "" when there is none. Two cards may share a name (GDD 10): the
## maker's own token (its id with a number) wins; otherwise several is none.
func token_named(name: String, maker_id: String = "") -> String:
	var found := PackedStringArray()
	for d: CardDef in cards.values():
		if d.token and d.name.to_lower() == name.to_lower():
			if not maker_id.is_empty() and d.id.begins_with(maker_id + "-"):
				return d.id
			found.append(d.id)
	return found[0] if found.size() == 1 else ""


## Hero card with this name (Evolution cards name their hero).
func hero_named(name: String) -> CardDef:
	for d: CardDef in cards.values():
		if d.type == "Hero" and d.name == name:
			return d
	return null


## Placeholder fx for cards that have no hand-written `fx` yet: {"JO1-004": "END ...: ..."}.
func apply_fx_overrides(d: Dictionary) -> void:
	for k: Variant in d:
		var card: CardDef = get_card(str(k))
		if card != null and not card.fx_hand_written:
			card.build_effects(str(d[k]))
	resolve_tokens()


## Six generic cores (2 Buff, 2 Major, 2 Debuff) until the real ones exist in cards.json.
func add_placeholder_cores() -> void:
	var kinds: Array[String] = ["Buff", "Buff", "Major", "Major", "Debuff", "Debuff"]
	for i: int in kinds.size():
		var c := CardDef.new()
		c.id = "CR0-%03d" % (i + 1)
		c.name = "%s core %d" % [kinds[i], i % 2 + 1]
		c.type = "Core"
		c.kind = kinds[i]
		cards[c.id] = c
