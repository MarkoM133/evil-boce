class_name Splash
extends Control
## The first screen when the game starts (mockup Cine6): hero strips along the top and the
## bottom, the logo big, PRESS ANY KEY blinking under it and a ticker of what is new above the
## bottom strip; once per run. Any key, click or pad button leaves for the menu underneath: the
## prompt flashes, the ticker drops, the strips part, a slanted red cut runs across and uncovers
## the menu, and the logo glides onto the menu's own logo. Another press ends it at once.

## The red cut has started across (the menu can come in behind it).
signal wipe_started
## Over: the splash is gone and the menu's logo should show.
signal finished

## Shown already in this run (going back to the menu skips it).
static var done: bool = false

const BLINK: float = 2.8
const TICKER_H: float = 42.0
const TICKER_SPEED: float = 40.0
const TICKER_GAP: float = 64.0
## The leaving: when each part starts and how long it takes (seconds from the press).
const STRIPS_AT: float = 0.1
const STRIPS_TIME: float = 0.3
const WIPE_AT: float = 0.3
const WIPE_TIME: float = 0.35
const LOGO_AT: float = 0.25
const LOGO_TIME: float = 0.5
## The cut: its band's width and how far its top leans right of its bottom.
const BAND: float = 140.0
const LEAN: float = 160.0

var _prompt: Label
var _version: Label
var _logo: Control
var _strips: Array[Control] = []
var _bg: Control
## Where the cut's bottom edge is; far left of the screen before it starts (all black).
var _wipe: float = -1e9
var _t: float = 0.0
var _leaving: bool = false
var _tween: Tween
var _flyer: TextureRect
## The menu's logo the splash's logo lands on.
var _target: Control
## The way out was cut short by a second press.
var skipped: bool = false
## Ticker: [tag, text, colour] items, how far it has run, one round's width.
var _items: Array = []
var _run: float = 0.0
var _round: float = 0.0
var _ticker: Control


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


## `target`: the menu's logo, hidden until the splash's lands on it.
func setup(db: CardDb, logo: Texture2D, news: Array, version: String, target: Control = null) -> void:
	_target = target
	_bg = Control.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.draw.connect(_draw_bg)
	add_child(_bg)
	_strips = HeroStrip.letterbox(self, db)

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
	_version = Label.new()
	_version.text = version
	_version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_version.add_theme_color_override("font_color", Palette.DIM)
	_version.add_theme_font_size_override("font_size", 13)
	col.add_child(_version)

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

	# The black stays solid from the first frame (the menu behind must not show); only what is on
	# it fades in.
	var t: Tween = create_tween().set_parallel()
	for c: Node in get_children():
		if c != _bg and c is CanvasItem:
			var ci := c as CanvasItem
			ci.modulate.a = 0.0
			t.tween_property(ci, "modulate:a", 1.0, 0.4)


func _process(delta: float) -> void:
	_t += delta
	if _prompt != null and not _leaving:
		_prompt.modulate.a = 0.55 + 0.45 * cos(TAU * _t / BLINK)
	if _ticker != null and _round > 0.0:
		_run = fposmod(_run + TICKER_SPEED * delta, _round)
		_ticker.queue_redraw()


func _input(event: InputEvent) -> void:
	var go: bool = false
	if event is InputEventKey:
		go = (event as InputEventKey).pressed and not (event as InputEventKey).echo
	elif event is InputEventMouseButton:
		go = (event as InputEventMouseButton).pressed
	elif event is InputEventJoypadButton:
		go = (event as InputEventJoypadButton).pressed
	if not go:
		return
	get_viewport().set_input_as_handled()
	if _leaving:
		skip()
	else:
		leave()


