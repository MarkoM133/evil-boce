extends Control
## Main menu (GDD 7) in one of two layouts (Settings → Main menu). "Side strip" (mockup M3): the
## hero strip down the left, the entries beside it in big italics, the logo big on the right;
## left alone for a while, the logo gives way to the last match. "Cinema" (mockup M8): strips
## along the top and the bottom, the logo in the middle. Every entry works: Continue (an
## unfinished match), Play, Online, Sandbox, Replays, Decks, Settings and Exit. When the game
## starts, the splash (logo, press any key, what is new) comes first.

const SANDBOX_SCENE: String = "res://scenes/sandbox/sandbox.tscn"
const SETUP_SCENE: String = "res://scenes/match/match_setup.tscn"
const LOBBY_SCENE: String = "res://scenes/net/lobby.tscn"
const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const REPLAYS_SCENE: String = "res://scenes/replays/replays_menu.tscn"
const SETTINGS_SCENE: String = "res://scenes/menu/settings_menu.tscn"
const DECKS_SCENE: String = "res://scenes/decks/decks_menu.tscn"

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
var _hint: Label
## The menu comes in after building it (at once, or behind the splash's cut): what fades in
## (and after how long), what slides in from the left, the logo, and the tweens doing it.
var _fade_ins: Array[Control] = []
var _fade_delays: Array[float] = []
var _slide_ins: Array[Control] = []
var _logo_node: Control
var _intro: Array[Tween] = []


func _ready() -> void:
	theme = UiTheme.get_theme()
	GameSettings.apply(get_tree())
	db = CardDb.load_from(GameSettings.data_path())
	var logo: Texture2D = db.logo()
	if logo != null:
		DisplayServer.set_icon(logo.get_image())

	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var layout: String = GameSettings.menu_layout()
	if layout == "cinema":
		_build_cinema(logo, GameSettings.cinema_fill())
	else:
		_build_strip(logo)

	var foot := Label.new()
	foot.add_theme_color_override("font_color", Palette.DIM)
	foot.add_theme_font_size_override("font_size", 13)
	# Above the bottom strip in the cinema layout; bottom right beside the side strip.
	if layout == "cinema":
		foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
		foot.position = Vector2(18, -150)
	else:
		foot.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		foot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
		foot.offset_left = -20
		foot.offset_right = -20
		foot.offset_top = -16
		foot.offset_bottom = -16
	foot.text = _version_line()
	if not db.is_ok():
		foot.add_theme_color_override("font_color", Palette.GOLD)
	add_child(foot)

	for f: Control in _fade_ins:
		f.modulate.a = 0.0
	if _logo_node != null:
		_logo_node.modulate.a = 0.0
	if Splash.done:
		_play_intro(true)
		return
	var splash := Splash.new()
	splash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(splash)
	splash.setup(db, logo, _news_items(), _version_line(), _logo_node)
	splash.wipe_started.connect(_play_intro.bind(false))
	splash.finished.connect(func() -> void:
		if _logo_node != null:
			_logo_node.modulate.a = 1.0
		if splash.skipped:
			for t: Tween in _intro:
				if t.is_valid():
					t.custom_step(10.0))


func _fade_in(c: Control, delay: float) -> void:
	_fade_ins.append(c)
	_fade_delays.append(delay)


