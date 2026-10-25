class_name UiTheme
extends RefCounted
## The game's UI theme, built in code (GDD 11: modern and quiet, dark flat panels, Barlow
## Condensed for numbers and titles, Barlow for text).
## Variations: "MenuItem" (main menu), "Header" (section titles), "Big" (large numbers),
## "Muted" (secondary text), "Toggle" (pressed = accent).

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func display_font() -> Font:
	return load("res://ui/fonts/BarlowCondensed-SemiBold.ttf") as Font


static func display_bold() -> Font:
	return load("res://ui/fonts/BarlowCondensed-Bold.ttf") as Font


static func body_font() -> Font:
	return load("res://ui/fonts/Barlow-Regular.ttf") as Font


static func box(bg: Color, radius: int = 3, border: Color = Color(0, 0, 0, 0), pad_x: float = 12,
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


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 15

	t.set_color("font_color", "Label", Palette.FG)

	var header := FontVariation.new()
	header.base_font = display_bold()
	header.spacing_glyph = 1
	t.set_type_variation("Header", "Label")
	t.set_font("font", "Header", header)
	t.set_font_size("font_size", "Header", 13)
	t.set_color("font_color", "Header", Palette.MUTED)

	t.set_type_variation("Big", "Label")
	t.set_font("font", "Big", display_bold())
	t.set_font_size("font_size", "Big", 30)

	t.set_type_variation("Muted", "Label")
	t.set_color("font_color", "Muted", Palette.MUTED)
	t.set_font_size("font_size", "Muted", 13)

	# Buttons
	t.set_font("font", "Button", display_font())
	t.set_font_size("font_size", "Button", 17)
	t.set_color("font_color", "Button", Palette.FG)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Palette.FG)
	t.set_color("font_disabled_color", "Button", Color(Palette.MUTED, 0.45))
	t.set_stylebox("normal", "Button", box(Palette.BUTTON))
	t.set_stylebox("hover", "Button", box(Palette.BUTTON_HOVER))
	t.set_stylebox("pressed", "Button", box(Palette.ACCENT))
	t.set_stylebox("hover_pressed", "Button", box(Palette.ACCENT.lightened(0.1)))
	t.set_stylebox("disabled", "Button", box(Color("201b17")))
	var focus := box(Color(0, 0, 0, 0), 3, Palette.GOLD)
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)

	t.set_type_variation("Toggle", "Button")

	# Main menu entries: big, flat, gold bar on hover.
	t.set_type_variation("MenuItem", "Button")
	t.set_font("font", "MenuItem", display_bold())
	t.set_font_size("font_size", "MenuItem", 34)
	t.set_color("font_color", "MenuItem", Palette.FG)
	t.set_color("font_hover_color", "MenuItem", Palette.GOLD)
	t.set_color("font_focus_color", "MenuItem", Palette.GOLD)
	t.set_color("font_disabled_color", "MenuItem", Color(Palette.MUTED, 0.35))
	var plain := box(Color(0, 0, 0, 0), 2, Color(0, 0, 0, 0), 22, 4)
	var hover := box(Color(1, 1, 1, 0.05), 2, Color(0, 0, 0, 0), 22, 4)
	hover.border_color = Palette.GOLD
	hover.border_width_left = 3
	t.set_stylebox("normal", "MenuItem", plain)
	t.set_stylebox("disabled", "MenuItem", plain)
	t.set_stylebox("hover", "MenuItem", hover)
	t.set_stylebox("pressed", "MenuItem", hover)
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

	t.set_stylebox("panel", "PanelContainer", box(Palette.PANEL, 4, Palette.LINE, 14, 12))
	t.set_stylebox("panel", "Panel", box(Palette.PANEL, 4, Palette.LINE))

	t.set_stylebox("normal", "LineEdit", box(Color("241e19"), 3, Palette.LINE, 8, 4))
	t.set_stylebox("focus", "LineEdit", box(Color("241e19"), 3, Palette.GOLD, 8, 4))
	t.set_color("font_color", "LineEdit", Palette.FG)
	t.set_font("font", "LineEdit", display_font())
	t.set_font_size("font_size", "LineEdit", 17)

	t.set_stylebox("panel", "PopupMenu", box(Palette.PANEL_SOLID, 3, Palette.LINE, 4, 4))
	t.set_stylebox("hover", "PopupMenu", box(Palette.BUTTON_HOVER, 2))
	t.set_color("font_color", "PopupMenu", Palette.FG)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	var sep := StyleBoxLine.new()
	sep.color = Palette.LINE
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 14)

	t.set_stylebox("panel", "TooltipPanel", box(Palette.PANEL_SOLID, 3, Palette.LINE, 8, 4))
	t.set_color("font_color", "TooltipLabel", Palette.FG)
	return t