## Plays the way out (see the class comment).
func leave() -> void:
	if _leaving:
		return
	_leaving = true
	done = true
	var h: float = size.y
	_tween = create_tween().set_parallel()
	# The prompt flashes gold as the answer to the press, then goes.
	_prompt.modulate.a = 1.0
	_prompt.add_theme_color_override("font_color", Palette.GOLD)
	_tween.tween_property(_prompt, "modulate:a", 0.0, 0.15).set_delay(0.12)
	_tween.tween_property(_version, "modulate:a", 0.0, 0.15)
	if _ticker != null:
		_tween.tween_property(_ticker, "position:y", _ticker.position.y + 70.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_tween.tween_property(_ticker, "modulate:a", 0.0, 0.18)
	# The strips part: the top pair up, the bottom pair down.
	for i: int in _strips.size():
		var s: Control = _strips[i]
		var away: float = -(s.position.y + s.size.y) - 4.0 if i < 2 else h - s.position.y + 4.0
		_tween.tween_property(s, "position:y", s.position.y + away, STRIPS_TIME).set_delay(STRIPS_AT) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# The cut runs across and uncovers what is behind.
	_tween.tween_callback(func() -> void: wipe_started.emit()).set_delay(WIPE_AT)
	_tween.tween_method(_set_wipe, -LEAN, size.x + BAND, WIPE_TIME).set_delay(WIPE_AT) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	# The logo glides onto the menu's.
	var tex: Texture2D = (_logo as TextureRect).texture if _logo is TextureRect else null
	if tex != null and _target != null:
		var from: Rect2 = _fit(tex.get_size(), _logo.get_global_rect())
		var to: Rect2 = _fit(tex.get_size(), _target.get_global_rect())
		_flyer = TextureRect.new()
		_flyer.texture = tex
		_flyer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_flyer.stretch_mode = TextureRect.STRETCH_SCALE
		_flyer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_flyer)
		_flyer.position = from.position - global_position
		_flyer.size = from.size
		_logo.modulate.a = 0.0
		_tween.tween_property(_flyer, "position", to.position - global_position, LOGO_TIME).set_delay(LOGO_AT) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_property(_flyer, "size", to.size, LOGO_TIME).set_delay(LOGO_AT) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	else:
		_tween.tween_property(_logo, "modulate:a", 0.0, 0.3).set_delay(LOGO_AT)
	_tween.chain().tween_callback(_finish)


## Ends the way out now.
func skip() -> void:
	skipped = true
	if _tween != null and _tween.is_valid():
		_tween.custom_step(10.0)


func _finish() -> void:
	finished.emit()
	queue_free()


func _set_wipe(x: float) -> void:
	_wipe = x
	_bg.queue_redraw()


## Black, or once the cut has started only right of it, with the red band on its edge.
func _draw_bg() -> void:
	var w: float = _bg.size.x
	var h: float = _bg.size.y
	if _wipe < -LEAN:
		_bg.draw_rect(Rect2(0, 0, w, h), Palette.BG)
		return
	var x: float = _wipe
	if x + LEAN < w:
		_bg.draw_colored_polygon(PackedVector2Array([Vector2(x + LEAN, 0), Vector2(w, 0), Vector2(w, h), Vector2(x, h)]), Palette.BG)
	_bg.draw_colored_polygon(PackedVector2Array([Vector2(x + LEAN - BAND, 0), Vector2(x + LEAN, 0), Vector2(x, h),
		Vector2(x - BAND, h)]), Palette.ACCENT)
	_bg.draw_colored_polygon(PackedVector2Array([Vector2(x + LEAN - BAND - 26.0, 0), Vector2(x + LEAN - BAND, 0),
		Vector2(x - BAND, h), Vector2(x - BAND - 26.0, h)]), Palette.ACCENT_DEEP)


## Where a picture of `tex_size` lands when fitted (aspect kept, centred) into `rect`.
static func _fit(tex_size: Vector2, rect: Rect2) -> Rect2:
	var k: float = minf(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
	var s: Vector2 = tex_size * k
	return Rect2(rect.position + (rect.size - s) * 0.5, s)


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
