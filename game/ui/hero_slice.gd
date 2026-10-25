class_name HeroSlice
extends Control
## A hero in the match HUD's roster (GDD 11), like the web app's deck slices: a slanted strip with
## a crop of the card art at one end (the right end when `mirrored`), and room for the name, HP
## and cores on the rest. States are drawn here: outline (active / pickable), a red stripe
## (in a battle), grey art (KO).

const ART_W: float = 84.0
const CUT: float = 16.0

## Width of the art end; set it to the full width for a tile that is all picture.
var art_w: float = ART_W

var art: Texture2D
## Part of the texture to show, in 0..1 texture coordinates.
var art_region: Rect2 = Rect2(0, 0, 1, 1)
var art_tint: Color = Color.WHITE
var mirrored: bool = false
var bg: Color = Palette.PANEL_SOLID
var art_fallback: Color = Palette.SURFACE_2
var outline: Color = Color(0, 0, 0, 0)
var outline_width: float = 3.0
var stripe: Color = Color(0, 0, 0, 0)
## Where the text goes (margins keep it off the art and the cut).
var content: MarginContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	content = MarginContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	_set_margins()


func set_mirrored(on: bool) -> void:
	mirrored = on
	_set_margins()


func _set_margins() -> void:
	# A tile that is all picture keeps its text off the cut only.
	var near: int = int(art_w + 12.0) if art_w < 140.0 else int(CUT + 10.0)
	var far: int = int(CUT + 10.0)
	content.add_theme_constant_override("margin_left", far if mirrored else near)
	content.add_theme_constant_override("margin_right", near if mirrored else far)
	content.add_theme_constant_override("margin_top", 7)
	content.add_theme_constant_override("margin_bottom", 6)


## Picks the art part of a card image: landscape cards (heroes, evolutions) carry the art on
## their left half, portrait ones in the top half.
static func region_for(tex: Texture2D) -> Rect2:
	if tex == null:
		return Rect2(0, 0, 1, 1)
	if tex.get_width() > tex.get_height():
		return Rect2(0.03, 0.10, 0.44, 0.62)
	return Rect2(0.08, 0.10, 0.84, 0.45)


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	# Parallelogram leaning like the app's cuts: the top edge starts CUT in on the left.
	var body := PackedVector2Array([Vector2(CUT, 0), Vector2(w, 0), Vector2(w - CUT, h), Vector2(0, h)])
	draw_colored_polygon(body, bg)
	var aw: float = minf(art_w, w - CUT)
	var a := PackedVector2Array()
	if mirrored:
		a = PackedVector2Array([Vector2(w - aw, 0), Vector2(w, 0), Vector2(w - CUT, h), Vector2(w - aw - CUT, h)])
	else:
		a = PackedVector2Array([Vector2(CUT, 0), Vector2(CUT + aw, 0), Vector2(aw, h), Vector2(0, h)])
	if art != null:
		var uvs := PackedVector2Array()
		var x0: float = a[3].x
		var span: float = aw + CUT
		for p: Vector2 in a:
			uvs.append(Vector2(art_region.position.x + art_region.size.x * (p.x - x0) / span,
				art_region.position.y + art_region.size.y * p.y / h))
		draw_polygon(a, PackedColorArray([art_tint, art_tint, art_tint, art_tint]), uvs, art)
	else:
		draw_colored_polygon(a, art_fallback * art_tint)
	if stripe.a > 0.0:
		var sx: float = (w - aw - CUT - 6.0) if mirrored else aw + 2.0
		draw_colored_polygon(PackedVector2Array([Vector2(sx + CUT, 0), Vector2(sx + CUT + 6, 0), Vector2(sx + 6, h),
			Vector2(sx, h)]), stripe)
	if outline.a > 0.0:
		var loop: PackedVector2Array = body.duplicate()
		loop.append(body[0])
		draw_polyline(loop, outline, outline_width, true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
