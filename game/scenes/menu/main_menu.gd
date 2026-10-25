extends Control
## Main menu (GDD 7) in one of three layouts (Settings → Main menu). "Featured hero" (mockup M5):
## one hero's card art fills the right side behind a slanted cut and changes every few seconds;
## the logo sits small top left and the entries run down the left in big italics. "Tiles"
## (mockup M7): a hub of big tiles like a mobile game's. Every entry works: Continue (an unfinished
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
## Tile hub (M7) instead of the featured hero (M5); Settings → Main menu.
var _tiles: bool = false


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
	var layout: String = GameSettings.menu_layout()
	_tiles = layout != "featured"
	if layout == "tiles":
		_build_tiles(logo)
	elif layout == "cinema" or layout == "table":
		_build_cinema(logo, layout == "table")
	elif layout == "strip":
		_build_strip(logo)
	else:
		_build_featured(logo)

	var foot := Label.new()
	foot.add_theme_color_override("font_color", Palette.DIM)
	foot.add_theme_font_size_override("font_size", 13)
	# Above the bottom strip in the cinema layout; bottom right beside the side strip.
	if layout == "strip":
		foot.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		foot.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
		foot.offset_left = -20
		foot.offset_right = -20
		foot.offset_top = -16
		foot.offset_bottom = -16
	else:
		foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
		foot.position = Vector2(18, -150 if layout == "cinema" or layout == "table" else -34)
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	if db.is_ok():
		foot.text = "v%s  ·  cards v%d, %d cards" % [version, db.version, db.card_count]
	else:
		foot.text = "v%s  ·  %s  ·  set the shared folder in Settings" % [version, db.error]
		foot.add_theme_color_override("font_color", Palette.GOLD)
	add_child(foot)


# --- cinema (mockup M8) ---------------------------------------------------------------------

## Letterbox: hero strips along the top and the bottom drifting opposite ways, the logo big in
## the middle, the entries in one row under it and a line about the one in focus. Beside the
## logo two cards (M8 + 5), or with `table` the match table behind it all (M8 + 3).
func _build_cinema(logo: Texture2D, table: bool = false) -> void:
	if table:
		var t := MenuTable.new()
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.offset_top = 113
		t.offset_bottom = -113
		add_child(t)
		t.setup(db)
		t.modulate.a = 0.0
		t.create_tween().tween_property(t, "modulate:a", 1.0, 0.6)
	for bottom: bool in [false, true]:
		var strip := HeroStrip.new()
		strip.setup(db)
		strip.reverse = bottom
		strip.edge_top = bottom
		strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
		strip.custom_minimum_size = Vector2(0, 110)
		if bottom:
			strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
			strip.offset_top = -110
		add_child(strip)
		var line := ColorRect.new()
		line.color = Palette.ACCENT
		line.set_anchors_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
		line.offset_top = -113.0 if bottom else 110.0
		line.offset_bottom = -110.0 if bottom else 113.0
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_top = 125
	col.offset_bottom = -125
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 18)
	add_child(col)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The logo between two cards (mockup M8 + 5): the last match on the left, what is new on
	# the right. Over the table, the logo alone and a bit smaller.
	var stage := HBoxContainer.new()
	stage.alignment = BoxContainer.ALIGNMENT_CENTER
	stage.add_theme_constant_override("separation", 56)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stage)
	var cards: Array[Control] = []
	if not table:
		cards.append_array([_last_match_card(), _whats_new_card()])
		stage.add_child(cards[0])
	if logo != null:
		var img := TextureRect.new()
		img.texture = logo
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img.custom_minimum_size = Vector2(340, 320) if table else Vector2(400, 380)
		stage.add_child(img)
		img.modulate.a = 0.0
		var lt: Tween = img.create_tween()
		lt.tween_property(img, "modulate:a", 1.0, 0.4)
	else:
		var title: Label = UiTheme.label("EVIL BOĆE", 110)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stage.add_child(title)
	if not table:
		stage.add_child(cards[1])
	for c: Control in cards:
		c.modulate.a = 0.0
		c.create_tween().tween_property(c, "modulate:a", 1.0, 0.3).set_delay(0.35)

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
		b.modulate.a = 0.0
		b.create_tween().tween_property(b, "modulate:a", 1.0, 0.22).set_delay(0.05 * i + delay)


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

	# The logo, big, right of the middle.
	var holder := CenterContainer.new()
	holder.anchor_left = 0.52
	holder.anchor_right = 1.0
	holder.anchor_bottom = 1.0
	holder.offset_right = -60
	add_child(holder)
	if logo != null:
		var img := TextureRect.new()
		img.texture = logo
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.custom_minimum_size = Vector2(580, 580)
		holder.add_child(img)
		img.modulate.a = 0.0
		img.create_tween().tween_property(img, "modulate:a", 1.0, 0.4)
	else:
		holder.add_child(UiTheme.label("EVIL BOĆE", 120))


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
			var r: Rect2 = MenuTile.card_art_region(tex, 2.0)
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


