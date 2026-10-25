class_name MenuTile
extends Control
## A big slanted tile for the tile-hub main menu (mockup M7): optional hero art under a colour
## wash, a title in the heavy italic and a line under it. Hover lifts and brightens it; a click
## says `pressed`.

signal pressed

var title: String = ""
var subtitle: String = ""
var art: Texture2D
var region: Rect2 = Rect2(0, 0, 1, 1)
## The wash over the art (strong at the bottom left, light at the top right).
var color: Color = Palette.PANEL_SOLID
var title_size: int = 64
var title_color: Color = Palette.FG
var cut: float = 18.0
var _hover: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL


func _ready() -> void:
	pivot_offset = size * 0.5
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	mouse_entered.connect(func() -> void: _set_hover(true))
	mouse_exited.connect(func() -> void: _set_hover(false))
	focus_entered.connect(func() -> void: _set_hover(true))
	focus_exited.connect(func() -> void: _set_hover(false))


func _set_hover(on: bool) -> void:
	_hover = on
	var t: Tween = create_tween()
	t.tween_property(self, "scale", Vector2.ONE * (1.03 if on else 1.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
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
	if art != null:
		var uvs := PackedVector2Array()
		for p: Vector2 in pts:
			uvs.append(Vector2(region.position.x + region.size.x * p.x / w, region.position.y + region.size.y * p.y / h))
		var tint := Color(1, 1, 1) if _hover else Color(0.8, 0.8, 0.8)
		draw_polygon(pts, PackedColorArray([tint, tint, tint, tint]), uvs, art)
		# Colour wash: strong at the bottom left where the title is, light at the top right.
		var strong := Color(color, 0.92)
		var light := Color(color, 0.25)
		draw_polygon(pts, PackedColorArray([Color(color, 0.6), light, Color(color, 0.6), strong]))
	else:
		draw_colored_polygon(pts, color.lightened(0.06) if _hover else color)
	if _hover:
		var loop: PackedVector2Array = pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, Palette.GOLD, 3.0, true)
	var font: Font = UiTheme.display_heavy()
	var x: float = cut + 22.0
	var sub_size: int = 15 if title_size > 40 else 13
	var base: float = h - 18.0 - (sub_size + 8.0 if not subtitle.is_empty() else 0.0)
	draw_string_outline(font, Vector2(x, base), title, HORIZONTAL_ALIGNMENT_LEFT, w - x, title_size, 8, Color(0, 0, 0, 0.45))
	draw_string(font, Vector2(x, base), title, HORIZONTAL_ALIGNMENT_LEFT, w - x, title_size, title_color)
	if not subtitle.is_empty():
		var sub_color: Color = Color(title_color, 0.8) if art != null or title_color != Palette.FG else Palette.MUTED
		draw_string(UiTheme.body_font(), Vector2(x - 4.0, h - 18.0), subtitle, HORIZONTAL_ALIGNMENT_LEFT, w - x, sub_size, sub_color)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
