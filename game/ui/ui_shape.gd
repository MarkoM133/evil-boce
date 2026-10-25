class_name UiShape
extends Control
## A flat shape the HUD draws itself, with an optional centred label: a slanted chip (the web
## app's clip-path cut), a chevron (phase steps), a diamond (energy, cost, cores) or the compass
## star of the logo (stages claimed).

enum Kind { SLANT, CHEVRON, DIAMOND, STAR }

var kind: Kind = Kind.SLANT
var fill: Color = Palette.SURFACE_2
## Drawn around the shape when its alpha is above 0.
var outline: Color = Color(0, 0, 0, 0)
var outline_width: float = 2.0
## How far a slant or chevron cuts in, px.
var cut: float = 10.0
var label: Label


## A shape of `size_` with `text` centred on it in the display face (empty text: no label).
static func make(kind_: Kind, fill_: Color, size_: Vector2, text: String = "", font_size: int = 16,
		text_color: Color = Palette.FG) -> UiShape:
	var s := UiShape.new()
	s.kind = kind_
	s.fill = fill_
	s.custom_minimum_size = size_
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not text.is_empty():
		var l: Label = UiTheme.label(text, font_size, text_color)
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.add_child(l)
		s.label = l
	return s


## A slanted chip just wide enough for `text`.
static func chip(text: String, fill_: Color, text_color: Color = Palette.FG, font_size: int = 16,
		height: float = 28.0, pad: float = 16.0) -> UiShape:
	var font: Font = UiTheme.display_heavy()
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + pad * 2.0
	return make(Kind.SLANT, fill_, Vector2(ceilf(w), height), text, font_size, text_color)


func _draw() -> void:
	var pts: PackedVector2Array = _points()
	if pts.is_empty():
		return
	if fill.a > 0.0:
		draw_colored_polygon(pts, fill)
	if outline.a > 0.0:
		var loop: PackedVector2Array = pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, outline, outline_width, true)


func _points() -> PackedVector2Array:
	var w: float = size.x
	var h: float = size.y
	match kind:
		Kind.SLANT:
			return PackedVector2Array([Vector2(cut, 0), Vector2(w, 0), Vector2(w - cut, h), Vector2(0, h)])
		Kind.CHEVRON:
			return PackedVector2Array([Vector2(0, 0), Vector2(w - cut, 0), Vector2(w, h * 0.5), Vector2(w - cut, h),
				Vector2(0, h), Vector2(cut, h * 0.5)])
		Kind.DIAMOND:
			return PackedVector2Array([Vector2(w * 0.5, 0), Vector2(w, h * 0.5), Vector2(w * 0.5, h), Vector2(0, h * 0.5)])
		Kind.STAR:
			# Eight points like the logo's compass: long N/E/S/W, short diagonals.
			var c := Vector2(w, h) * 0.5
			var r: float = minf(w, h) * 0.5
			var out := PackedVector2Array()
			for i: int in 16:
				var a: float = -PI * 0.5 + i * PI / 8.0
				var rr: float = r if i % 4 == 0 else (r * 0.62 if i % 2 == 0 else r * 0.34)
				out.append(c + Vector2(cos(a), sin(a)) * rr)
			return out
	return PackedVector2Array()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
