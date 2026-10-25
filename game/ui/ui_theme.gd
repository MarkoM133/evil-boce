class_name UiTheme
extends RefCounted
## The game's UI theme, built in code, in the web app's look: black, flat surfaces, compass red
## for the one main action, straw yellow for "yours / now", Barlow Condensed italic for titles,
## numbers and buttons, slanted edges (StyleBoxFlat.skew) like the app's clip-path cuts.
## Variations: "MenuItem" (main menu), "Header" (section titles), "Big" (large numbers),
## "Title" (screen titles), "Muted" (secondary text), "Toggle" (pressed = accent),
## "Primary" (the red main action), "Gold" (straw: confirm / yours), "Ghost" (no fill).

## How far buttons and chips lean (StyleBoxFlat.skew.x).
const SKEW: float = 0.22

static var _theme: Theme
static var _italic: FontVariation
static var _italic_heavy: FontVariation


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func display_font() -> Font:
	return load("res://ui/fonts/BarlowCondensed-SemiBold.ttf") as Font


static func display_bold() -> Font:
	return load("res://ui/fonts/BarlowCondensed-Bold.ttf") as Font


## Barlow Condensed Bold leaned like the app's italic headings.
static func display_italic() -> Font:
	if _italic == null:
		_italic = FontVariation.new()
		_italic.base_font = display_bold()
		_italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
	return _italic


## The heaviest look (the app's italic 800): leaned and thickened, for titles and big numbers.
static func display_heavy() -> Font:
	if _italic_heavy == null:
		_italic_heavy = FontVariation.new()
		_italic_heavy.base_font = display_bold()
		_italic_heavy.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
		_italic_heavy.variation_embolden = 0.6
	return _italic_heavy


static func body_font() -> Font:
	return load("res://ui/fonts/Barlow-Regular.ttf") as Font


static func body_semibold() -> Font:
	return load("res://ui/fonts/Barlow-SemiBold.ttf") as Font


