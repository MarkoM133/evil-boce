extends Control
## Play (GDD 7): everything that starts a game, on one screen of big tiles. Vs the bot and two
## players on this computer open the match setup with that opponent; Online opens the lobby;
## Practice opens the sandbox.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const SETUP_SCENE: String = "res://scenes/match/match_setup.tscn"
const LOBBY_SCENE: String = "res://scenes/net/lobby.tscn"
const SANDBOX_SCENE: String = "res://scenes/sandbox/sandbox.tscn"
const TILE := Vector2(268, 420)

## [title, what it is, action, art from: "hero" or "stage"]
const MODES: Array = [
	["VS BOT", "Against the computer, Easy or Hard", "bot", "hero"],
	["TWO PLAYERS", "Both of you on this computer", "local", "hero"],
	["ONLINE", "Host a match or join one over Tailscale", "online", "stage"],
	["PRACTICE", "Throw balls around, try terrain", "practice", "stage"],
]

var db: CardDb


func _ready() -> void:
	db = CardDb.load_from(GameSettings.data_path())
	var frame: Dictionary = MenuScreen.build(self, db, "Play", "Pick how you want to play.", _back, 1180.0)
	var content: VBoxContainer = frame["content"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(row)
	var heroes: Array[HeroDef] = db.heroes.duplicate() if db.is_ok() else []
	heroes.shuffle()
	var stages: Array[CardDef] = db.catalog.of_type("Stage") if db.is_ok() else []
	stages.shuffle()
	for i: int in MODES.size():
		var m: Array = MODES[i]
		var art_id: String = ""
		if str(m[3]) == "hero" and i < heroes.size():
			art_id = heroes[i].id
		elif str(m[3]) == "stage" and not stages.is_empty():
			art_id = stages[i % stages.size()].id
		var tile: Control = _tile(str(m[0]), str(m[1]), art_id, i == 0)
		var action: String = str(m[2])
		tile.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
					and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_go(action))
		row.add_child(tile)
		tile.modulate.a = 0.0
		tile.create_tween().tween_property(tile, "modulate:a", 1.0, 0.22).set_delay(0.06 * i)


## A tall tile: card art (dimmed until hovered), the title big at the bottom, a line under it.
func _tile(title: String, line: String, art_id: String, main: bool) -> Control:
	var s := HeroSlice.new()
	s.custom_minimum_size = TILE
	s.art_w = TILE.x
	s.art = null
	if db != null and not art_id.is_empty():
		s.art = db.large(art_id) if db.large(art_id) != null else db.thumb(art_id)
	if s.art != null:
		s.art_region = HeroSlice.card_art_region(s.art, TILE.x / TILE.y)
	s.art_fallback = Palette.SURFACE_2
	s.art_tint = Color(0.55, 0.55, 0.55)
	s.outline = Palette.ACCENT if main else Color(0, 0, 0, 0)
	s.outline_width = 3.0
	s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	s.mouse_entered.connect(func() -> void:
		s.art_tint = Color.WHITE
		s.outline = Palette.GOLD
		s.queue_redraw())
	s.mouse_exited.connect(func() -> void:
		s.art_tint = Color(0.55, 0.55, 0.55)
		s.outline = Palette.ACCENT if main else Color(0, 0, 0, 0)
		s.queue_redraw())
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.content.add_child(col)
	var t: Label = UiTheme.label(title, 34)
	t.add_theme_color_override("font_outline_color", Color.BLACK)
	t.add_theme_constant_override("outline_size", 10)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(t)
	var l := Label.new()
	l.text = line
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color("e6e1d8"))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	col.add_child(l)
	return s


func _go(action: String) -> void:
	match action:
		"bot":
			MatchSetup.preset_opponent = 0
			get_tree().change_scene_to_file(SETUP_SCENE)
		"local":
			MatchSetup.preset_opponent = 2
			get_tree().change_scene_to_file(SETUP_SCENE)
		"online":
			get_tree().change_scene_to_file(LOBBY_SCENE)
		"practice":
			get_tree().change_scene_to_file(SANDBOX_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and GameSettings.logical_key((event as InputEventKey).keycode) == KEY_ESCAPE:
		_back()


func _back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
