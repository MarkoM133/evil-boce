class_name MenuTile
extends Control
## A big slanted tile for the tile-hub main menu (mockup M7): a colour ground with diagonal
## speed lines (or card art under a colour wash), the heroes' pixel figures standing in it, a
## title in the heavy italic and a line under it. Hover lifts and outlines it; a click says
## `pressed`.

signal pressed

var title: String = ""
var subtitle: String = ""
## Card art under the wash; leave empty for the plain ground with speed lines.
var art: Texture2D
var region: Rect2 = Rect2(0, 0, 1, 1)
## Crop `art` to the tile's shape (card_art_region) instead of using `region`.
var fit_art: bool = false
var color: Color = Palette.PANEL_SOLID
var title_size: int = 64
var title_color: Color = Palette.FG
var cut: float = 18.0
## Pixel figures (sprite standees) standing on the tile's floor, left to right; every second
## one faces the other way, so two of them face off.
var figures: Array[Texture2D] = []
## Two card images side by side, cut apart on a slant (a face-off); overrides `art`.
var split_art: Array[Texture2D] = []
## Figure height as a share of the tile's height.
var figure_size: float = 0.86
var _hover: bool = false
var _title_l: Label
var _sub_l: Label
var _figure_nodes: Array[TextureRect] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	clip_contents = true


func _ready() -> void:
	pivot_offset = size * 0.5
	for tex: Texture2D in figures:
		var f := TextureRect.new()
		f.texture = tex
		f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		f.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		f.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		f.flip_h = _figure_nodes.size() % 2 == 1
		add_child(f)
		_figure_nodes.append(f)
	var text := VBoxContainer.new()
	text.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	text.grow_vertical = Control.GROW_DIRECTION_BEGIN
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation", 0)
	add_child(text)
	_title_l = UiTheme.label(title, title_size, title_color)
	_title_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	_title_l.add_theme_constant_override("outline_size", 8 if title_color == Palette.FG else 0)
	text.add_child(_title_l)
	if not subtitle.is_empty():
		_sub_l = Label.new()
		_sub_l.text = subtitle
		_sub_l.add_theme_font_size_override("font_size", 14 if title_size > 40 else 12)
		var sub_color: Color = Color(title_color, 0.85) if title_color != Palette.FG or art != null or not figures.is_empty() else Palette.MUTED
		_sub_l.add_theme_color_override("font_color", sub_color)
		text.add_child(_sub_l)
	_layout(text)
	resized.connect(func() -> void:
		pivot_offset = size * 0.5
		_layout(text))
	mouse_entered.connect(func() -> void: _set_hover(true))
	mouse_exited.connect(func() -> void: _set_hover(false))
	focus_entered.connect(func() -> void: _set_hover(true))
	focus_exited.connect(func() -> void: _set_hover(false))


func _layout(text: VBoxContainer) -> void:
	text.position = Vector2(cut + 20.0, size.y - text.get_combined_minimum_size().y - 14.0)
	var n: int = _figure_nodes.size()
	if n == 0:
		return
	# A tall tile has the crew stand above its title; a wide one on the floor, right of it.
	var tall: bool = size.y > size.x * 0.75
	var floor_y: float = size.y - text.get_combined_minimum_size().y - 24.0 if tall else size.y + 6.0
	# As tall as the tile allows, but a crew must fit across the tile.
	var w: float = minf(floor_y * figure_size * 175.0 / 206.0, size.x * (0.92 if tall else 0.8) / (n * 0.78 + 0.22))
	var h: float = w * 206.0 / 175.0
	var span: float = w * (n * 0.78 + 0.22)
	var x0: float = (size.x - span) * 0.5 if tall else size.x - span - cut - 10.0
	for i: int in n:
		var f: TextureRect = _figure_nodes[i]
		f.size = Vector2(w, h)
		f.position = Vector2(x0 + i * (span - w) / maxf(float(n - 1), 1.0), floor_y - h)
		f.set_meta("rest_y", f.position.y)


