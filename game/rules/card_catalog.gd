class_name CardCatalog
extends RefCounted
## Card definitions by id, built from a parsed cards.json document. Placeholder cores are
## added when the document has none (see docs/private handoff, step 2).

var version: int = 0
var cards: Dictionary[String, CardDef] = {}


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
	if with_placeholders and cat.of_type("Core").is_empty():
		cat.add_placeholder_cores()
	return cat


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


## Hero card with this name (Evolution cards name their hero).
func hero_named(name: String) -> CardDef:
	for d: CardDef in cards.values():
		if d.type == "Hero" and d.name == name:
			return d
	return null


## Placeholder terrain for stage cards that have no `Terrain:` line yet: {"Stage-001": "Ice"}.
func apply_terrain_overrides(d: Dictionary) -> void:
	for k: Variant in d:
		var card: CardDef = get_card(str(k))
		if card != null and card.type == "Stage" and card.terrain == Terrain.Type.NONE:
			card.terrain = Terrain.parse(str(d[k]))


## Placeholder fx for cards that have no hand-written `fx` yet: {"JO1-004": "END ...: ..."}.
func apply_fx_overrides(d: Dictionary) -> void:
	for k: Variant in d:
		var card: CardDef = get_card(str(k))
		if card != null and not card.fx_hand_written:
			card.build_effects(str(d[k]))


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
