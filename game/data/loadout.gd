class_name Loadout
extends RefCounted
## What a player brings besides the deck (GDD 7): 3 stages and 6 cores (2 Buff, 2 Major,
## 2 Debuff). Chosen before every match, not saved with the deck; "" in a slot means Random.
## The last choice is remembered in the settings for convenience.

const STAGES: int = 3
const CORE_KINDS: Array[String] = ["Buff", "Major", "Debuff"]
const CORES_PER_KIND: int = 2
const RANDOM: String = ""

## Stage ids per slot ("" = random), length STAGES.
var stages: PackedStringArray = PackedStringArray(["", "", ""])
## Core ids per slot, kind by kind (Buff, Buff, Major, Major, Debuff, Debuff); "" = random.
var cores: PackedStringArray = PackedStringArray(["", "", "", "", "", ""])


static func random() -> Loadout:
	return Loadout.new()


## The kind a core slot takes.
static func core_kind(slot: int) -> String:
	@warning_ignore("integer_division")
	return CORE_KINDS[clampi(slot / CORES_PER_KIND, 0, CORE_KINDS.size() - 1)]


## What is wrong with the picks (the same stage or core twice), for the UI.
func problems(catalog: CardCatalog) -> PackedStringArray:
	var out := PackedStringArray()
	if _has_twice(stages):
		out.append("the same stage twice")
	if _has_twice(cores):
		out.append("the same core twice")
	for i: int in cores.size():
		if cores[i].is_empty():
			continue
		var c: CardDef = catalog.get_card(cores[i])
		if c == null or c.type != "Core":
			out.append("%s is not a core" % cores[i])
		elif c.kind != core_kind(i):
			out.append("%s is a %s core, not %s" % [c.name, c.kind, core_kind(i)])
	return out


## Fills the random slots and returns {"stages": [3 ids], "cores": [6 ids]}. Random picks never
## repeat a chosen one; when a kind has too few cores the rest of that kind is left out.
func resolve(catalog: CardCatalog, rng: RandomNumberGenerator) -> Dictionary:
	var all_stages: Array[String] = []
	for c: CardDef in catalog.of_type("Stage"):
		all_stages.append(c.id)
	var out_stages := PackedStringArray()
	for id: String in stages:
		if not id.is_empty() and all_stages.has(id) and not out_stages.has(id):
			out_stages.append(id)
	var pool: Array[String] = _without(all_stages, out_stages)
	while out_stages.size() < STAGES and not pool.is_empty():
		out_stages.append(_take(pool, rng))
	var out_cores := PackedStringArray()
	for k: int in CORE_KINDS.size():
		var kind: String = CORE_KINDS[k]
		var of_kind: Array[String] = []
		for c: CardDef in catalog.of_type("Core"):
			if c.kind == kind:
				of_kind.append(c.id)
		var mine := PackedStringArray()
		for j: int in CORES_PER_KIND:
			var id: String = cores[k * CORES_PER_KIND + j]
			if not id.is_empty() and of_kind.has(id) and not mine.has(id):
				mine.append(id)
		var left: Array[String] = _without(of_kind, mine)
		while mine.size() < CORES_PER_KIND and not left.is_empty():
			mine.append(_take(left, rng))
		out_cores.append_array(mine)
	return {"stages": out_stages, "cores": out_cores}


func to_dict() -> Dictionary:
	return {"stages": Array(stages), "cores": Array(cores)}


static func from_dict(d: Dictionary) -> Loadout:
	var l := Loadout.new()
	var s: PackedStringArray = JsonUtil.as_strings(d.get("stages", []))
	var c: PackedStringArray = JsonUtil.as_strings(d.get("cores", []))
	for i: int in mini(s.size(), STAGES):
		l.stages[i] = s[i]
	for i: int in mini(c.size(), l.cores.size()):
		l.cores[i] = c[i]
	return l


## The last loadout this player picked on this computer (`who` = "p1", "p2" or "online").
static func remembered(who: String) -> Loadout:
	return from_dict(GameSettings.loadout(who))


func remember(who: String) -> void:
	GameSettings.set_loadout(who, to_dict())


static func _without(ids: Array[String], taken: PackedStringArray) -> Array[String]:
	var out: Array[String] = []
	for id: String in ids:
		if not taken.has(id):
			out.append(id)
	return out


static func _take(pool: Array[String], rng: RandomNumberGenerator) -> String:
	var i: int = rng.randi_range(0, pool.size() - 1)
	var id: String = pool[i]
	pool.remove_at(i)
	return id


static func _has_twice(ids: PackedStringArray) -> bool:
	var seen: Dictionary[String, bool] = {}
	for id: String in ids:
		if id.is_empty():
			continue
		if seen.has(id):
			return true
		seen[id] = true
	return false