func _set_hover(on: bool) -> void:
	_hover = on
	var t: Tween = create_tween()
	t.tween_property(self, "scale", Vector2.ONE * (1.025 if on else 1.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for i: int in _figure_nodes.size():
		var f: TextureRect = _figure_nodes[i]
		var ft: Tween = f.create_tween()
		var rest: float = JsonUtil.as_float(f.get_meta("rest_y", f.position.y))
		ft.tween_property(f, "position:y", rest - (10.0 if on else 0.0), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
	elif event.is_action_pressed("ui_accept"):
		pressed.emit()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var pts := PackedVector2Array([Vector2(cut, 0), Vector2(w, 0), Vector2(w - cut, h), Vector2(0, h)])
	if split_art.size() == 2:
		_draw_split(w, h, pts)
	elif art != null:
		var r: Rect2 = card_art_region(art, w / h) if fit_art else region
		var uvs := PackedVector2Array()
		for p: Vector2 in pts:
			uvs.append(Vector2(r.position.x + r.size.x * p.x / w, r.position.y + r.size.y * p.y / h))
		var tint := Color(1, 1, 1) if _hover else Color(0.8, 0.8, 0.8)
		draw_polygon(pts, PackedColorArray([tint, tint, tint, tint]), uvs, art)
		if figures.is_empty():
			draw_polygon(pts, PackedColorArray([Color(color, 0.6), Color(color, 0.25), Color(color, 0.6), Color(color, 0.92)]))
		else:
			# A scene behind the figures: tinted, clear at the top, deep at the bottom for the title.
			draw_polygon(pts, PackedColorArray([Color(color, 0.18), Color(color, 0.08), Color(color, 0.7), Color(color, 0.85)]))
			draw_rect(Rect2(0, h - 26, w, 26), Color(0, 0, 0, 0.25))
	elif figures.is_empty():
		draw_colored_polygon(pts, color.lightened(0.06) if _hover else color)
	else:
		# A lit ground: lighter top right, darker bottom left, with diagonal speed lines.
		var top: Color = color.lightened(0.25 if _hover else 0.15)
		var low: Color = color.darkened(0.45)
		draw_polygon(pts, PackedColorArray([color, top, color, low]))
		var lines := Color(1, 1, 1, 0.07)
		var step: float = 46.0
		var x: float = -h
		while x < w:
			draw_line(Vector2(x, h), Vector2(x + h * 0.7, 0), lines, 10.0)
			x += step
		# A soft floor under the figures.
		draw_rect(Rect2(0, h - 26, w, 26), Color(0, 0, 0, 0.25))
		# The lines and the floor ran past the slanted ends: cut them back to the background.
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(cut, 0), Vector2(0, h)]), Palette.BG)
		draw_colored_polygon(PackedVector2Array([Vector2(w, 0), Vector2(w, h), Vector2(w - cut, h)]), Palette.BG)
	if _hover:
		var loop: PackedVector2Array = pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, Palette.GOLD, 3.0, true)


## Two card arts meeting on a slanted line, darker at the bottom for the title.
func _draw_split(w: float, h: float, pts: PackedVector2Array) -> void:
	var lean: float = 60.0
	var mid: float = w * 0.5
	var halves: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(cut, 0), Vector2(mid + lean, 0), Vector2(mid - lean, h), Vector2(0, h)]),
		PackedVector2Array([Vector2(mid + lean, 0), Vector2(w, 0), Vector2(w - cut, h), Vector2(mid - lean, h)]),
	]
	var spans: Array[Vector2] = [Vector2(0, mid + lean), Vector2(mid - lean, w)]
	var tint := Color(1, 1, 1) if _hover else Color(0.82, 0.82, 0.82)
	for i: int in 2:
		var tex: Texture2D = split_art[i]
		var poly: PackedVector2Array = halves[i]
		var x0: float = spans[i].x
		var span: float = spans[i].y - spans[i].x
		if tex == null:
			draw_colored_polygon(poly, color)
			continue
		var r: Rect2 = card_art_region(tex, span / h)
		var uvs := PackedVector2Array()
		for p: Vector2 in poly:
			uvs.append(Vector2(r.position.x + r.size.x * (p.x - x0) / span, r.position.y + r.size.y * p.y / h))
		draw_polygon(poly, PackedColorArray([tint, tint, tint, tint]), uvs, tex)
	# Dark at the bottom (the title), a touch of the tile's colour over all.
	var clear := Color(0, 0, 0, 0)
	var dark := Color(0, 0, 0, 0.8)
	draw_polygon(PackedVector2Array([Vector2(cut * 0.4, h * 0.45), Vector2(w - cut * 0.4, h * 0.45), Vector2(w - cut, h), Vector2(0, h)]),
		PackedColorArray([clear, clear, dark, dark]))
	draw_polygon(pts, PackedColorArray([Color(color, 0.18), Color(color, 0.05), Color(color, 0.18), Color(color, 0.35)]))
	# The cut between them.
	draw_colored_polygon(PackedVector2Array([Vector2(mid + lean - 4, 0), Vector2(mid + lean + 4, 0), Vector2(mid - lean + 4, h),
		Vector2(mid - lean - 4, h)]), Palette.GOLD)


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


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