# --- tiles (mockup M7)----------------------------------------------------------------------

## A hub like a mobile game's: a thin hero strip, the logo and what is new in the cards on top,
## two big tiles with the heroes' pixel figures (Play: two face off; Online: a crew; Continue
## takes half of Play when a match waits), a row of small tiles, Exit in the corner.
func _build_tiles(logo: Texture2D) -> void:
	var strip := HeroStrip.new()
	strip.setup(db)
	strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip.custom_minimum_size = Vector2(0, 56)
	add_child(strip)
	# Logo and news along the top, out by the edges; the tiles below in the middle of the
	# screen at a share of it ("zoomed out"), with room between them.
	var head := HBoxContainer.new()
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_left = 230
	head.offset_right = -230
	head.offset_top = 80
	head.offset_bottom = 168
	head.add_theme_constant_override("separation", 16)
	add_child(head)
	var margin := MarginContainer.new()
	margin.anchor_left = 0.2
	margin.anchor_right = 0.8
	margin.anchor_top = 0.25
	margin.anchor_bottom = 0.9
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)

	if logo != null:
		var img := TextureRect.new()
		img.texture = logo
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.custom_minimum_size = Vector2(110, 88)
		head.add_child(img)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var news: Control = _news()
	if news != null:
		head.add_child(news)

	# Heroes for the figures: Play shows two of different sets facing off, Online a crew.
	var with_sprite: Array[HeroDef] = []
	for h: HeroDef in _heroes:
		if db.sprite(h) != null:
			with_sprite.append(h)
	var big := HBoxContainer.new()
	big.add_theme_constant_override("separation", 12)
	big.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(big)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.5
	big.add_child(left)
	var current: MatchRecord = ReplayStore.load_current() if ReplayStore.has_current() else null
	if current != null and current.frame_count() > 0:
		var cont: MenuTile = _tile(left, "CONTINUE", "%s  ·  turn %d" % [current.title(), current.state_at(current.frame_count() - 1).turn],
			Palette.GOLD.darkened(0.15), 42, "continue", _sprites_of(current))
		cont.title_color = Color.BLACK
		cont.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pair: Array[HeroDef] = _face_off(with_sprite)
	# Play: the two heroes' real card art, cut apart on a slant.
	var play: MenuTile = _tile(left, "PLAY", "Against the bot, or two players on this computer", Palette.ACCENT,
		54 if current == null else 42, "play")
	for h: HeroDef in pair:
		var tex: Texture2D = db.large(h.id)
		play.split_art.append(tex if tex != null else db.thumb(h.id))
	# On hover: the table of the last match, or a stage when there is none yet.
	play.hover_art = ReplayStore.last_shot()
	play.hover_subtitle = ReplayStore.last_caption()
	if play.hover_art == null and db.is_ok() and not db.catalog.of_type("Stage").is_empty():
		var st: CardDef = db.catalog.of_type("Stage").pick_random()
		play.hover_art = db.large(st.id)
		play.hover_card = true
		play.hover_subtitle = "Pick decks, stages and cores  ·  %s" % st.name
	play.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Online: three others.
	var crew: Array[Texture2D] = []
	for h: HeroDef in with_sprite:
		if crew.size() < 3 and not pair.has(h):
			crew.append(db.sprite(h))
	var online: MenuTile = _tile(big, "ONLINE", "Host or join over Tailscale", Color("1d4fd1").darkened(0.25), 46, "online", crew)
	# Behind the crew: a random stage's art, as if they stood there.
	var stages: Array[CardDef] = db.catalog.of_type("Stage") if db.is_ok() else []
	if not stages.is_empty():
		var st: CardDef = stages.pick_random()
		online.art = db.large(st.id) if db.large(st.id) != null else db.thumb(st.id)
		online.fit_art = true
		online.tooltip_text = "Host or join over Tailscale  ·  on %s" % st.name

	var small := HBoxContainer.new()
	small.add_theme_constant_override("separation", 12)
	small.custom_minimum_size = Vector2(0, 68)
	col.add_child(small)
	var replays: int = ReplayStore.list_replays().size()
	var decks: int = DeckStore.load_all(db.root_dir).size() if db.is_ok() else 0
	_tile(small, "SANDBOX", "Throw balls around, try terrain", Palette.PANEL_SOLID, 22, "sandbox")
	_tile(small, "REPLAYS", "%d saved" % replays if replays > 0 else "None yet", Palette.PANEL_SOLID, 22, "replays")
	_tile(small, "DECKS", "%d deck%s" % [decks, "" if decks == 1 else "s"] if decks > 0 else "Deck codes", Palette.PANEL_SOLID, 22, "decks")
	_tile(small, "SETTINGS", "Display, sound, keys", Palette.PANEL_SOLID, 22, "settings")

	var exit := Button.new()
	exit.text = "EXIT"
	exit.theme_type_variation = &"Ghost"
	exit.add_theme_font_size_override("font_size", 22)
	exit.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	exit.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	exit.grow_vertical = Control.GROW_DIRECTION_BEGIN
	exit.anchor_left = 0.8
	exit.anchor_right = 0.8
	exit.anchor_top = 0.9
	exit.anchor_bottom = 0.9
	exit.position = Vector2(-90, 10)
	exit.pressed.connect(_on_pressed.bind("exit"))
	add_child(exit)
	# Tiles come in one after another.
	var i: int = 0
	for row: Container in [left, big, small]:
		for c: Node in row.get_children():
			if not c is MenuTile:
				continue
			var t := c as Control
			t.modulate.a = 0.0
			t.create_tween().tween_property(t, "modulate:a", 1.0, 0.25).set_delay(0.06 * i + 0.1)
			i += 1


