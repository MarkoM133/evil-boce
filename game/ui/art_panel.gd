class_name ArtPanel
extends Control
## A large piece of card art with its left edge cut on a slant (the main menu's featured hero):
## `region` of the texture fills the panel, a red line runs along the cut. Fades by modulate.

var art: Texture2D
## Part of the texture shown, in 0..1 texture coordinates.
var region: Rect2 = Rect2(0, 0, 1, 1)
## How far the cut leans in over the panel's height, px.
var lean: float = 160.0
var fallback: Color = Palette.SURFACE_2
var edge: Color = Palette.ACCENT


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var pts := PackedVector2Array([Vector2(lean, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
	if art != null:
		var uvs := PackedVector2Array()
		for p: Vector2 in pts:
			uvs.append(Vector2(region.position.x + region.size.x * p.x / w, region.position.y + region.size.y * p.y / h))
		draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs, art)
	else:
		draw_colored_polygon(pts, fallback)
	# Darken towards the bottom so the name on it reads.
	var clear := Color(0, 0, 0, 0)
	var dark := Color(0, 0, 0, 0.75)
	draw_polygon(PackedVector2Array([Vector2(lean * 0.4, h * 0.6), Vector2(w, h * 0.6), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([clear, clear, dark, dark]))
	draw_colored_polygon(PackedVector2Array([Vector2(lean - 4, 0), Vector2(lean + 4, 0), Vector2(4, h), Vector2(-4, h)]), edge)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
