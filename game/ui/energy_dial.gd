class_name EnergyDial
extends Control
## A player's energy (mockup HUD 1b/1c): the number on a diamond, and a ring of segments round
## it, one per energy up to the match's limit: lit for what is left, dark for what was spent
## this turn, faint for what the turn does not give yet. `preview` (when not -1) shows what
## would be left after paying for a card ("3 → 1").

var value: int = 0
## Energy the turn gives (the ring's dark part ends here).
var cap: int = 0
var max_value: int = 5
var color: Color = Palette.GOLD
var number_color: Color = Color.BLACK
var preview: int = -1
## Flashes when the value drops (the energy was spent).
var _flash: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_value(v: int, cap_: int, max_: int) -> void:
	if v < value:
		_flash = 1.0
	value = v
	cap = cap_
	max_value = maxi(max_, 1)
	tooltip_text = "Energy %d of %d" % [value, cap]
	queue_redraw()


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.5)
		queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r1: float = minf(size.x, size.y) * 0.48
	var r0: float = r1 * 0.8
	var gap: float = 0.16 if max_value <= 7 else 0.08
	var step: float = TAU / max_value
	for i: int in max_value:
		var a0: float = -PI / 2.0 + i * step + gap * 0.5
		var a1: float = a0 + step - gap
		var pts := PackedVector2Array()
		for k: int in 9:
			pts.append(c + Vector2.from_angle(lerpf(a0, a1, k / 8.0)) * r1)
		for k: int in 9:
			pts.append(c + Vector2.from_angle(lerpf(a1, a0, k / 8.0)) * r0)
		var col: Color = color if i < value else (Palette.LINE if i < cap else Color(Palette.LINE, 0.35))
		if i < value and preview >= 0 and i >= preview:
			col = color.darkened(0.45)
		draw_colored_polygon(pts, col.lerp(Color.WHITE, _flash * 0.6) if i < value else col)
		pts.append(pts[0])
		draw_polyline(pts, Color.BLACK, maxf(1.5, r1 * 0.035), true)
	# The diamond with the number.
	var d: float = r0 * 0.78
	var diamond := PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)])
	draw_colored_polygon(diamond, color.lerp(Color.WHITE, _flash * 0.5))
	var loop: PackedVector2Array = diamond.duplicate()
	loop.append(diamond[0])
	draw_polyline(loop, Color.BLACK, maxf(2.0, r1 * 0.05), true)
	var font: Font = UiTheme.display_heavy()
	var fs: int = roundi(d * 0.95)
	var txt: String = str(value)
	var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, c + Vector2(-w * 0.5, fs * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, number_color)
	if preview >= 0:
		var p: String = "→ %d" % preview
		var ps: int = maxi(12, roundi(fs * 0.45))
		draw_string(font, c + Vector2(r1 * 0.55, r1 * 0.95), p, HORIZONTAL_ALIGNMENT_LEFT, -1, ps, Palette.FG)
