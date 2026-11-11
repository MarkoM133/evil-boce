class_name GameCursor
## The game's own mouse cursor (item 19, C1, Marko 2026-11-10: "romb i ciao"): a sharp slanted arrow like
## the cuts of the buttons, straw at rest, red over what can be clicked (buttons, cards, hero panels,
## balls), a straw diamond while a throw is aimed. Drawn from its outline at 32 px for a window 900 px
## tall, bigger on a bigger one. Shapes: the arrow is CURSOR_ARROW, the red one CURSOR_POINTING_HAND (which
## clickable controls ask for), the diamond CURSOR_CROSS (the match asks for it while aiming).

const GOLD := "#f4b62a"
const GOLD_FACET := "#c98f12"
const RED := "#e3120b"
const RED_FACET := "#9c0c07"
const DART := "M3 2 L26 12.5 L15 15.5 L11.5 27 Z"
## Where the arrow points and where the diamond's middle is, in the 32 px drawing.
const ARROW_TIP := Vector2(3, 2)
const DIAMOND_MID := Vector2(16, 16)

static var _scale: float = 0.0
static var _hooked: bool = false


## Puts the cursor in place for the window's size now (again only when that changed), and makes every
## button ask for the red one.
static func install(tree: SceneTree) -> void:
	if DisplayServer.get_name() == "headless":
		return
	# The system arrow when it is asked for (Settings → Interface → Cursor).
	if not GameSettings.game_cursor():
		if _scale > 0.0:
			_scale = 0.0
			for shape: Input.CursorShape in [Input.CURSOR_ARROW, Input.CURSOR_POINTING_HAND, Input.CURSOR_CROSS]:
				Input.set_custom_mouse_cursor(null, shape)
		return
	var k: float = scale_for(DisplayServer.window_get_size().y)
	if absf(k - _scale) > 0.01:
		_scale = k
		Input.set_custom_mouse_cursor(_image(dart_svg(false), k), Input.CURSOR_ARROW, ARROW_TIP * k)
		Input.set_custom_mouse_cursor(_image(dart_svg(true), k), Input.CURSOR_POINTING_HAND, ARROW_TIP * k)
		Input.set_custom_mouse_cursor(_image(diamond_svg(), k), Input.CURSOR_CROSS, DIAMOND_MID * k)
	if not _hooked:
		_hooked = true
		# Godot's buttons keep the plain arrow unless told: every one that comes in asks for the red one.
		tree.node_added.connect(func(n: Node) -> void:
			var b := n as BaseButton
			if b != null and b.mouse_default_cursor_shape == Control.CURSOR_ARROW:
				b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND)


## 32 px on a window up to 900 px tall, in step with a taller one (at most two and a half times).
static func scale_for(window_height: int) -> float:
	return clampf(float(window_height) / 900.0, 1.0, 2.5)


static func dart_svg(clickable: bool) -> String:
	var fill: String = RED if clickable else GOLD
	var facet: String = RED_FACET if clickable else GOLD_FACET
	var body: String = '<path d="%s" fill="%s"/><path d="M3 2 L15 15.5 L11.5 27 Z" fill="%s"/>' % [DART, fill, facet]
	body += '<path d="%s" fill="none" stroke="#000" stroke-width="2.4" stroke-linejoin="round"/>' % DART
	if clickable:
		body += '<path d="M6.5 5.5 L19.5 11.5" stroke="#fff" stroke-width="1.4" stroke-linecap="round"/>'
	return _svg(body)


static func diamond_svg() -> String:
	var d: String = "M0 -12 L12 0 L0 12 L-12 0 Z"
	return _svg('<g transform="translate(16 16)"><path d="%s" fill="none" stroke="#000" stroke-width="5.4" stroke-linejoin="round"/>' % d
		+ '<path d="%s" fill="none" stroke="%s" stroke-width="2.4" stroke-linejoin="round"/>' % [d, GOLD]
		+ '<circle r="2.4" fill="%s" stroke="#000" stroke-width="1.3"/></g>' % GOLD)


static func _svg(body: String) -> String:
	return '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32">%s</svg>' % body


static func _image(svg: String, k: float) -> Image:
	var img := Image.new()
	img.load_svg_from_string(svg, k)
	return img
