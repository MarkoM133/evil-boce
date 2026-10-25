extends Control
## Decks (GDD 7): every saved deck (the shared folder's, from the web app's deck builder, and
## the ones imported here), what is in it, whether it passes the deck rules, and its code.
## A pasted deck code is imported onto this computer; deleting works for those only.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const TYPE_ORDER: Array[String] = ["Evolution", "Action", "Equipment", "Assist"]
const THUMB: Vector2 = Vector2(104, 146)

var db: CardDb
var decks: Array[Dictionary] = []
var _list: ItemList
var _detail: VBoxContainer
var _status: Label
var _code_in: LineEdit
var _name_in: LineEdit
var _selected: int = -1


func _ready() -> void:
	theme = UiTheme.get_theme()
	db = CardDb.load_from(GameSettings.data_path())
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var strip := HeroStrip.new()
	strip.setup(db)
	strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip.custom_minimum_size = Vector2(0, 84)
	add_child(strip)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", 100)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)

	# Left: the list and the import box.
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(340, 0)
	row.add_child(left_panel)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left_panel.add_child(left)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	left.add_child(title_row)
	var slash: UiShape = UiShape.make(UiShape.Kind.SLANT, Palette.ACCENT, Vector2(14, 44))
	slash.cut = 8.0
	title_row.add_child(slash)
	title_row.add_child(UiTheme.label("DECKS", 44))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_show)
	left.add_child(_list)
	_header(left, "IMPORT A DECK CODE")
	_code_in = LineEdit.new()
	_code_in.placeholder_text = "EB1|v7|…  (Copy code in the web app's deck builder)"
	_code_in.text_changed.connect(func(_t: String) -> void: _preview_code())
	left.add_child(_code_in)
	var import_row := HBoxContainer.new()
	import_row.add_theme_constant_override("separation", 8)
	left.add_child(import_row)
	_name_in = LineEdit.new()
	_name_in.placeholder_text = "Name"
	_name_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_in.text_submitted.connect(func(_t: String) -> void: _import())
	import_row.add_child(_name_in)
	var import_btn := Button.new()
	import_btn.text = "IMPORT"
	import_btn.theme_type_variation = &"Gold"
	import_btn.pressed.connect(_import)
	import_row.add_child(import_btn)
	_status = Label.new()
	_status.theme_type_variation = &"Muted"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_status)
	var back := Button.new()
	back.text = "‹  BACK"
	back.pressed.connect(func() -> void: get_tree().change_scene_to_file(MENU_SCENE))
	left.add_child(back)

	# Right: the selected deck.
	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_panel.add_child(scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 10)
	scroll.add_child(_detail)

	if not db.is_ok():
		_status.text = db.error
	_reload("")