static func box(bg: Color, radius: int = 0, border: Color = Color(0, 0, 0, 0), pad_x: float = 12,
		pad_y: float = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb


## A slanted box (the app's buttons and chips). Extra side padding keeps text off the cut edges.
static func slant(bg: Color, pad_x: float = 18, pad_y: float = 8, skew: float = SKEW) -> StyleBoxFlat:
	var sb := box(bg, 0, Color(0, 0, 0, 0), pad_x, pad_y)
	sb.skew = Vector2(skew, 0)
	sb.anti_aliasing = true
	return sb


## A label in the display face: `heavy` for titles and big numbers.
static func label(text: String, size: int, color: Color = Palette.FG, heavy: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", display_heavy() if heavy else display_italic())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 15

	t.set_color("font_color", "Label", Palette.FG)

	var header := FontVariation.new()
	header.base_font = display_italic()
	header.spacing_glyph = 1
	t.set_type_variation("Header", "Label")
	t.set_font("font", "Header", header)
	t.set_font_size("font_size", "Header", 14)
	t.set_color("font_color", "Header", Palette.MUTED)

	t.set_type_variation("Big", "Label")
	t.set_font("font", "Big", display_heavy())
	t.set_font_size("font_size", "Big", 34)

	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", display_heavy())
	t.set_font_size("font_size", "Title", 56)

	t.set_type_variation("Muted", "Label")
	t.set_color("font_color", "Muted", Palette.MUTED)
	t.set_font_size("font_size", "Muted", 13)

	# Buttons: slanted, flat, italic.
	t.set_font("font", "Button", display_italic())
	t.set_font_size("font_size", "Button", 18)
	t.set_color("font_color", "Button", Palette.FG)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Palette.FG)
	t.set_color("font_disabled_color", "Button", Color(Palette.MUTED, 0.45))
	t.set_stylebox("normal", "Button", slant(Palette.BUTTON))
	t.set_stylebox("hover", "Button", slant(Palette.BUTTON_HOVER))
	t.set_stylebox("pressed", "Button", slant(Palette.ACCENT))
	t.set_stylebox("hover_pressed", "Button", slant(Palette.ACCENT_HOVER))
	t.set_stylebox("disabled", "Button", slant(Color("111111")))
	var focus := slant(Color(0, 0, 0, 0))
	focus.draw_center = false
	focus.border_color = Palette.GOLD
	focus.set_border_width_all(2)
	t.set_stylebox("focus", "Button", focus)

	t.set_type_variation("Toggle", "Button")

	# The red main action, bigger, with a darker "ledge" under it.
	t.set_type_variation("Primary", "Button")
	t.set_font("font", "Primary", display_heavy())
	t.set_font_size("font_size", "Primary", 24)
	var prim := slant(Palette.ACCENT, 26, 10)
	prim.border_color = Palette.ACCENT_DEEP
	prim.border_width_bottom = 5
	var prim_hover := slant(Palette.ACCENT_HOVER, 26, 10)
	prim_hover.border_color = Palette.ACCENT_DEEP
	prim_hover.border_width_bottom = 7
	t.set_stylebox("normal", "Primary", prim)
	t.set_stylebox("hover", "Primary", prim_hover)
	t.set_stylebox("pressed", "Primary", slant(Palette.ACCENT_DEEP, 26, 10))
	t.set_stylebox("disabled", "Primary", slant(Color("2a1210"), 26, 10))

	t.set_type_variation("Gold", "Button")
	t.set_color("font_color", "Gold", Color.BLACK)
	t.set_color("font_hover_color", "Gold", Color.BLACK)
	t.set_color("font_pressed_color", "Gold", Color.BLACK)
	t.set_color("font_focus_color", "Gold", Color.BLACK)
	t.set_stylebox("normal", "Gold", slant(Palette.GOLD))
	t.set_stylebox("hover", "Gold", slant(Palette.GOLD.lightened(0.15)))
	t.set_stylebox("pressed", "Gold", slant(Palette.GOLD.darkened(0.2)))

	t.set_type_variation("Ghost", "Button")
	var ghost := slant(Color(0, 0, 0, 0))
	t.set_stylebox("normal", "Ghost", ghost)
	t.set_stylebox("hover", "Ghost", slant(Color(1, 1, 1, 0.06)))
	t.set_color("font_color", "Ghost", Palette.MUTED)
	t.set_color("font_hover_color", "Ghost", Palette.FG)

	# Main menu entries: big italic words; hover lays a red slanted bar behind them.
	t.set_type_variation("MenuItem", "Button")
	t.set_font("font", "MenuItem", display_heavy())
	t.set_font_size("font_size", "MenuItem", 40)
	t.set_color("font_color", "MenuItem", Palette.FG)
	t.set_color("font_hover_color", "MenuItem", Color.WHITE)
	t.set_color("font_focus_color", "MenuItem", Color.WHITE)
	t.set_color("font_disabled_color", "MenuItem", Color(Palette.MUTED, 0.35))
	var plain := slant(Color(0, 0, 0, 0), 26, 2)
	var hover := slant(Palette.ACCENT, 26, 2)
	t.set_stylebox("normal", "MenuItem", plain)
	t.set_stylebox("disabled", "MenuItem", plain)
	t.set_stylebox("hover", "MenuItem", hover)
	t.set_stylebox("pressed", "MenuItem", slant(Palette.ACCENT_DEEP, 26, 2))
	t.set_stylebox("focus", "MenuItem", hover)

	# Check boxes: no button frame.
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 2
	empty.content_margin_top = 3
	empty.content_margin_bottom = 3
	for s: String in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(s, "CheckBox", empty)
	t.set_font("font", "CheckBox", body_font())
	t.set_font_size("font_size", "CheckBox", 14)
	t.set_color("font_color", "CheckBox", Palette.FG)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", Palette.FG)
	t.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)

	# Panels: flat surfaces, no frame (the app's cards).
	t.set_stylebox("panel", "PanelContainer", box(Palette.PANEL, 0, Color(0, 0, 0, 0), 18, 16))
	t.set_stylebox("panel", "Panel", box(Palette.PANEL, 0))

	var field := box(Palette.PANEL_SOLID, 0, Palette.LINE, 10, 6)
	var field_focus := box(Palette.PANEL_SOLID, 0, Palette.GOLD, 10, 6)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", Palette.FG)
	t.set_color("font_placeholder_color", "LineEdit", Palette.DIM)
	t.set_font("font", "LineEdit", display_font())
	t.set_font_size("font_size", "LineEdit", 17)

	t.set_stylebox("panel", "PopupMenu", box(Palette.PANEL_SOLID, 0, Palette.LINE, 4, 4))
	t.set_stylebox("hover", "PopupMenu", box(Palette.ACCENT, 0))
	t.set_color("font_color", "PopupMenu", Palette.FG)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font("font", "PopupMenu", display_font())
	t.set_font_size("font_size", "PopupMenu", 17)

	t.set_stylebox("panel", "ItemList", box(Palette.PANEL_SOLID, 0, Color(0, 0, 0, 0), 6, 6))
	t.set_stylebox("selected", "ItemList", box(Palette.ACCENT, 0))
	t.set_stylebox("selected_focus", "ItemList", box(Palette.ACCENT, 0))
	t.set_stylebox("hovered", "ItemList", box(Palette.BUTTON_HOVER, 0))
	t.set_font("font", "ItemList", display_italic())
	t.set_font_size("font_size", "ItemList", 18)
	t.set_color("font_color", "ItemList", Palette.FG)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)

	var sep := StyleBoxLine.new()
	sep.color = Palette.LINE
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 14)

	var grab := box(Palette.GOLD, 0)
	t.set_stylebox("slider", "HSlider", box(Palette.LINE, 0, Color(0, 0, 0, 0), 0, 3))
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", grab)

	t.set_stylebox("panel", "TooltipPanel", box(Palette.PANEL_SOLID, 0, Palette.LINE, 10, 6))
	t.set_color("font_color", "TooltipLabel", Palette.FG)
	return t
