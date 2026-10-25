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
## Stage terrain, from the `Terrain: X` line in the text.
var terrain: Terrain.Type = Terrain.Type.NONE
var text: String = ""
var traits: PackedStringArray = PackedStringArray()


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
	d.terrain = parse_terrain(d.text)
	if d.terrain == Terrain.Type.NONE and c.has("terrain"):
		d.terrain = Terrain.parse(str(c.get("terrain", "")))
	return d


## Finds a `Terrain: X` line in card text.
static func parse_terrain(text: String) -> Terrain.Type:
	for line: String in text.split("\n"):
		var s: String = line.strip_edges()
		if s.to_lower().begins_with("terrain:"):
			return Terrain.parse(s.substr(8))
	return Terrain.Type.NONE


func is_hero() -> bool:
	return type == "Hero"