func _header(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Header"
	parent.add_child(l)


## Reads the decks again and selects the one called `select` (or the first).
func _reload(select: String) -> void:
	decks = DeckStore.load_all(db.root_dir)
	_list.clear()
	var pick: int = 0
	for i: int in decks.size():
		var d: Dictionary = decks[i]
		var problems: PackedStringArray = _problems(d)
		var mark: String = "" if problems.is_empty() else "  ⚠"
		var where: String = "  ·  imported" if JsonUtil.as_bool(d["local"]) else ""
		_list.add_item("%s%s%s" % [str(d["name"]), where, mark])
		if str(d["name"]) == select:
			pick = i
	if decks.is_empty():
		_clear_detail()
		var none := Label.new()
		none.text = "No decks yet. Build one in the web app's deck builder, or paste a deck code on the left."
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(none)
		return
	_list.select(pick)
	_show(pick)


func _problems(d: Dictionary) -> PackedStringArray:
	return DeckCode.check(db.catalog, JsonUtil.as_strings(d["heroes"]), JsonUtil.as_dict(d["cards"]))


func _clear_detail() -> void:
	for c: Node in _detail.get_children():
		c.queue_free()


func _show(i: int) -> void:
	_selected = i
	_clear_detail()
	var d: Dictionary = decks[i]
	var heroes: PackedStringArray = JsonUtil.as_strings(d["heroes"])
	var cards: Dictionary = JsonUtil.as_dict(d["cards"])
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_detail.add_child(head)
	var name_l := Label.new()
	name_l.text = str(d["name"])
	name_l.theme_type_variation = &"Big"
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_l)
	var copy := Button.new()
	copy.text = "Copy deck code"
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(DeckCode.encode(heroes, cards, db.version))
		_status.text = "Deck code of %s copied." % str(d["name"]))
	head.add_child(copy)
	if JsonUtil.as_bool(d["local"]):
		var del := Button.new()
		del.text = "Delete"
		del.tooltip_text = "Imported decks only; shared decks are edited in the web app"
		del.pressed.connect(func() -> void:
			if DeckStore.delete_local(str(d["path"])):
				_status.text = "%s deleted." % str(d["name"])
				_reload(""))
		head.add_child(del)

	var total: int = 0
	for k: Variant in cards:
		total += JsonUtil.as_int(cards[k])
	var info := Label.new()
	info.theme_type_variation = &"Muted"
	var source: String = "imported on this computer" if JsonUtil.as_bool(d["local"]) else "shared folder"
	info.text = "%d cards  ·  %s" % [total, source]
	var v: int = JsonUtil.as_int(d.get("version", 0))
	if v > db.version:
		info.text += "  ·  built with cards v%d, you have v%d: sync the shared folder" % [v, db.version]
	_detail.add_child(info)
	var problems: PackedStringArray = _problems(d)
	if not problems.is_empty():
		var warn := Label.new()
		warn.text = "Breaks the deck rules: " + "; ".join(problems)
		warn.add_theme_color_override("font_color", Palette.GOLD)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(warn)

	_header(_detail, "HEROES")
	var hero_row := HBoxContainer.new()
	hero_row.add_theme_constant_override("separation", 10)
	_detail.add_child(hero_row)
	for id: String in heroes:
		hero_row.add_child(_card_tile(id, 1))
	var by_type: Dictionary[String, Array] = {}
	for k: Variant in cards:
		var c: CardDef = db.catalog.get_card(str(k))
		var t: String = c.type if c != null else "Unknown"
		if not by_type.has(t):
			by_type[t] = []
		by_type[t].append(str(k))
	var order: Array[String] = TYPE_ORDER.duplicate()
	for t: String in by_type:
		if not order.has(t):
			order.append(t)
	for t: String in order:
		if not by_type.has(t):
			continue
		var ids: Array = by_type[t]
		ids.sort_custom(func(a: Variant, b: Variant) -> bool: return _cost(str(a)) < _cost(str(b)) or (_cost(str(a)) == _cost(str(b)) and str(a) < str(b)))
		var n: int = 0
		for id: Variant in ids:
			n += JsonUtil.as_int(cards[id])
		_header(_detail, "%s  ·  %d" % [t.to_upper(), n])
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		_detail.add_child(grid)
		for id: Variant in ids:
			grid.add_child(_card_tile(str(id), JsonUtil.as_int(cards[id])))


func _cost(id: String) -> int:
	var c: CardDef = db.catalog.get_card(id)
	return c.cost if c != null else 99


