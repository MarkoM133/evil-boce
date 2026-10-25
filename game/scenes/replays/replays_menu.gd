extends Control
## Replays (GDD 2): every match this player played, newest first. Watch it phase by phase,
## carry on from where it stopped, or delete it. Replays are local to this computer.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const RESULTS: Dictionary = {"ko": "all heroes KO", "stages": "stages claimed", "deckout": "deck-out",
	"surrender": "surrender", "draw": "draw"}

var _list: VBoxContainer
var _empty: Label


func _ready() -> void:
	theme = UiTheme.get_theme()
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(760, 0)
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := Label.new()
	title.text = "REPLAYS"
	title.theme_type_variation = &"Big"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	head.add_child(back)
	var note := Label.new()
	note.theme_type_variation = &"Muted"
	note.text = "Saved on this computer. Watch a match phase by phase, or continue from any phase in a new match."
	col.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)
	_empty = Label.new()
	_empty.theme_type_variation = &"Muted"
	_empty.text = "No replays yet. Every match is saved here when it ends."
	col.add_child(_empty)
	_fill()


func _fill() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	var items: Array[Dictionary] = ReplayStore.list_replays()
	_empty.visible = items.is_empty()
	for r: Dictionary in items:
		_list.add_child(_row(r))


func _row(r: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.03), 3, Palette.LINE, 12, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var name := Label.new()
	name.text = str(r["title"])
	name.add_theme_font_override("font", UiTheme.display_bold())
	name.add_theme_font_size_override("font_size", 20)
	text.add_child(name)
	var info := Label.new()
	info.theme_type_variation = &"Muted"
	info.text = "%s  ·  %s  ·  %s" % [_when(str(r["created"])), _turns(JsonUtil.as_int(r["turns"])), _outcome(r)]
	text.add_child(info)
	var path: String = str(r["path"])
	var watch := Button.new()
	watch.text = "Watch"
	watch.pressed.connect(func() -> void: _open(path, true))
	row.add_child(watch)
	if not JsonUtil.as_bool(r["finished"]):
		var go := Button.new()
		go.text = "Continue"
		go.tooltip_text = "Carry on from the last phase"
		go.pressed.connect(func() -> void: _open(path, false))
		row.add_child(go)
	var del := Button.new()
	del.text = "Delete"
	del.pressed.connect(func() -> void:
		# Two clicks: the first asks, the second deletes.
		if del.text == "Delete":
			del.text = "Sure?"
			del.add_theme_color_override("font_color", Palette.ACCENT)
			return
		ReplayStore.delete(path)
		_fill())
	row.add_child(del)
	return panel


func _open(path: String, watch: bool) -> void:
	var record: MatchRecord = ReplayStore.load_record(path)
	if record == null or record.frame_count() == 0:
		return
	MatchLaunch.config = MatchLaunch.from_record(record, 0 if watch else -1, watch)
	get_tree().change_scene_to_file(MATCH_SCENE)


## Screenshot helper (tools/screenshot.gd --call=demo_watch_current): watches the unfinished
## match from `frame` and starts playing.
func demo_watch_current(frame: int = 6) -> void:
	var record: MatchRecord = ReplayStore.load_current()
	if record == null:
		push_error("no user://saves/current.json")
		return
	MatchLaunch.config = MatchLaunch.from_record(record, frame, true)
	MatchLaunch.config["autoplay"] = true
	get_tree().change_scene_to_file(MATCH_SCENE)


static func _when(iso: String) -> String:
	# "2026-10-25T13:40:00Z" -> "2026-10-25 13:40" (UTC)
	return iso.replace("T", " ").substr(0, 16)


static func _turns(n: int) -> String:
	return "setup" if n <= 0 else "%d turn%s" % [n, "" if n == 1 else "s"]


static func _outcome(r: Dictionary) -> String:
	if not JsonUtil.as_bool(r["finished"]):
		return "not finished"
	var winner: int = JsonUtil.as_int(r["winner"], -1)
	var why: String = str(RESULTS.get(str(r["result"]), str(r["result"])))
	if winner < 0:
		return "draw (%s)" % why
	var names: PackedStringArray = str(r["title"]).split(" vs ")
	var who: String = names[winner] if winner < names.size() else "Player %d" % (winner + 1)
	return "%s won (%s)" % [who, why]
