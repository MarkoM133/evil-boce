class_name ReplaysMenu
extends Control
## Replays (GDD 2) in the menus' look: every match this player played, newest first, each with
## both sides' heroes as art slices and how it ended, under a heading per day, with filters on top
## (Marko 2026-11-08, from the mockups). Watch it phase by phase, carry on from where it stopped, or
## delete it. Replays are local to this computer.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const MATCH_SCENE: String = "res://scenes/match/match.tscn"
const LOBBY_SCENE: String = "res://scenes/net/lobby.tscn"
## Set by the lobby: the host picks a replay to watch together, streamed to the table.
static var for_host: NetHost
const RESULTS: Dictionary = {"ko": "all heroes KO", "stages": "stages claimed", "deckout": "deck-out",
	"surrender": "surrender", "draw": "draw"}

## [button, filter]; see `matches`.
const FILTERS: Array[Array] = [["ALL", ""], ["ONLINE", "online"], ["BOTS", "bot"], ["NOT FINISHED", "open"]]
const MONTHS: Array[String] = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
const SECONDS_A_DAY: int = 86400
const NOTHING_YET: String = "NO REPLAYS YET. EVERY MATCH IS SAVED HERE WHEN IT ENDS."
const NOTHING_HERE: String = "NO MATCHES HERE."

## The filter open, kept while the game runs (back from watching a replay it is still on).
static var filter_open: String = ""

var db: CardDb
var _list: VBoxContainer
var _empty: Label
var _filter_bar: HBoxContainer
var _items: Array[Dictionary] = []


func _ready() -> void:
	db = CardDb.load_from(GameSettings.data_path())
	var frame: Dictionary = MenuScreen.build(self, db, "Replays",
		"Saved on this computer. Watch a match phase by phase, or carry on from where it stopped.",
		_back, 1300.0)
	# Balance (web app) sums up every match, beside the single replays here.
	var title_row: HBoxContainer = frame["title_row"]
	var balance: Button = WebApp.link("BALANCE", "balance", "Win rates of heroes and cards from every match played.")
	balance.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(balance)
	var back_btn: Button = frame["back"]
	title_row.move_child(balance, back_btn.get_index())
	var content: VBoxContainer = frame["content"]
	_filter_bar = HBoxContainer.new()
	_filter_bar.add_theme_constant_override("separation", 8)
	content.add_child(_filter_bar)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	content.add_child(_list)
	_empty = UiTheme.label(NOTHING_YET, 22, Palette.DIM)
	content.add_child(_empty)
	_fill()


func _back() -> void:
	var to_lobby: bool = for_host != null
	for_host = null
	get_tree().change_scene_to_file(LOBBY_SCENE if to_lobby else MENU_SCENE)


## Reads the replays again (a new visit, one deleted) and shows them.
func _fill() -> void:
	_items = ReplayStore.list_replays()
	_show_list()


func _show_filters() -> void:
	for c: Node in _filter_bar.get_children():
		_filter_bar.remove_child(c)
		c.queue_free()
	_filter_bar.visible = not _items.is_empty()
	for f: Array in FILTERS:
		var key: String = f[1]
		var b := Button.new()
		b.text = str(f[0])
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 18)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if key == filter_open:
			b.theme_type_variation = &"Gold"
		b.pressed.connect(func() -> void:
			filter_open = key
			_show_list())
		_filter_bar.add_child(b)


## The replays the filter lets through, a heading above each day's first.
func _show_list() -> void:
	_show_filters()
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var now: int = int(Time.get_unix_time_from_system())
	var bias: int = JsonUtil.as_int(Time.get_time_zone_from_system().get("bias", 0))
	var day_at: String = ""
	var shown: int = 0
	for r: Dictionary in _items:
		if not matches(r, filter_open):
			continue
		var day: String = day_label(_unix(str(r["created"])), now, bias)
		if day != day_at:
			day_at = day
			_appear(UiTheme.label(day, 18, Palette.GOLD), shown)
		_appear(_row(r), shown)
		shown += 1
	_empty.text = NOTHING_YET if _items.is_empty() else NOTHING_HERE
	_empty.visible = shown == 0


## Rows come in one after another.
func _appear(c: Control, i: int) -> void:
	_list.add_child(c)
	c.modulate.a = 0.0
	c.create_tween().tween_property(c, "modulate:a", 1.0, 0.18).set_delay(0.03 * mini(i, 12))


## Whether replay header `r` goes through `filter`: "" all, "open" not finished, else its kind.
static func matches(r: Dictionary, filter: String) -> bool:
	if filter.is_empty():
		return true
	if filter == "open":
		return not JsonUtil.as_bool(r.get("finished", false))
	return kind_of(r) == filter


## "bot" with a bot at the table, "local" for two seats at one screen ("Player 2"), else "online".
## By name too: replays from before the bot flag have none.
static func kind_of(r: Dictionary) -> String:
	for b: Variant in JsonUtil.as_array(r.get("bots", [])):
		if JsonUtil.as_bool(b):
			return "bot"
	var local: bool = false
	for n: String in JsonUtil.as_strings(r.get("names", [])):
		if n.begins_with("Bot"):
			return "bot"
		local = local or n.begins_with("Player ")
	return "local" if local else "online"


## The heading of the day of `unix` (seconds, UTC), as seen `bias` minutes ahead of UTC at `now`.
static func day_label(unix: int, now: int, bias: int) -> String:
	var at: int = unix + bias * 60
	var today: int = now + bias * 60
	var ago: int = floori(today / float(SECONDS_A_DAY)) - floori(at / float(SECONDS_A_DAY))
	if ago == 0:
		return "TODAY"
	if ago == 1:
		return "YESTERDAY"
	var d: Dictionary = Time.get_date_dict_from_unix_time(at)
	var text: String = "%d %s" % [JsonUtil.as_int(d["day"]), MONTHS[JsonUtil.as_int(d["month"]) - 1]]
	var this_year: int = JsonUtil.as_int(Time.get_date_dict_from_unix_time(today)["year"])
	return text if JsonUtil.as_int(d["year"]) == this_year else "%s %d" % [text, JsonUtil.as_int(d["year"])]


static func _unix(iso: String) -> int:
	return Time.get_unix_time_from_datetime_string(iso.trim_suffix("Z"))


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
	# Picking a replay for the table only watches; a local continue would leave the table waiting.
	if not JsonUtil.as_bool(r["finished"]) and for_host == null:
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
	if for_host != null and watch:
		MatchLaunch.config["net"] = {"role": "host", "node": for_host}
	for_host = null
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
	# "2026-10-25T13:40:00Z" -> "2026-10-25 14:40", this computer's time, as the day headings.
	var bias: int = JsonUtil.as_int(Time.get_time_zone_from_system().get("bias", 0))
	return Time.get_datetime_string_from_unix_time(_unix(iso) + bias * 60, true).substr(0, 16)


static func _turns(n: int) -> String:
	return "setup" if n <= 0 else "%d turn%s" % [n, "" if n == 1 else "s"]


## Screenshot helpers: the list with a filter on.
func demo_filter_online() -> void:
	filter_open = "online"
	_show_list()


func demo_filter_bots() -> void:
	filter_open = "bot"
	_show_list()


func demo_filter_open() -> void:
	filter_open = "open"
	_show_list()