## Fades and slides the menu in; `with_logo` fades the logo too (no splash logo lands on it).
func _play_intro(with_logo: bool) -> void:
	for i: int in _fade_ins.size():
		var c: Control = _fade_ins[i]
		var t: Tween = c.create_tween()
		t.tween_property(c, "modulate:a", 1.0, 0.22).set_delay(_fade_delays[i])
		_intro.append(t)
	for c: Control in _slide_ins:
		var x: float = c.position.x
		c.position.x = x - 320.0
		var t: Tween = c.create_tween()
		t.tween_property(c, "position:x", x, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_intro.append(t)
	if with_logo and _logo_node != null:
		var t: Tween = _logo_node.create_tween()
		t.tween_property(_logo_node, "modulate:a", 1.0, 0.4)
		_intro.append(t)


func _version_line() -> String:
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	if db.is_ok():
		return "v%s  ·  cards v%d, %d cards" % [version, db.version, db.card_count]
	return "v%s  ·  %s  ·  set the shared folder in Settings" % [version, db.error]


## What the splash's ticker says: what changed in the latest cards, the last match, replays.
## [tag, text, colour]
func _news_items() -> Array:
	var out: Array = []
	var entries: Array[Dictionary] = _changelog()
	if not entries.is_empty():
		var last: Dictionary = entries[0]
		var parts := PackedStringArray()
		for c: Variant in JsonUtil.as_array(last.get("cards", [])):
			var cd: Dictionary = JsonUtil.as_dict(c)
			parts.append("%s (%s)" % [str(cd.get("name", "")), _change_text(cd)])
		out.append(["CARDS v%d" % JsonUtil.as_int(last.get("version", 0)), ", ".join(parts.slice(0, 6))
			+ (" and %d more" % (parts.size() - 6) if parts.size() > 6 else ""), Palette.GOLD])
	var caption: String = ReplayStore.last_caption()
	if caption != "":
		out.append(["LAST MATCH", caption.trim_prefix("Last match: "), Palette.team(0)])
	if ReplayStore.has_current():
		out.append(["CONTINUE", "A match is waiting where you left it", Palette.GOLD])
	var replays: int = ReplayStore.list_replays().size()
	if replays > 0:
		out.append(["REPLAYS", "%d saved, watch them from Replays" % replays, Palette.hero("Purple")])
	if db.is_ok():
		out.append(["CARDS", "%d cards, %d heroes" % [db.card_count, db.heroes.size()], Palette.hero("Cyan")])
	return out


# --- cinema (mockup M8) ---------------------------------------------------------------------

## Letterbox: hero strips along the top and the bottom drifting opposite ways, the logo big in
## the middle, the entries in one row under it and a line about the one in focus. `fill`
## (Settings): "empty" for the logo alone, "info" for two cards beside it (M8 + 5), "table" for
## the match table behind it all (M8 + 3).
func _build_cinema(logo: Texture2D, fill: String = "info") -> void:
	var table: bool = fill == "table"
	if table:
		var t := MenuTable.new()
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.offset_top = 113
		t.offset_bottom = -113
		add_child(t)
		t.setup(db)
		t.modulate.a = 0.0
		t.create_tween().tween_property(t, "modulate:a", 1.0, 0.6)
	HeroStrip.letterbox(self, db)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_top = 125
	col.offset_bottom = -125
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	add_child(col)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The logo between two cards (mockup M8 + 5): the last match on the left, what is new on
	# the right. Alone it is bigger; over the table, smaller.
	var stage := HBoxContainer.new()
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	stage.add_theme_constant_override("separation", 56)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stage)
	var cards: Array[Control] = []
	if fill == "info":
		cards.append_array([_last_match_card(), _whats_new_card()])
		stage.add_child(cards[0])
	if logo != null:
		var img := TextureRect.new()
		img.texture = logo
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img.custom_minimum_size = {"table": Vector2(340, 320), "empty": Vector2(480, 460)}.get(fill, Vector2(400, 380))
		stage.add_child(img)
		_logo_node = img
	else:
		var title: Label = UiTheme.label("EVIL BOĆE", 110)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stage.add_child(title)
		_logo_node = title
	if not cards.is_empty():
		stage.add_child(cards[1])
	for c: Control in cards:
		_fade_in(c, 0.35)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	col.add_child(row)
	_entry_buttons(row, 36, false, 0.25)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Palette.MUTED)
	_hint.add_theme_font_size_override("font_size", 15)
	col.add_child(_hint)


## The entries as big italic buttons (Continue first when a match waits), fading in one after
## another from `delay`; hovering or focusing one puts its line in `_hint`, which the caller
## makes. The first one gets the focus.
func _entry_buttons(parent: BoxContainer, font_size: int, left: bool, delay: float) -> void:
	var entries: Array = ENTRIES.duplicate()
	# A match left unfinished (quit or crash) comes back first.
	if ReplayStore.has_current():
		entries.push_front(["CONTINUE", "continue", "Back to the match you left"])
	for i: int in entries.size():
		var entry: Array = entries[i]
		var b := Button.new()
		b.text = str(entry[0])
		b.theme_type_variation = &"MenuItem"
		b.add_theme_font_size_override("font_size", font_size)
		if left:
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size = Vector2(300, 0)
			b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var action: String = str(entry[1])
		if action == "continue":
			b.add_theme_color_override("font_color", Palette.GOLD)
		var hint: String = str(entry[2])
		b.pressed.connect(_on_pressed.bind(action))
		b.mouse_entered.connect(func() -> void: b.grab_focus())
		b.focus_entered.connect(func() -> void: _hint.text = hint)
		parent.add_child(b)
		if i == 0:
			b.grab_focus.call_deferred()
		_fade_in(b, 0.05 * i + delay)


