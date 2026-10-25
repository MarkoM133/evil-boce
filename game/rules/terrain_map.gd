class_name TerrainMap
extends RefCounted
## Which hexes carry which terrain. Owned by whoever runs the game (the sandbox, or the rules
## engine from the revealed stages); the arena only draws it and the sim reads friction, the
## hill and the wind from it. Every patch remembers its centre (the top of a hill) and its
## direction (where a wind blows, a Hex.DIRECTIONS index).

var cells: Dictionary[Vector2i, Terrain.Type] = {}
var centers: Dictionary[Vector2i, Vector2i] = {}
var dirs: Dictionary[Vector2i, int] = {}


func at(a: Vector2i) -> Terrain.Type:
	return cells.get(a, Terrain.Type.NONE)


## Centre hex of the patch `a` belongs to (`a` itself when it has no terrain).
func center_of(a: Vector2i) -> Vector2i:
	return centers.get(a, a)


func dir_of(a: Vector2i) -> int:
	return dirs.get(a, 0)


func is_empty() -> bool:
	return cells.is_empty()


func has(t: Terrain.Type) -> bool:
	return cells.values().has(t)


func clear() -> void:
	cells.clear()
	centers.clear()
	dirs.clear()


## Sets the 7-hex patch around `center` (a stage's footprint). NONE clears it. Hexes outside
## `map` are skipped. `dir` is the wind direction (ignored by the other types).
func set_patch(center: Vector2i, t: Terrain.Type, map: HexMap, dir: int = 0) -> void:
	for a: Vector2i in Hex.spiral(center, 1):
		if not map.contains(a):
			continue
		if t == Terrain.Type.NONE:
			cells.erase(a)
			centers.erase(a)
			dirs.erase(a)
		else:
			cells[a] = t
			centers[a] = center
			dirs[a] = posmod(dir, 6)


## {"q,r": "Ice", ...}; a ramp also names its centre ("Ramp@q,r") and a wind its direction
## ("Wind>d").
func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for a: Vector2i in cells:
		var v: String = Terrain.name_of(cells[a])
		match cells[a]:
			Terrain.Type.RAMP:
				var c: Vector2i = center_of(a)
				v += "@%d,%d" % [c.x, c.y]
			Terrain.Type.WIND:
				v += ">%d" % dir_of(a)
		out["%d,%d" % [a.x, a.y]] = v
	return out


static func from_dict(d: Dictionary) -> TerrainMap:
	var tm := TerrainMap.new()
	for key: Variant in d:
		var a: Variant = _cell(str(key))
		if a == null:
			continue
		var cell: Vector2i = a
		var v: String = str(d[key])
		var dir: int = 0
		var center: Vector2i = cell
		if v.contains(">"):
			dir = v.get_slice(">", 1).to_int()
			v = v.get_slice(">", 0)
		if v.contains("@"):
			var c: Variant = _cell(v.get_slice("@", 1))
			if c != null:
				center = c
			v = v.get_slice("@", 0)
		var t: Terrain.Type = Terrain.parse(v)
		if t != Terrain.Type.NONE:
			tm.cells[cell] = t
			tm.centers[cell] = center
			tm.dirs[cell] = posmod(dir, 6)
	return tm


static func _cell(s: String) -> Variant:
	var parts: PackedStringArray = s.split(",")
	if parts.size() != 2:
		return null
	return Vector2i(parts[0].to_int(), parts[1].to_int())