func _tile(parent: Control, title: String, subtitle: String, color: Color, size: int, action: String,
		figures: Array[Texture2D] = []) -> MenuTile:
	var t := MenuTile.new()
	t.title = title
	t.subtitle = subtitle
	t.color = color
	t.title_size = size
	t.figures = figures
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.pressed.connect(_on_pressed.bind(action))
	parent.add_child(t)
	return t


## Two heroes from different sets (One Piece against JoJo, when there are both).
func _face_off(heroes: Array[HeroDef]) -> Array[HeroDef]:
	var out: Array[HeroDef] = []
	if heroes.is_empty():
		return out
	out.append(heroes[0])
	for h: HeroDef in heroes.slice(1):
		if h.set_code != heroes[0].set_code:
			out.append(h)
			return out
	if heroes.size() > 1:
		out.append(heroes[1])
	return out


## The active heroes of the match waiting to be continued: player 1's first, the other's first.
func _sprites_of(rec: MatchRecord) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for p: Dictionary in rec.players:
		var ids: Array = JsonUtil.as_array(p.get("heroes", []))
		if ids.is_empty():
			continue
		for h: HeroDef in db.heroes:
			if h.id == str(ids[0]) and db.sprite(h) != null:
				out.append(db.sprite(h))
	return out


## What is new in the cards (data/changelog.json, written by the web app on Publish): the
## latest version, how many cards came and changed, a few names. Null without a changelog.
func _news() -> Control:
	var last: Dictionary = _last_changelog()
	if last.is_empty():
		return null
	var counts: Dictionary = {}
	var names := PackedStringArray()
	for c: Variant in JsonUtil.as_array(last.get("cards", [])):
		var cd: Dictionary = JsonUtil.as_dict(c)
		var kind: String = str(cd.get("kind", "changed"))
		counts[kind] = JsonUtil.as_int(counts.get(kind, 0)) + 1
		if names.size() < 4 and kind != "deleted":
			names.append(str(cd.get("name", "")))
	var panel := PanelContainer.new()
	var sb: StyleBoxFlat = UiTheme.box(Palette.PANEL_SOLID, 0, Color(0, 0, 0, 0), 22, 12)
	sb.skew = Vector2(UiTheme.SKEW * 0.5, 0)
	sb.border_color = Palette.GOLD
	sb.border_width_left = 4
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(400, 0)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)
	var date: String = str(last.get("date", "")).substr(0, 10)
	v.add_child(UiTheme.label("WHAT'S NEW  ·  CARDS v%d  ·  %s" % [JsonUtil.as_int(last.get("version", 0)), date], 14, Palette.GOLD))
	var parts := PackedStringArray()
	for kind: String in ["new", "changed", "deleted"]:
		if counts.has(kind):
			parts.append("%d %s" % [JsonUtil.as_int(counts[kind]), kind])
	v.add_child(UiTheme.label(", ".join(parts).to_upper(), 22))
	var list := Label.new()
	list.text = ", ".join(names) + ("…" if JsonUtil.as_array(last.get("cards", [])).size() > names.size() else "")
	list.add_theme_color_override("font_color", Palette.MUTED)
	list.add_theme_font_size_override("font_size", 13)
	list.clip_text = true
	list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(list)
	return panel


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


# --- featured hero (mockup M5) --------------------------------------------------------------

func _build_featured(logo: Texture2D) -> void:
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
	_entry_buttons(col, 50, true, 0.1)
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", Palette.MUTED)
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.custom_minimum_size = Vector2(0, 40)
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	col.add_child(_hint)
	_show_hero(0)


func _process(delta: float) -> void:
	if _tiles or _heroes.size() < 2:
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


## Screenshot helper: hovers the Play tile.
func demo_hover_play() -> void:
	for t: Node in find_children("*", "MenuTile", true, false):
		var tile := t as MenuTile
		if tile.title == "PLAY":
			tile._set_hover(true)


func demo_table_open() -> void:
	for t: Node in find_children("*", "MenuTable", true, false):
		(t as MenuTable).pin_first()
