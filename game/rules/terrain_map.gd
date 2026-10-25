class_name TerrainMap
extends RefCounted
## Which hexes carry which terrain. Owned by whoever runs the game (the sandbox now, the rules
## engine in step 2); the arena only draws it and the sim only reads friction from it.

var cells: Dictionary[Vector2i, Terrain.Type] = {}


func at(a: Vector2i) -> Terrain.Type:
	return cells.get(a, Terrain.Type.NONE)


func is_empty() -> bool:
	return cells.is_empty()


func clear() -> void:
	cells.clear()


## Sets the 7-hex patch around `center` (a stage's footprint). NONE clears it. Hexes outside
## `map` are skipped.
func set_patch(center: Vector2i, t: Terrain.Type, map: HexMap) -> void:
	for a: Vector2i in Hex.spiral(center, 1):
		if not map.contains(a):
			continue
		if t == Terrain.Type.NONE:
			cells.erase(a)
		else:
			cells[a] = t


## {"q,r": "Ice", ...}
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for a: Vector2i in cells:
		out["%d,%d" % [a.x, a.y]] = Terrain.name_of(cells[a])
	return out


static func from_dict(d: Dictionary) -> TerrainMap:
	var tm := TerrainMap.new()
	for key: Variant in d:
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() != 2:
			continue
		var t: Terrain.Type = Terrain.parse(str(d[key]))
		if t != Terrain.Type.NONE:
			tm.cells[Vector2i(parts[0].to_int(), parts[1].to_int())] = t
	return tm
