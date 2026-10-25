class_name HexMap
extends RefCounted
## A rectangular N x N map of pointy-top hexes in odd-r offset layout, centred on the
## world origin. Row 0 is the far edge (-z), row N-1 the near edge (+z).

var size: int
var hex_size: float
## Axial-space world position of the map centre; world = axial world - origin.
var origin: Vector2


func _init(n: int, hex_size_: float = 1.0) -> void:
	size = n
	hex_size = hex_size_
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for a: Vector2i in cells():
		var p: Vector2 = Hex.to_world(a, hex_size)
		lo = lo.min(p)
		hi = hi.max(p)
	origin = (lo + hi) * 0.5


func contains(a: Vector2i) -> bool:
	var o: Vector2i = Hex.axial_to_offset(a)
	return o.x >= 0 and o.y >= 0 and o.x < size and o.y < size


func cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row: int in size:
		for col: int in size:
			out.append(Hex.offset_to_axial(col, row))
	return out


@warning_ignore("integer_division")
func center_cell() -> Vector2i:
	return Hex.offset_to_axial((size - 1) / 2, (size - 1) / 2)


func to_world(a: Vector2i) -> Vector2:
	return Hex.to_world(a, hex_size) - origin


func from_world(p: Vector2) -> Vector2i:
	return Hex.from_world(p + origin, hex_size)


## Distance between neighbouring hex centres.
func spacing() -> float:
	return hex_size * Hex.SQRT3


## Hexes a ball covers: 1 for WT 1-3, 7 (centre and ring) for WT 4+.
func footprint(center: Vector2i, big: bool) -> Array[Vector2i]:
	return Hex.spiral(center, 1 if big else 0)


## Map hexes within `rng` steps of the ball's outer hexes, footprint excluded.
func range_cells(center: Vector2i, big: bool, rng: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if rng <= 0:
		return out
	var inner: int = 1 if big else 0
	for a: Vector2i in Hex.spiral(center, rng + inner):
		if Hex.distance(a, center) > inner and contains(a):
			out.append(a)
	return out
