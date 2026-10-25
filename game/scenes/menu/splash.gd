class_name Splash
extends Control
## The first screen when the game starts (mockup Cine6): hero strips along the top and the
## bottom, the logo big, PRESS ANY KEY blinking under it and a ticker of what is new above the
## bottom strip. Any key, click or pad button fades it out over the main menu; once per run.

## Shown already in this run (going back to the menu skips it).
static var done: bool = false

const BLINK: float = 2.8
const TICKER_H: float = 42.0
const TICKER_SPEED: float = 40.0
const TICKER_GAP: float = 64.0

var _prompt: Label
var _logo: Control
var _t: float = 0.0
var _leaving: bool = false
## Ticker: [tag, text, colour] items, how far it has run, one round's width.
var _items: Array = []
var _run: float = 0.0
var _round: float = 0.0
var _ticker: Control


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(db: CardDb, logo: Texture2D, news: Array, version: String) -> void:
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	HeroStrip.letterbox(self, db)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_top = 125
	col.offset_bottom = -125 - TICKER_H
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	if logo != null:
		var img := TextureRect.new()
		img.texture = logo
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.custom_minimum_size = Vector2(0, 470)
		_logo = img
	else:
		var title: Label = UiTheme.label("EVIL BOĆE", 120)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_logo = title
	col.add_child(_logo)
	_prompt = UiTheme.label("PRESS ANY KEY", 34)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_prompt)
	var v := Label.new()
	v.text = version
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_theme_color_override("font_color", Palette.DIM)
	v.add_theme_font_size_override("font_size", 13)
	col.add_child(v)

	_items = news
	if not _items.is_empty():
		_ticker = Control.new()
		_ticker.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_ticker.offset_top = -113.0 - TICKER_H
		_ticker.offset_bottom = -113.0
		_ticker.clip_contents = true
		_ticker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ticker.draw.connect(_draw_ticker)
		add_child(_ticker)
		for it: Array in _items:
			_round += _item_width(it) + TICKER_GAP

	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.4)


func _process(delta: float) -> void:
	_t += delta
	if _prompt != null and not _leaving:
		_prompt.modulate.a = 0.55 + 0.45 * cos(TAU * _t / BLINK)
	if _ticker != null and _round > 0.0:
		_run = fposmod(_run + TICKER_SPEED * delta, _round)
		_ticker.queue_redraw()


func _input(event: InputEvent) -> void:
	if _leaving:
		return
	var go: bool = false
	if event is InputEventKey:
		go = (event as InputEventKey).pressed and not (event as InputEventKey).echo
	elif event is InputEventMouseButton:
		go = (event as InputEventMouseButton).pressed
	elif event is InputEventJoypadButton:
		go = (event as InputEventJoypadButton).pressed
	if go:
		get_viewport().set_input_as_handled()
		leave()


## Fades out over the menu and goes.
func leave() -> void:
	if _leaving:
		return
	_leaving = true
	done = true
	var t: Tween = create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.35)
	t.tween_callback(queue_free)


func _item_width(it: Array) -> float:
	return UiTheme.display_heavy().get_string_size(str(it[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 12.0 \
		+ UiTheme.body_font().get_string_size(str(it[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x


## A band like a sports broadcast's: "WHAT'S NEW" in red on the left, the items running under it.
func _draw_ticker() -> void:
	var w: float = _ticker.size.x
	var h: float = _ticker.size.y
	_ticker.draw_rect(Rect2(0, 0, w, h), Palette.PANEL_SOLID)
	_ticker.draw_rect(Rect2(0, 0, w, 1), Palette.LINE)
	var heavy: Font = UiTheme.display_heavy()
	var body: Font = UiTheme.body_font()
	var base: float = h * 0.5 + 7.0
	var x: float = 190.0 - _run
	while x < w:
		for it: Array in _items:
			var tag_w: float = heavy.get_string_size(str(it[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			var color: Color = it[2]
			_ticker.draw_string(heavy, Vector2(x, base), str(it[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, color)
			_ticker.draw_string(body, Vector2(x + tag_w + 12.0, base - 1.0), str(it[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("d8d3cb"))
			x += _item_width(it) + TICKER_GAP
	var tag := PackedVector2Array([Vector2(0, 0), Vector2(176, 0), Vector2(162, h), Vector2(0, h)])
	_ticker.draw_colored_polygon(tag, Palette.ACCENT)
	_ticker.draw_string(heavy, Vector2(20, base), "WHAT'S NEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Palette.FG)