# --- side strip (mockup M3) -----------------------------------------------------------------

## The hero strip runs down the left edge and drifts up; the entries stand beside it in big
## italics, the logo big on the right.
func _build_strip(logo: Texture2D) -> void:
	const STRIP_W: float = 280.0
	var strip := HeroStrip.new()
	strip.vertical = true
	strip.setup(db)
	strip.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	strip.custom_minimum_size = Vector2(STRIP_W, 0)
	strip.offset_right = STRIP_W
	add_child(strip)
	# The strip fades into the black on its right.
	var fade := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.gradient = Gradient.new()
	grad.gradient.set_color(0, Palette.BG)
	grad.gradient.set_color(1, Color(Palette.BG, 0.0))
	grad.width = 64
	grad.height = 4
	fade.texture = grad
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	fade.offset_left = STRIP_W
	fade.offset_right = STRIP_W + 120
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	col.offset_left = STRIP_W + 100
	col.offset_right = STRIP_W + 600
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	_entry_buttons(col, 54, true, 0.1)
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", Palette.MUTED)
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.custom_minimum_size = Vector2(0, 40)
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	col.add_child(_hint)
	_slide_ins.append_array([strip, fade, col])

	# The logo, big, right of the middle; left alone for a while, the last match shows in its
	# circle.
	var holder := CenterContainer.new()
	holder.anchor_left = 0.52
	holder.anchor_right = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_right = -60
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	if logo != null:
		var img := MenuLogo.new()
		img.logo = logo
		img.shot = ReplayStore.last_shot()
		img.caption = ReplayStore.last_caption().trim_prefix("Last match: ")
		img.custom_minimum_size = Vector2(580, 580)
		holder.add_child(img)
		_logo_node = img
	else:
		_logo_node = UiTheme.label("EVIL BOĆE", 120)
		holder.add_child(_logo_node)


const SIDE_CARD := Vector2(330, 380)
## Card fields as the web app's changelog names them, for the What's new card.
const FIELD_NAMES: Dictionary = {"wt": "weight", "stats": "stats", "text": "text", "cost": "cost",
	"bonus": "bonus", "values": "values", "traits": "traits", "terrain": "terrain", "fx": "effect",
	"evo": "evolution", "type": "type", "color": "colour", "image": "art"}


## A side card of the cinema menu: a slanted panel with a coloured edge and a header.
func _side_card(header: String, color: Color) -> VBoxContainer:
	var panel := PanelContainer.new()
	var sb: StyleBoxFlat = UiTheme.box(Palette.PANEL_SOLID, 0, Color(0, 0, 0, 0), 26, 18)
	sb.skew = Vector2(UiTheme.SKEW * 0.25, 0)
	sb.anti_aliasing = true
	sb.border_color = color
	sb.border_width_left = 4
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = SIDE_CARD
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	v.add_child(UiTheme.label(header, 16, color))
	return v


func _card_link(v: VBoxContainer, text: String, action: String) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UiTheme.display_heavy())
	b.add_theme_font_size_override("font_size", 18)
	for state: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(state, Palette.GOLD if state == "font_color" else Color("ffd36a"))
	for state: String in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(_on_pressed.bind(action))
	v.add_child(b)


## Left: the table at the end of the last match (its snapshot) and how it went. Without one,
## a stage's art and a way to play.
func _last_match_card() -> Control:
	var v: VBoxContainer = _side_card("LAST MATCH", Palette.team(0))
	var pic := TextureRect.new()
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.clip_contents = true
	pic.custom_minimum_size = Vector2(0, 160)
	v.add_child(pic)
	var shot: Texture2D = ReplayStore.last_shot()
	if shot == null:
		var stages: Array[CardDef] = db.catalog.of_type("Stage") if db.is_ok() else []
		var st: CardDef = stages.pick_random() if not stages.is_empty() else null
		var tex: Texture2D = null
		if st != null:
			tex = db.large(st.id) if db.large(st.id) != null else db.thumb(st.id)
		if tex != null:
			var at := AtlasTexture.new()
			at.atlas = tex
			var r: Rect2 = HeroSlice.card_art_region(tex, 2.0)
			at.region = Rect2(r.position * tex.get_size(), r.size * tex.get_size())
			pic.texture = at
		v.add_child(UiTheme.label("NO MATCH YET", 30))
		v.add_child(_muted("Pick decks, stages and cores" + ("  ·  %s" % st.name if st != null else ""), 13))
		_card_link(v, "PLAY  ›", "play")
		return v.get_parent() as Control
	pic.texture = shot
	# "Last match: A vs B  ·  turn 6  ·  A won" (match.gd _snapshot).
	var parts: PackedStringArray = ReplayStore.last_caption().trim_prefix("Last match: ").split("  ·  ")
	var result: String = parts[2] if parts.size() > 2 else "unfinished"
	v.add_child(UiTheme.label(result.to_upper(), 30, Palette.GOLD if result == "unfinished" else Palette.FG))
	v.add_child(_muted("  ·  ".join(parts.slice(0, 2)), 13))
	if result == "unfinished" and ReplayStore.has_current():
		_card_link(v, "CONTINUE  ›", "continue")
	else:
		_card_link(v, "WATCH REPLAY  ›", "replays")
	return v.get_parent() as Control


