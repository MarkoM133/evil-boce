class_name HeroSlice
extends Control
## A hero in the match HUD's roster (GDD 11), like the web app's deck slices: a slanted strip with
## a crop of the card art at one end (the right end when `mirrored`), and room for the name, HP
## and cores on the rest. States are drawn here: outline (active / pickable), a red stripe
## (in a battle), grey art (KO).

const ART_W: float = 84.0
const CUT: float = 16.0
const EDGE_W: float = 7.0

## Width of the art end; set it to the full width for a tile that is all picture.
var art_w: float = ART_W

var art: Texture2D
## Part of the texture to show, in 0..1 texture coordinates.
var art_region: Rect2 = Rect2(0, 0, 1, 1)
## The art keeps its proportions (Marko 2026-11-08: the resting panels squeezed the faces wide):
## art_region is cut to the drawn shape, a band near its top (faces) or its middle, not stretched.
var fit_art: bool = true
var art_tint: Color = Color.WHITE
var mirrored: bool = false
var bg: Color = Palette.PANEL_SOLID
var art_fallback: Color = Palette.SURFACE_2
var outline: Color = Color(0, 0, 0, 0)
var outline_width: float = 3.0
var stripe: Color = Color(0, 0, 0, 0)
## The hero's card colour as a band on the slanted edge away from the art (Marko 2026-10-26).
var color_edge: Color = Color(0, 0, 0, 0)
## Where the text goes (margins keep it off the art and the cut).
var content: MarginContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The art is a card thumbnail drawn much smaller: through its mipmaps, or its edges shimmer and
	# look crumpled (Marko 2026-11-08). The text inside keeps the plain filter.
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	content = MarginContainer.new()
	content.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)
	_set_margins()


func set_mirrored(on: bool) -> void:
	mirrored = on
	_set_margins()


func _set_margins() -> void:
	# A tile that is all picture keeps its text off the cut only.
	# The art leans by CUT, so the text keeps clear of its far corner too.
	var near: int = int(art_w + CUT + 8.0) if art_w < 140.0 else int(CUT + 10.0)
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
	# The art box on a landscape card ends at 0.445 of its width; past it is the frame, which a
	# slanted tile shows in its top corner (Marko 2026-11-02: a purple corner on every hero).
	if tex.get_width() > tex.get_height():
		return Rect2(0.03, 0.10, 0.41, 0.62)
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
		var r: Rect2 = _fitted(art_region, span / maxf(h, 1.0)) if fit_art else art_region
		for p: Vector2 in a:
			uvs.append(Vector2(r.position.x + r.size.x * (p.x - x0) / span,
				r.position.y + r.size.y * p.y / h))
		draw_polygon(a, PackedColorArray([art_tint, art_tint, art_tint, art_tint]), uvs, art)
	else:
		draw_colored_polygon(a, art_fallback * art_tint)
	if stripe.a > 0.0:
		var sx: float = (w - aw - CUT - 6.0) if mirrored else aw + 2.0
		draw_colored_polygon(PackedVector2Array([Vector2(sx + CUT, 0), Vector2(sx + CUT + 6, 0), Vector2(sx + 6, h),
			Vector2(sx, h)]), stripe)
	if color_edge.a > 0.0:
		var e: float = EDGE_W
		if mirrored:
			draw_colored_polygon(PackedVector2Array([Vector2(CUT, 0), Vector2(CUT + e, 0), Vector2(e, h), Vector2(0, h)]), color_edge)
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(w - e, 0), Vector2(w, 0), Vector2(w - CUT, h), Vector2(w - CUT - e, h)]), color_edge)
	if outline.a > 0.0:
		var loop: PackedVector2Array = body.duplicate()
		loop.append(body[0])
		draw_polyline(loop, outline, outline_width, true)


## Where the colour edge's inner side is, at height `y`: the slice leans, so it depends on the height.
func edge_inner_x(y: float) -> float:
	var lean: float = CUT * y / maxf(size.y, 1.0)
	return (CUT + EDGE_W - lean) if mirrored else (size.x - EDGE_W - lean)


## `box` cut to `aspect` (width / height) in the texture's pixels: a wider shape keeps the box's
## width and takes a band near its top (where the faces are), a taller one keeps its height and
## takes the middle.
func _fitted(box: Rect2, aspect: float) -> Rect2:
	var px := Vector2(art.get_width(), art.get_height())
	var bw: float = box.size.x * px.x
	var bh: float = box.size.y * px.y
	if bw <= 0.0 or bh <= 0.0:
		return box
	if bw / bh < aspect:
		var nh: float = bw / aspect
		return Rect2(box.position.x, box.position.y + (bh - nh) * 0.15 / px.y, box.size.x, nh / px.y)
	var nw: float = bh * aspect
	return Rect2(box.position.x + (bw - nw) * 0.5 / px.x, box.position.y, nw / px.x, box.size.y)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


## The art part of a card image cropped to `aspect` (width / height). Landscape hero cards
## carry the art in a box on their left; portrait cards in their top half.
static func card_art_region(tex: Texture2D, aspect: float) -> Rect2:
	# Portrait cards: the art window sits under the name bar.
	var box: Rect2 = Rect2(0.025, 0.07, 0.405, 0.72) if tex.get_width() > tex.get_height() else Rect2(0.075, 0.115, 0.85, 0.385)
	var px := Vector2(tex.get_width(), tex.get_height())
	var bw: float = box.size.x * px.x
	var bh: float = box.size.y * px.y
	if bw / bh < aspect:
		# The box is taller than the slot: keep its width, take a band near the top (faces).
		var nh: float = bw / aspect
		return Rect2(box.position.x, box.position.y + (bh - nh) * 0.15 / px.y, box.size.x, nh / px.y)
	var nw: float = bh * aspect
	return Rect2(box.position.x + (bw - nw) * 0.5 / px.x, box.position.y, nw / px.x, box.size.y)
