class_name UiSegments
extends Control
## A bar in slanted segments (HP, GDD 11): `value` of `max_value` lit in `color`, the next
## `ghost` segments in white (damage about to land), the rest dark. `mirrored` fills from the right.

var value: int = 0
var max_value: int = 1
var ghost: int = 0
var color: Color = Palette.HP
var empty: Color = Palette.LINE
var mirrored: bool = false
var gap: float = 2.0
var lean: float = 3.0


func _draw() -> void:
	var n: int = maxi(max_value, 1)
	var w: float = (size.x - gap * (n - 1)) / n
	var h: float = size.y
	for i: int in n:
		var idx: int = n - 1 - i if mirrored else i
		var x: float = idx * (w + gap)
		var c: Color = empty
		if i < value - ghost:
			c = color
		elif i < value:
			c = Palette.FG
		draw_colored_polygon(PackedVector2Array([Vector2(x + lean, 0), Vector2(x + w, 0), Vector2(x + w - lean, h),
			Vector2(x, h)]), c)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