## A card's thumbnail (or its name on a coloured tile) with the copy count in the corner.
func _card_tile(id: String, count: int) -> Control:
	var c: CardDef = db.catalog.get_card(id)
	var box := Control.new()
	var tex: Texture2D = db.thumb(id)
	# Heroes and evolutions are landscape cards: turn the tile with the image.
	var size: Vector2 = THUMB
	if tex != null and tex.get_width() > tex.get_height():
		size = Vector2(THUMB.y, THUMB.x)
	box.custom_minimum_size = size
	if tex != null:
		var img := TextureRect.new()
		img.texture = tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.add_child(img)
	else:
		var tile := ColorRect.new()
		tile.color = Palette.hero(c.color if c != null else "").darkened(0.5)
		tile.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.add_child(tile)
		var l := Label.new()
		l.text = c.name if c != null else id
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.add_child(l)
	if count > 1:
		var badge := Label.new()
		badge.text = "×%d" % count
		badge.add_theme_font_override("font", UiTheme.display_bold())
		badge.add_theme_font_size_override("font_size", 22)
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		badge.add_theme_constant_override("outline_size", 6)
		badge.position = size - Vector2(40, 32)
		box.add_child(badge)
	if c == null:
		box.tooltip_text = "%s is not in cards.json (sync the shared folder)" % id
	else:
		box.tooltip_text = "%s  ·  %s %s%s\n%s" % [c.name, c.color, c.type, "  ·  cost %d" % c.cost if c.type != "Hero" else "", c.text]
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	return box


# --- import -------------------------------------------------------------------------------

func _preview_code() -> void:
	var code: String = _code_in.text.strip_edges()
	if code.is_empty():
		_status.text = ""
		return
	var d: Dictionary = DeckCode.decode(code)
	if not JsonUtil.as_bool(d.get("ok", false)):
		_status.text = str(d.get("error", ""))
		return
	var heroes: PackedStringArray = d["heroes"]
	var names := PackedStringArray()
	for id: String in heroes:
		var c: CardDef = db.catalog.get_card(id)
		names.append(c.name if c != null else id)
	_status.text = "Heroes: %s" % ", ".join(names)
	if _name_in.text.strip_edges().is_empty():
		_name_in.placeholder_text = " / ".join(names)


func _import() -> void:
	var d: Dictionary = DeckCode.decode(_code_in.text)
	if not JsonUtil.as_bool(d.get("ok", false)):
		_status.text = str(d.get("error", "Paste a deck code first."))
		return
	var name: String = _name_in.text.strip_edges()
	if name.is_empty():
		name = _name_in.placeholder_text if _name_in.placeholder_text != "Name" else "Imported deck"
	for x: Dictionary in decks:
		if str(x["name"]) == name and not JsonUtil.as_bool(x["local"]):
			_status.text = "The shared folder already has a deck called %s; pick another name." % name
			return
	var heroes: PackedStringArray = d["heroes"]
	var cards: Dictionary = d["cards"]
	var version: int = JsonUtil.as_int(d["version"])
	var replaced: bool = DeckStore.local_exists(name)
	if DeckStore.save_local(name, heroes, cards, version).is_empty():
		_status.text = "Could not save the deck."
		return
	var problems: PackedStringArray = DeckCode.check(db.catalog, heroes, cards)
	_status.text = "%s %s.%s" % [name, "replaced" if replaced else "imported",
		"" if problems.is_empty() else " It breaks the deck rules, so Play will not take it as it is."]
	if version > db.version:
		_status.text += " Built with cards v%d, you have v%d: sync the shared folder." % [version, db.version]
	_code_in.text = ""
	_name_in.text = ""
	_name_in.placeholder_text = "Name"
	_reload(name)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and GameSettings.logical_key((event as InputEventKey).keycode) == KEY_ESCAPE:
		get_tree().change_scene_to_file(MENU_SCENE)


# --- screenshot helpers -------------------------------------------------------------------

## Puts a random deck's code in the import box and shows that deck (without saving it).
func demo_code() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var d: Dictionary = DeckCode.random_deck(db.catalog, rng)
	_code_in.text = DeckCode.encode(JsonUtil.as_strings(d["heroes"]), JsonUtil.as_dict(d["cards"]), db.version)
	_preview_code()
	# Shown, not saved: nothing is written to this computer.
	decks.append({"name": "Random deck (demo)", "heroes": d["heroes"], "cards": d["cards"], "local": false,
		"path": "", "version": db.version})
	_list.add_item("Random deck (demo)")
	_list.select(decks.size() - 1)
	_show(decks.size() - 1)
