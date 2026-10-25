class_name CardDef
extends RefCounted
## The parts of a card the rules engine needs. Built from a cards.json record (or a
## placeholder); text effects are parsed elsewhere.

var id: String = ""
var name: String = ""
## "Hero", "Action", "Equipment", "Assist", "Evolution", "Stage", "Core".
var type: String = ""
var color: String = ""
var cost: int = 0
var wt: int = 2
## Hero and Evolution stats.
var hp: int = 0
var dmg: int = 0
var pwr: int = 0
var rng: int = 0
var kb: int = 0
## Evolution level (1, 2, 3) and the hero it evolves (card name).
var evo: int = 0
var hero: String = ""
## Core kind: "Buff", "Major" or "Debuff".
var kind: String = ""
## Flat stat bonus from the web app's `bonus` field ({"pwr": 2000, "kb": 1} ...). Equipment
## keeps it while equipped; an Action gives it until the end of the phase.
var bonus: Dictionary[String, int] = {}
## Stage terrain, from the `Terrain: X` line in the text.
var terrain: Terrain.Type = Terrain.Type.NONE
var text: String = ""
var traits: PackedStringArray = PackedStringArray()
## Effects in the fx language: the web app's `fx` field when set, else what FxTextParser read
## from the text. `fx_hand_written` says which. Sentences nobody understood are in `unparsed`.
var fx: String = ""
var fx_hand_written: bool = false
var effects: Array[FxEffect] = []
var unparsed: PackedStringArray = PackedStringArray()


## A card the game can play: every sentence is understood (or an fx was written by hand).
func is_ready() -> bool:
	return unparsed.is_empty()


## Effects that fire or can be used in `when` (an fx WHEN word, e.g. "POSTROLL").
func effects_when(when: String) -> Array[FxEffect]:
	var out: Array[FxEffect] = []
	for e: FxEffect in effects:
		if e.when == when:
			out.append(e)
	return out


func has_trait(t: String) -> bool:
	for x: String in traits:
		if x.to_lower() == t.to_lower():
			return true
	return false


## Fills fx, effects and unparsed from the record's `fx` field or from the text.
func build_effects(fx_field: String) -> void:
	unparsed = PackedStringArray()
	if not fx_field.strip_edges().is_empty():
		fx = fx_field.strip_edges()
		fx_hand_written = true
		var bad := PackedStringArray()
		effects = FxEffect.parse_all(fx, bad)
		for b: String in bad:
			unparsed.append("fx: " + b)
		return
	var parsed: Dictionary = FxTextParser.parse(self)
	fx = str(parsed.get("fx", ""))
	fx_hand_written = false
	effects = FxEffect.parse_all(fx)
	unparsed = JsonUtil.as_strings(parsed.get("unparsed", []))


static func from_card(c: Dictionary) -> CardDef:
	var d := CardDef.new()
	d.id = str(c.get("id", ""))
	d.name = str(c.get("name", d.id))
	d.type = str(c.get("type", ""))
	d.color = str(c.get("color", "")) if c.get("color") != null else ""
	d.cost = JsonUtil.as_int(c.get("cost", 0))
	d.wt = maxi(1, JsonUtil.as_int(c.get("wt", 2), 2))
	var stats: Dictionary = JsonUtil.as_dict(c.get("stats", {}))
	d.hp = JsonUtil.as_int(stats.get("hp", 0))
	d.dmg = JsonUtil.as_int(stats.get("dmg", 0))
	d.pwr = JsonUtil.as_int(stats.get("pwr", 0))
	d.rng = JsonUtil.as_int(stats.get("rng", 0))
	d.kb = JsonUtil.as_int(stats.get("kb", 0))
	d.evo = JsonUtil.as_int(c.get("evo", 0))
	d.hero = str(c.get("hero", "")) if c.get("hero") != null else ""
	d.kind = str(c.get("kind", "")) if c.get("kind") != null else ""
	d.text = str(c.get("text", "")) if c.get("text") != null else ""
	d.traits = JsonUtil.as_strings(c.get("traits", []))
	var bonus: Dictionary = JsonUtil.as_dict(c.get("bonus", {}))
	for k: Variant in bonus:
		var v: int = JsonUtil.as_int(bonus[k])
		if v != 0:
			d.bonus[str(k)] = v
	d.terrain = parse_terrain(d.text)
	if d.terrain == Terrain.Type.NONE and c.has("terrain"):
		d.terrain = Terrain.parse(str(c.get("terrain", "")))
	d.build_effects(str(c.get("fx", "")) if c.get("fx") != null else "")
	return d


## The card as a cards.json record (what from_card reads), for replays that carry their cards.
func to_record() -> Dictionary:
	var rec: Dictionary = {"id": id, "name": name, "type": type, "cost": cost, "wt": wt, "text": text,
		"traits": Array(traits)}
	if not color.is_empty():
		rec["color"] = color
	if type == "Hero" or type == "Evolution":
		rec["stats"] = {"hp": hp, "dmg": dmg, "pwr": pwr, "rng": rng, "kb": kb}
	if evo > 0:
		rec["evo"] = evo
	if not hero.is_empty():
		rec["hero"] = hero
	if not kind.is_empty():
		rec["kind"] = kind
	if not bonus.is_empty():
		rec["bonus"] = bonus.duplicate()
	if terrain != Terrain.Type.NONE and parse_terrain(text) == Terrain.Type.NONE:
		rec["terrain"] = Terrain.name_of(terrain)
	if fx_hand_written:
		rec["fx"] = fx
	return rec


## Finds a `Terrain: X` line in card text.
static func parse_terrain(text: String) -> Terrain.Type:
	for line: String in text.split("\n"):
		var s: String = line.strip_edges()
		if s.to_lower().begins_with("terrain:"):
			return Terrain.parse(s.substr(8))
	return Terrain.Type.NONE


func is_hero() -> bool:
	return type == "Hero"
