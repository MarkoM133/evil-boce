extends Control
## Main menu (GDD 7), "featured hero" layout (mockup M5): one hero's card art fills the right
## side behind a slanted cut and changes every few seconds; the logo sits small top left and
## the entries run down the left in big italics. Every entry works: Continue (an unfinished
## match), Play, Online, Sandbox, Replays, Decks, Settings and Exit.

const SANDBOX_SCENE: String = "res://scenes/sandbox/sandbox.tscn"
const SETUP_SCENE: String = "res://scenes/match/match_setup.tscn"
const LOBBY_SCENE: String = "res://scenes/net/lobby.tscn"
const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const REPLAYS_SCENE: String = "res://scenes/replays/replays_menu.tscn"
const SETTINGS_SCENE: String = "res://scenes/menu/settings_menu.tscn"
const DECKS_SCENE: String = "res://scenes/decks/decks_menu.tscn"
## Seconds a hero stays before the next one fades in.
const HERO_TIME: float = 6.0
const PANEL_W: float = 900.0

## [label, action, what it is]
const ENTRIES: Array = [
	["PLAY", "play", "Against the bot, or two players on this computer"],
	["ONLINE", "online", "Host a match or join one over Tailscale"],
	["SANDBOX", "sandbox", "Throw balls around, try terrain"],
	["REPLAYS", "replays", "Watch past matches, continue from any phase"],
	["DECKS", "decks", "Your decks, deck codes"],
	["SETTINGS", "settings", "Shared folder, display, sound, keys"],
	["EXIT", "exit", "See you"],
]

var db: CardDb
var _heroes: Array[HeroDef] = []
var _shown: int = -1
var _timer: float = 0.0
## Two panels so one can fade over the other.
var _panels: Array[ArtPanel] = []
var _front: int = 0
var _hero_name: Label
var _hero_info: Label
var _dots: HBoxContainer
var _hint: Label


func _ready() -> void:
	theme = UiTheme.get_theme()
	GameSettings.apply(get_tree())
	db = CardDb.load_from(GameSettings.data_path())
	var logo: Texture2D = db.logo()
	if logo != null:
		DisplayServer.set_icon(logo.get_image())
	if db.is_ok():
		_heroes = db.heroes.duplicate()
		_heroes.shuffle()

	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# The featured hero, right side.
	for i: int in 2:
		var p := ArtPanel.new()
		p.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
		p.offset_left = -PANEL_W
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.modulate.a = 0.0
		add_child(p)
		_panels.append(p)
	var info := VBoxContainer.new()
	info.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	info.position = Vector2(-70, -56)
	info.alignment = BoxContainer.ALIGNMENT_END
	info.add_theme_constant_override("separation", 6)
	add_child(info)
	_hero_info = UiTheme.label("", 16, Palette.GOLD, false)
	_hero_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hero_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_hero_info.add_theme_constant_override("outline_size", 6)
	info.add_child(_hero_info)
	_hero_name = UiTheme.label("", 96)
	_hero_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hero_name.add_theme_color_override("font_outline_color", Color.BLACK)
	_hero_name.add_theme_constant_override("outline_size", 10)
	info.add_child(_hero_name)
	_dots = HBoxContainer.new()
	_dots.alignment = BoxContainer.ALIGNMENT_END
	_dots.add_theme_constant_override("separation", 5)
	info.add_child(_dots)

	# Logo, small, top left.
	if logo != null:
		var img := TextureRect.new()
		img.texture = logo
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.position = Vector2(56, 30)
		img.size = Vector2(170, 150)
		add_child(img)
	else:
		var title: Label = UiTheme.label("EVIL BOĆE", 48)
		title.position = Vector2(60, 50)
		add_child(title)

	# The entries.
	var col := VBoxContainer.new()
	col.position = Vector2(86, 214)
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	var entries: Array = ENTRIES.duplicate()
	# A match left unfinished (quit or crash) comes back first.
	if ReplayStore.has_current():
		entries.push_front(["CONTINUE", "continue", "Back to the match you left"])
	var first: Button = null
	for i: int in entries.size():
		var entry: Array = entries[i]
		var b := Button.new()
		b.text = str(entry[0])
		b.theme_type_variation = &"MenuItem"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 50)
		b.custom_minimum_size = Vector2(300, 0)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var action: String = str(entry[1])
		if action == "continue":
			b.add_theme_color_override("font_color", Palette.GOLD)
		var hint: String = str(entry[2])
		b.pressed.connect(_on_pressed.bind(action))
		b.mouse_entered.connect(func() -> void: b.grab_focus())
		b.focus_entered.connect(func() -> void: _hint.text = hint)
		col.add_child(b)
		if first == null:
			first = b
		# Entries slide in from the left, one after another.
		b.modulate.a = 0.0
		var t: Tween = b.create_tween()
		t.tween_property(b, "modulate:a", 1.0, 0.22).set_delay(0.05 * i + 0.1)
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", Palette.MUTED)
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.custom_minimum_size = Vector2(0, 40)
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	col.add_child(_hint)
	if first != null:
		first.grab_focus.call_deferred()

	var foot := Label.new()
	foot.add_theme_color_override("font_color", Palette.DIM)
	foot.add_theme_font_size_override("font_size", 13)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	foot.position = Vector2(18, -34)
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	if db.is_ok():
		foot.text = "v%s  ·  cards v%d, %d cards" % [version, db.version, db.card_count]
	else:
		foot.text = "v%s  ·  %s  ·  set the shared folder in Settings" % [version, db.error]
		foot.add_theme_color_override("font_color", Palette.GOLD)
	add_child(foot)
	_show_hero(0)


