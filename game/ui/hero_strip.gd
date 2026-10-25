class_name HeroStrip
extends Control
## The web app's header strip in the game: every hero's card art in slanted slices that drift
## slowly to the left, dimmed; the one under the mouse lights up and shows its name, and the
## strip stops while the mouse is on it. Ends fade into the background.

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
		_offset = fposmod(_offset + SPEED * delta, _ids.size() * (SLICE_W + GAP))
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


func _index_at(p: Vector2) -> int:
	if _ids.is_empty():
		return -1
	var span: float = SLICE_W + GAP
	# Undo the lean at this height, then find the slice.
	var x: float = p.x + _offset + LEAN * (p.y / maxf(size.y, 1.0)) - 24.0
	return posmod(floori(x / span), _ids.size())


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG)
	if _ids.is_empty():
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
