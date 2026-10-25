class_name HeroStrip
extends Control
## The web app's header strip in the game: every hero's card art in slanted slices that drift
## slowly to the left, dimmed; the one under the mouse lights up and shows its name, and the
## strip stops while the mouse is on it. Ends fade into the background. `vertical` stacks the
## slices down a strip along the side of the screen instead.

signal hero_clicked(hero_id: String)

const SLICE_W: float = 150.0
const GAP: float = 6.0
const SPEED: float = 22.0
## How far each slice leans (px across its height).
const LEAN: float = 29.0
const FADE: float = 90.0

var _ids: PackedStringArray = PackedStringArray()
var _names: PackedStringArray = PackedStringArray()
var _colors: Array[Color] = []
var _art: Array[Texture2D] = []
var _offset: float = 0.0
var _hover: int = -1
## Drift to the right instead of the left.
var reverse: bool = false
## The colour edges run along the top (a strip at the bottom of the screen).
var edge_top: bool = false
## Slices stacked down the screen (a strip along the left edge), drifting up; the colour edges
## run along the right side.
var vertical: bool = false

## A vertical strip's slices: their height and how far their top and bottom edges lean.
const SLICE_H: float = 120.0
const LEAN_V: float = 22.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 116)
	mouse_filter = Control.MOUSE_FILTER_PASS
	clip_contents = true


## Heroes from the card database (their card images); nothing to draw without one.
func setup(db: CardDb) -> void:
	_ids.clear()
	_names.clear()
	_colors.clear()
	_art.clear()
	if db == null or not db.is_ok():
		return
	for h: HeroDef in db.heroes:
		_ids.append(h.id)
		_names.append(h.name)
		_colors.append(Palette.hero(h.color_name))
		_art.append(db.thumb(h.id))
	queue_redraw()


func _process(delta: float) -> void:
	if _ids.is_empty():
		return
	if _hover < 0:
		_offset = fposmod(_offset + SPEED * delta * (-1.0 if reverse else 1.0), _ids.size() * _span())
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _index_at((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var i: int = _index_at(mb.position)
			if i >= 0:
				hero_clicked.emit(_ids[i])


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = -1


func _span() -> float:
	return (SLICE_H if vertical else SLICE_W) + GAP


func _index_at(p: Vector2) -> int:
	if _ids.is_empty():
		return -1
	var span: float = _span()
	if vertical:
		# A slice's top edge runs from LEAN_V down on the left to its top on the right.
		var y: float = p.y + _offset - LEAN_V * (1.0 - p.x / maxf(size.x, 1.0)) - 24.0
		return posmod(floori(y / span), _ids.size())
	# Undo the lean at this height, then find the slice.
	var x: float = p.x + _offset + LEAN * (p.y / maxf(size.y, 1.0)) - 24.0
	return posmod(floori(x / span), _ids.size())


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG)
	if _ids.is_empty():
		return
	if vertical:
		_draw_vertical()
		return
	var h: float = size.y
	var span: float = SLICE_W + GAP
	var first: int = floori(_offset / span) - 1
	var count: int = ceili(size.x / span) + 3
	var font: Font = UiTheme.display_heavy()
	for k: int in count:
		var n: int = first + k
		var i: int = posmod(n, _ids.size())
		var x: float = n * span - _offset + 24.0
		var pts := PackedVector2Array([Vector2(x + LEAN, 0), Vector2(x + LEAN + SLICE_W, 0), Vector2(x + SLICE_W, h), Vector2(x, h)])
		var lit: bool = i == _hover
		var tint := Color(1, 1, 1) if lit else Color(0.5, 0.5, 0.5)
		var tex: Texture2D = _art[i]
		if tex != null:
			# Landscape hero cards carry the art on their left; take a band matching the slice.
			var region := Rect2(0.03, 0.10, 0.44, 0.42) if tex.get_width() > tex.get_height() else Rect2(0.05, 0.08, 0.9, 0.4)
			var uvs := PackedVector2Array()
			for pt: Vector2 in pts:
				uvs.append(Vector2(region.position.x + region.size.x * (pt.x - x) / (SLICE_W + LEAN),
					region.position.y + region.size.y * pt.y / h))
			draw_polygon(pts, PackedColorArray([tint, tint, tint, tint]), uvs, tex)
		else:
			draw_colored_polygon(pts, _colors[i].darkened(0.5))
		# Colour edge along the bottom, like the app's slices.
		if edge_top:
			draw_colored_polygon(PackedVector2Array([Vector2(x + LEAN, 0), Vector2(x + LEAN + SLICE_W, 0),
				Vector2(x + SLICE_W + LEAN * (1.0 - 3.0 / h), 3), Vector2(x + LEAN * (1.0 - 3.0 / h), 3)]), _colors[i])
		else:
			draw_colored_polygon(PackedVector2Array([Vector2(x + 3.0 * LEAN / h, h - 3), Vector2(x + SLICE_W + 3.0 * LEAN / h, h - 3),
				Vector2(x + SLICE_W, h), Vector2(x, h)]), _colors[i])
		if lit:
			draw_string(font, Vector2(x + 14, h - 12), _names[i], HORIZONTAL_ALIGNMENT_LEFT, SLICE_W, 17, Palette.FG)
	# Fade both ends into the background.
	var clear := Color(Palette.BG, 0.0)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(FADE, 0), Vector2(FADE, h), Vector2(0, h)]),
		PackedColorArray([Palette.BG, clear, clear, Palette.BG]))
	draw_polygon(PackedVector2Array([Vector2(size.x - FADE, 0), Vector2(size.x, 0), Vector2(size.x, h), Vector2(size.x - FADE, h)]),
		PackedColorArray([clear, Palette.BG, Palette.BG, clear]))