func _process(delta: float) -> void:
	if _heroes.size() < 2:
		return
	_timer += delta
	if _timer >= HERO_TIME:
		_show_hero((_shown + 1) % _heroes.size())


## Fades hero `i` in over the one shown now.
func _show_hero(i: int) -> void:
	_timer = 0.0
	if _heroes.is_empty() or i == _shown:
		return
	_shown = i
	var h: HeroDef = _heroes[i]
	var back: ArtPanel = _panels[1 - _front]
	back.art = db.large(h.id)
	if back.art == null:
		back.art = db.thumb(h.id)
	back.region = _art_region(back.art)
	back.fallback = Palette.hero(h.color_name).darkened(0.4)
	back.queue_redraw()
	move_child(back, _panels[_front].get_index() + 1)
	var t: Tween = create_tween().set_parallel(true)
	t.tween_property(back, "modulate:a", 1.0, 0.6)
	t.tween_property(back, "position:x", back.position.x, 0.6).from(back.position.x + 40.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(_panels[_front], "modulate:a", 0.0, 0.6)
	_front = 1 - _front
	_hero_name.text = h.name.to_upper()
	_hero_info.text = "%s  ·  WT %d  ·  RANGE %d  ·  HP %d" % [h.color_name.to_upper(), h.wt, h.rng, h.hp]
	_hero_info.add_theme_color_override("font_color", Palette.hero(h.color_name).lightened(0.2))
	_hero_name.modulate.a = 0.0
	_hero_name.create_tween().tween_property(_hero_name, "modulate:a", 1.0, 0.35).set_delay(0.15)
	_refresh_dots()


## Hero cards are landscape with the art on the left half; take a tall piece of it.
func _art_region(tex: Texture2D) -> Rect2:
	if tex == null:
		return Rect2(0, 0, 1, 1)
	if tex.get_width() > tex.get_height():
		return Rect2(0.025, 0.07, 0.405, 0.72)
	return Rect2(0.06, 0.06, 0.88, 0.5)


func _refresh_dots() -> void:
	for c: Node in _dots.get_children():
		c.queue_free()
	for i: int in _heroes.size():
		var d: UiShape = UiShape.make(UiShape.Kind.SLANT, Palette.GOLD if i == _shown else Color(1, 1, 1, 0.25), Vector2(24, 7))
		d.cut = 3.0
		d.mouse_filter = Control.MOUSE_FILTER_STOP
		d.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		d.tooltip_text = _heroes[i].name
		d.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
				_show_hero(i))
		_dots.add_child(d)


func _on_pressed(action: String) -> void:
	match action:
		"continue":
			var record: MatchRecord = ReplayStore.load_current()
			if record == null or record.frame_count() == 0:
				ReplayStore.clear_current()
				get_tree().reload_current_scene()
				return
			MatchLaunch.config = MatchLaunch.from_record(record)
			get_tree().change_scene_to_file(MATCH_SCENE)
		"play":
			get_tree().change_scene_to_file(SETUP_SCENE)
		"online":
			get_tree().change_scene_to_file(LOBBY_SCENE)
		"replays":
			get_tree().change_scene_to_file(REPLAYS_SCENE)
		"sandbox":
			get_tree().change_scene_to_file(SANDBOX_SCENE)
		"settings":
			get_tree().change_scene_to_file(SETTINGS_SCENE)
		"decks":
			get_tree().change_scene_to_file(DECKS_SCENE)
		"exit":
			get_tree().quit()
