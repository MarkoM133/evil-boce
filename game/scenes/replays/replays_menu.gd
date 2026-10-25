extends Control
## Replays (GDD 2) in the menus' look: every match this player played, newest first, each with
## both sides' heroes as art slices and how it ended. Watch it phase by phase, carry on from
## where it stopped, or delete it. Replays are local to this computer.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const RESULTS: Dictionary = {"ko": "all heroes KO", "stages": "stages claimed", "deckout": "deck-out",
	"surrender": "surrender", "draw": "draw"}

var db: CardDb
var _list: VBoxContainer
var _empty: Label


func _ready() -> void:
	db = CardDb.load_from(GameSettings.data_path())
	var frame: Dictionary = MenuScreen.build(self, db, "Replays",
		"Saved on this computer. Watch a match phase by phase, or carry on from where it stopped.",
		func() -> void: get_tree().change_scene_to_file(MENU_SCENE), 1300.0)
	var content: VBoxContainer = frame["content"]
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	content.add_child(_list)
	_empty = UiTheme.label("NO REPLAYS YET. EVERY MATCH IS SAVED HERE WHEN IT ENDS.", 22, Palette.DIM)
	content.add_child(_empty)
	_fill()


func _fill() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	var items: Array[Dictionary] = ReplayStore.list_replays()
	_empty.visible = items.is_empty()
	for i: int in items.size():
		var row: Control = _row(items[i])
		_list.add_child(row)
		# Rows come in one after another.
		row.modulate.a = 0.0
		row.create_tween().tween_property(row, "modulate:a", 1.0, 0.18).set_delay(0.03 * mini(i, 12))


func _row(r: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(Palette.PANEL_SOLID, 0, Color(0, 0, 0, 0), 16, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)
	# Both sides' heroes, a VS between them.
	var heroes: Array = JsonUtil.as_array(r.get("heroes", []))
	for side: int in 2:
		var ids: Array = JsonUtil.as_array(heroes[side]) if side < heroes.size() else []
		var strip := HBoxContainer.new()
		strip.add_theme_constant_override("separation", -8)
		row.add_child(strip)
		for id: Variant in ids:
			strip.add_child(_mini_slice(str(id), side))
		if side == 0:
			var vs: Label = UiTheme.label("VS", 22, Palette.ACCENT)
			vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(vs)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	var name_l: Label = UiTheme.label(str(r["title"]).to_upper(), 24)
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.add_child(name_l)
	var info := Label.new()
	info.add_theme_color_override("font_color", Palette.MUTED)
	info.add_theme_font_size_override("font_size", 13)
	info.text = "%s  ·  %s" % [_when(str(r["created"])), _turns(JsonUtil.as_int(r["turns"]))]
	text.add_child(info)
	var outcome: UiShape = _outcome_chip(r)
	outcome.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(outcome)

	var path: String = str(r["path"])
	var watch := Button.new()
	watch.text = "WATCH"
	watch.theme_type_variation = &"Gold"
	watch.add_theme_font_size_override("font_size", 20)
	watch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	watch.pressed.connect(func() -> void: _open(path, true))
	row.add_child(watch)
	if not JsonUtil.as_bool(r["finished"]):
		var go := Button.new()
		go.text = "CONTINUE"
		go.tooltip_text = "Carry on from the last phase"
		go.add_theme_font_size_override("font_size", 20)
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.pressed.connect(func() -> void: _open(path, false))
		row.add_child(go)
	var del := Button.new()
	del.text = "DELETE"
	del.theme_type_variation = &"Ghost"
	del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	del.pressed.connect(func() -> void:
		# Two clicks: the first asks, the second deletes.
		if del.text == "DELETE":
			del.text = "SURE?"
			del.add_theme_color_override("font_color", Palette.ACCENT)
			return
		ReplayStore.delete(path)
		_fill())
	row.add_child(del)
	return panel


func _mini_slice(id: String, side: int) -> Control:
	var s := HeroSlice.new()
	s.custom_minimum_size = Vector2(78, 50)
	s.art_w = 78.0
	s.set_mirrored(false)
	var card: CardDef = db.catalog.get_card(id) if db != null and db.is_ok() else null
	s.art = db.thumb(id) if card != null else null
	s.art_region = HeroSlice.region_for(s.art)
	s.art_fallback = Palette.hero(card.color if card != null else "").darkened(0.3)
	s.stripe = Palette.team(side)
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	s.tooltip_text = card.name if card != null else id
	return s


func _outcome_chip(r: Dictionary) -> UiShape:
	if not JsonUtil.as_bool(r["finished"]):
		return UiShape.chip("NOT FINISHED", Palette.SURFACE_2, Palette.MUTED, 15, 28.0, 12.0)
	var winner: int = JsonUtil.as_int(r["winner"], -1)
	var why: String = str(RESULTS.get(str(r["result"]), str(r["result"]))).to_upper()
	if winner < 0:
		return UiShape.chip("DRAW · " + why, Palette.FG, Color.BLACK, 15, 28.0, 12.0)
	var names: PackedStringArray = str(r["title"]).split(" vs ")
	var who: String = names[winner] if winner < names.size() else "Player %d" % (winner + 1)
	return UiShape.chip("%s WON · %s" % [who.to_upper(), why], Palette.team(winner), Palette.FG, 15, 28.0, 12.0)


func _open(path: String, watch: bool) -> void:
	var record: MatchRecord = ReplayStore.load_record(path)
	if record == null or record.frame_count() == 0:
		return
	MatchLaunch.config = MatchLaunch.from_record(record, 0 if watch else -1, watch)
	get_tree().change_scene_to_file(MATCH_SCENE)


## Screenshot helper (tools/screenshot.gd --call=demo_watch_current): watches the unfinished
## match from `frame` and starts playing.
func demo_watch_current(frame_i: int = 6) -> void:
	var record: MatchRecord = ReplayStore.load_current()
	if record == null:
		push_error("no user://saves/current.json")
		return
	MatchLaunch.config = MatchLaunch.from_record(record, frame_i, true)
	MatchLaunch.config["autoplay"] = true
	get_tree().change_scene_to_file(MATCH_SCENE)


static func _when(iso: String) -> String:
	# "2026-10-25T13:40:00Z" -> "2026-10-25 13:40" (UTC)
	return iso.replace("T", " ").substr(0, 16)


static func _turns(n: int) -> String:
	return "setup" if n <= 0 else "%d turn%s" % [n, "" if n == 1 else "s"]