func _draw_vertical() -> void:
	var w: float = size.x
	var span: float = _span()
	var first: int = floori(_offset / span) - 1
	var count: int = ceili(size.y / span) + 3
	var font: Font = UiTheme.display_heavy()
	for k: int in count:
		var n: int = first + k
		var i: int = posmod(n, _ids.size())
		var y: float = n * span - _offset + 24.0
		var pts := PackedVector2Array([Vector2(0, y + LEAN_V), Vector2(w, y), Vector2(w, y + SLICE_H), Vector2(0, y + SLICE_H + LEAN_V)])
		var lit: bool = i == _hover
		var tint := Color(1, 1, 1) if lit else Color(0.5, 0.5, 0.5)
		var tex: Texture2D = _art[i]
		if tex != null:
			var region: Rect2 = HeroSlice.card_art_region(tex, w / (SLICE_H + LEAN_V))
			var uvs := PackedVector2Array()
			for pt: Vector2 in pts:
				uvs.append(region.position + region.size * Vector2(pt.x / w, (pt.y - y) / (SLICE_H + LEAN_V)))
			draw_polygon(pts, PackedColorArray([tint, tint, tint, tint]), uvs, tex)
		else:
			draw_colored_polygon(pts, _colors[i].darkened(0.5))
		draw_colored_polygon(PackedVector2Array([Vector2(w - 3, y + 3.0 * LEAN_V / w), Vector2(w, y), Vector2(w, y + SLICE_H),
			Vector2(w - 3, y + SLICE_H + 3.0 * LEAN_V / w)]), _colors[i])
		var name_color := Palette.FG if lit else Color(Palette.FG, 0.6)
		draw_string(font, Vector2(14, y + SLICE_H + LEAN_V * (1.0 - 14.0 / w) - 12), _names[i], HORIZONTAL_ALIGNMENT_LEFT, w - 28, 17, name_color)
	var clear := Color(Palette.BG, 0.0)
	var h: float = size.y
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, FADE), Vector2(0, FADE)]),
		PackedColorArray([Palette.BG, Palette.BG, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(0, h - FADE), Vector2(w, h - FADE), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([clear, clear, Palette.BG, Palette.BG]))


## Strips `h` high along the top and the bottom of `parent` (drifting opposite ways), each with
## a red line on its inner edge: the cinema menu's and the splash's letterbox.
static func letterbox(parent: Control, db: CardDb, h: float = 110.0) -> void:
	for bottom: bool in [false, true]:
		var strip := HeroStrip.new()
		strip.setup(db)
		strip.reverse = bottom
		strip.edge_top = bottom
		strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
		strip.custom_minimum_size = Vector2(0, h)
		if bottom:
			strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
			strip.offset_top = -h
		parent.add_child(strip)
		var line := ColorRect.new()
		line.color = Palette.ACCENT
		line.set_anchors_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
		line.offset_top = -h - 3.0 if bottom else h
		line.offset_bottom = -h if bottom else h + 3.0
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(line)
