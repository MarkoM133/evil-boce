class_name MenuScreen
extends RefCounted
## The frame every menu screen shares (the web app's layout): black, the hero strip on top,
## a title with a red slash and a Back button under it, then the screen's own content, which
## scrolls when it is taller than the window.

## {"content": VBoxContainer, "strip": HeroStrip, "title_row": HBoxContainer, "back": Button}
static func build(root: Control, db: CardDb, title: String, subtitle: String = "", back: Callable = Callable(),
		content_width: float = 1180.0) -> Dictionary:
	root.theme = UiTheme.get_theme()
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	root.add_child(col)
	var strip := HeroStrip.new()
	strip.setup(db)
	strip.custom_minimum_size = Vector2(0, 84)
	col.add_child(strip)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 28)
	center.add_child(margin)
	var body := VBoxContainer.new()
	body.custom_minimum_size = Vector2(content_width, 0)
	body.add_theme_constant_override("separation", 16)
	margin.add_child(body)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 14)
	body.add_child(title_row)
	var slash: UiShape = UiShape.make(UiShape.Kind.SLANT, Palette.ACCENT, Vector2(14, 44))
	slash.cut = 8.0
	slash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(slash)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(titles)
	titles.add_child(UiTheme.label(title.to_upper(), 44))
	if not subtitle.is_empty():
		var sub := Label.new()
		sub.text = subtitle
		sub.add_theme_color_override("font_color", Palette.MUTED)
		sub.add_theme_font_size_override("font_size", 14)
		titles.add_child(sub)
	var back_btn: Button = null
	if back.is_valid():
		back_btn = Button.new()
		back_btn.text = "‹  BACK"
		back_btn.add_theme_font_size_override("font_size", 20)
		back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		back_btn.pressed.connect(back)
		title_row.add_child(back_btn)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	body.add_child(content)
	# Content fades in, the way the app's views come in.
	content.modulate.a = 0.0
	var t: Tween = content.create_tween().set_parallel(true)
	t.tween_property(content, "modulate:a", 1.0, 0.22)
	return {"content": content, "strip": strip, "title_row": title_row, "back": back_btn}


## A section heading inside a screen: small straw italic caps.
static func heading(parent: Control, text: String) -> Label:
	var l: Label = UiTheme.label(text.to_upper(), 16, Palette.GOLD)
	parent.add_child(l)
	return l


## A flat dark card (the app's surface) holding a VBox; returns the VBox.
static func card(parent: Control, pad: int = 18) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(Palette.PANEL_SOLID, 0, Color(0, 0, 0, 0), pad, pad))
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	return v
