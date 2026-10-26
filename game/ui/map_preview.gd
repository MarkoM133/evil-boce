class_name MapPreview
extends Control
## A small drawing of an N x N map, for the map picker: every hex, the two start edges in the
## team colours (red at the top, blue at the bottom, as the table camera sees it) and the
## middle third, where the stages go, in straw.

var map_size: int = 23:
	set(v):
		map_size = v
		queue_redraw()
## Hexes drawn a little smaller than their cell, so the grid shows.
var gap: float = 0.12

const BASE := Color("2a2622")
const MIDDLE := Color("5c4a1e")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var m := HexMap.new(map_size, 1.0)
	var cells: Array[Vector2i] = m.cells()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for a: Vector2i in cells:
		var p: Vector2 = m.to_world(a)
		lo = lo.min(p)
		hi = hi.max(p)
	# Centres span lo..hi; a pointy-top hex reaches sqrt(3)/2 sideways and 1 up and down.
	lo -= Vector2(Hex.SQRT3 * 0.5, 1.0)
	hi += Vector2(Hex.SQRT3 * 0.5, 1.0)
	var span: Vector2 = hi - lo
	var k: float = minf(size.x / span.x, size.y / span.y)
	var off: Vector2 = (size - span * k) * 0.5 - lo * k
	var r: float = k * (1.0 - gap)
	var corners := PackedVector2Array()
	for i: int in 6:
		corners.append(Hex.corner(i, r))
	@warning_ignore("integer_division")
	var third: int = map_size / 3
	for a: Vector2i in cells:
		var row: int = Hex.axial_to_offset(a).y
		var col: Color = BASE
		if row == 0:
			col = Palette.team(1).darkened(0.25)
		elif row == map_size - 1:
			col = Palette.team(0).darkened(0.25)
		elif row >= third and row < map_size - third:
			col = MIDDLE
		var c: Vector2 = m.to_world(a) * k + off
		var poly := PackedVector2Array()
		for p: Vector2 in corners:
			poly.append(c + p)
		draw_colored_polygon(poly, col)