## Right: the cards in the latest Publish and what changed on each.
func _whats_new_card() -> Control:
	var entries: Array[Dictionary] = _changelog()
	var v: VBoxContainer = _side_card("WHAT'S NEW" if entries.is_empty()
		else "WHAT'S NEW  ·  CARDS v%d" % JsonUtil.as_int(entries[0].get("version", 0)), Palette.GOLD)
	if entries.is_empty():
		v.add_child(_muted("Nothing published yet. New and changed cards show up here after a Publish in the web app.", 13))
		return v.get_parent() as Control
	v.add_child(_muted(str(entries[0].get("date", "")).substr(0, 10), 12))
	# The latest Publish first, then older ones until the card is full; each card once.
	const ROWS: int = 7
	var rows: Array[Dictionary] = []
	var seen: Dictionary = {}
	var left_out: int = 0
	for e: Dictionary in entries:
		for c: Variant in JsonUtil.as_array(e.get("cards", [])):
			var cd: Dictionary = JsonUtil.as_dict(c)
			var id: String = str(cd.get("id", ""))
			if seen.has(id):
				continue
			seen[id] = true
			if rows.size() < ROWS:
				cd["version"] = e.get("version", 0)
				rows.append(cd)
			elif e == entries[0]:
				left_out += 1
		if rows.size() >= ROWS:
			break
	for cd: Dictionary in rows:
		var row := HBoxContainer.new()
		var name_l: Label = UiTheme.label(str(cd.get("name", "")), 19, Palette.FG, false)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(name_l)
		row.add_child(_muted("v%d  ·  %s" % [JsonUtil.as_int(cd.get("version", 0)), _change_text(cd)], 13, false))
		v.add_child(row)
		var line := ColorRect.new()
		line.color = Palette.LINE
		line.custom_minimum_size = Vector2(0, 1)
		v.add_child(line)
	if left_out > 0:
		v.add_child(_muted("and %d more" % left_out, 13))
	v.add_child(_muted("%d cards in all" % db.card_count, 12))
	return v.get_parent() as Control


## "new", "deleted", or the fields that changed ("weight, art").
static func _change_text(cd: Dictionary) -> String:
	var kind: String = str(cd.get("kind", "changed"))
	if kind != "changed":
		return kind
	var out := PackedStringArray()
	for f: Variant in JsonUtil.as_array(cd.get("fields", [])):
		if FIELD_NAMES.has(str(f)):
			out.append(str(FIELD_NAMES[str(f)]))
	if cd.get("image", false) == true:
		out.append("art")
	return ", ".join(out) if not out.is_empty() else "look"


func _muted(text: String, size: int, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Palette.MUTED)
	l.add_theme_font_size_override("font_size", size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## The newest entry of data/changelog.json, or {} without one.
func _last_changelog() -> Dictionary:
	var entries: Array[Dictionary] = _changelog()
	return entries[0] if not entries.is_empty() else {}


## The entries of data/changelog.json, newest version first.
func _changelog() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not db.is_ok():
		return out
	var path: String = db.data_dir().path_join("changelog.json")
	if not FileAccess.file_exists(path):
		return out
	for e: Variant in JsonUtil.as_array(JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(path))).get("entries", [])):
		out.append(JsonUtil.as_dict(e))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return JsonUtil.as_int(a.get("version", 0)) > JsonUtil.as_int(b.get("version", 0)))
	return out


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


func demo_table_open() -> void:
	for t: Node in find_children("*", "MenuTable", true, false):
		(t as MenuTable).pin_first()


func demo_skip_splash() -> void:
	for s: Node in find_children("*", "Splash", true, false):
		(s as Splash).leave()


func demo_idle_logo() -> void:
	for s: Node in find_children("*", "MenuLogo", true, false):
		(s as MenuLogo).go_idle()
