extends Control
## Decks (GDD 7; Marko 2026-11-08, from the mockups): every saved deck (the shared folder's, from
## the web app's deck builder, and the ones imported here) as a row with its heroes on the left,
## the chosen one on the right as real cards. With no deck at all, the two ways to get one.
## A pasted deck code is imported onto this computer; deleting works for those only.

const MENU_SCENE: String = "res://scenes/menu/main_menu.tscn"
const TYPE_ORDER: Array[String] = ["Evolution", "Action", "Equipment", "Assist"]
const HERO_CARD_H: float = 172.0
const CARD_H: float = 160.0
## Fits the frame under the title at the game's 900 px height, so only the panels scroll.
const MAIN_H: float = 686.0
const LEGAL_GREEN: Color = Color("23b14d")
const NAME_HINT: String = "name"

var db: CardDb
var decks: Array[Dictionary] = []
var _main: HBoxContainer
var _empty: HBoxContainer
var _empty_paste: VBoxContainer
var _rows_box: VBoxContainer
var _rows: Array[PanelContainer] = []
var _detail: VBoxContainer
## Where messages go: the line under the list, or the paste form while one is showing.
var _status: Label
var _main_status: Label
var _code_in: LineEdit
var _name_in: LineEdit
var _paste_layer: Control
var _selected: int = -1


func _ready() -> void:
	db = CardDb.load_from(GameSettings.data_path())
	var frame: Dictionary = MenuScreen.build(self, db, "Decks", "Your decks. Build them in the web app.", _back, 1500.0)
	var content: VBoxContainer = frame["content"]
	_build_main(content)
	_build_empty(content)
	_reload("")
	if not db.is_ok():
		_status.text = db.error


func _back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func _build_main(content: VBoxContainer) -> void:
	_main = HBoxContainer.new()
	_main.add_theme_constant_override("separation", 16)
	_main.custom_minimum_size.y = MAIN_H
	content.add_child(_main)

	var left: VBoxContainer = MenuScreen.card(_main, 16)
	(left.get_parent() as Control).custom_minimum_size.x = 430
	var list_scroll := ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(list_scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 10)
	list_scroll.add_child(_rows_box)
	_main_status = _muted("", 15)
	left.add_child(_main_status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	left.add_child(actions)
	var new_deck: Button = _web_button("NEW DECK", &"Gold", 22, "decks/new", "Build a deck in the web app's deck builder; it lands in the shared folder and shows here.")
	new_deck.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(new_deck)
	var paste := Button.new()
	paste.text = "PASTE A CODE"
	paste.add_theme_font_size_override("font_size", 18)
	paste.pressed.connect(_open_paste)
	actions.add_child(paste)

	var right: VBoxContainer = MenuScreen.card(_main, 24, true)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 14)
	scroll.add_child(_detail)


## With no deck at all: the two ways to get one, as the two cards on the Online screen.
func _build_empty(content: VBoxContainer) -> void:
	_empty = HBoxContainer.new()
	_empty.add_theme_constant_override("separation", 18)
	content.add_child(_empty)
	var build: VBoxContainer = MenuScreen.card(_empty, 34, true)
	build.custom_minimum_size.y = 520
	build.add_theme_constant_override("separation", 16)
	build.add_child(UiTheme.label("BUILD", 56))
	build.add_child(_muted("Pick three heroes and your cards in the deck builder. The deck shows here by itself.", 20))
	build.add_child(_web_button("OPEN THE DECK BUILDER", &"Primary", 36, "decks/new", "Build a deck in the web app's deck builder."))
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	build.add_child(gap)
	build.add_child(_muted("No deck? New Match deals you a Random Deck.", 16))
	_empty_paste = MenuScreen.card(_empty, 34, true)
	_empty_paste.add_theme_constant_override("separation", 16)


func _muted(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Palette.MUTED)
	l.add_theme_font_size_override("font_size", font_size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A web app link dressed as one of the screen's real buttons.
func _web_button(text: String, variation: StringName, font_size: int, page: String, what: String) -> Button:
	var b: Button = WebApp.link(text, page, what)
	b.theme_type_variation = variation
	b.add_theme_font_size_override("font_size", font_size)
	if variation == &"Gold":
		for state: String in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			b.add_theme_color_override(state, Color.BLACK)
	return b


## Reads the decks again and selects the one called `select` (or the first).
func _reload(select: String) -> void:
	decks = DeckStore.load_all(db.root_dir)
	_fill(select)


func _fill(select: String) -> void:
	# A message from just before this (imported, deleted) stays on whichever view comes up.
	var said: String = _status.text if _status != null else ""
	_main.visible = not decks.is_empty()
	_empty.visible = decks.is_empty()
	if decks.is_empty():
		_paste_form(_empty_paste, said)
		return
	_status = _main_status
	_status.text = said
	for c: Node in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()
	_rows.clear()
	var pick: int = 0
	for i: int in decks.size():
		_rows.append(_row(i))
		if str(decks[i]["name"]) == select:
			pick = i
	_show(pick)


func _problems(d: Dictionary) -> PackedStringArray:
	return DeckCode.check(db.catalog, JsonUtil.as_strings(d["heroes"]), JsonUtil.as_dict(d["cards"]))


func _total(cards: Dictionary) -> int:
	var n: int = 0
	for k: Variant in cards:
		n += JsonUtil.as_int(cards[k])
	return n


## One deck in the list: its three heroes, its name, and a line on it. Clicking shows it.
func _row(i: int) -> PanelContainer:
	var d: Dictionary = decks[i]
	var panel := PanelContainer.new()
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_rows_box.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var slices := HBoxContainer.new()
	slices.add_theme_constant_override("separation", -8)
	row.add_child(slices)
	for id: String in JsonUtil.as_strings(d["heroes"]):
		slices.add_child(_mini_slice(id))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var name_l: Label = UiTheme.label(str(d["name"]).to_upper(), 22)
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(name_l)
	var line: Label = _muted("%d cards%s" % [_total(JsonUtil.as_dict(d["cards"])), "  ·  imported" if JsonUtil.as_bool(d["local"]) else ""], 13)
	if not _problems(d).is_empty():
		line.text = "Breaks the deck rules"
		line.add_theme_color_override("font_color", Palette.GOLD)
	col.add_child(line)
	panel.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_show(i))
	panel.mouse_entered.connect(func() -> void: _style_row(panel, i, true))
	panel.mouse_exited.connect(func() -> void: _style_row(panel, i, false))
	_style_row(panel, i, false)
	return panel


func _style_row(panel: PanelContainer, i: int, hover: bool) -> void:
	var on: bool = i == _selected
	panel.add_theme_stylebox_override("panel", UiTheme.box(Palette.SURFACE_2 if on or hover else Palette.PANEL_SOLID, 0,
		Palette.GOLD if on else Color(0, 0, 0, 0), 12, 10))


func _mini_slice(id: String) -> HeroSlice:
	var s := HeroSlice.new()
	s.custom_minimum_size = Vector2(68, 46)
	s.art_w = 68.0
	s.set_mirrored(false)
	var card: CardDef = db.catalog.get_card(id)
	s.art = db.thumb(id) if card != null else null
	s.art_region = HeroSlice.region_for(s.art)
	s.art_fallback = Palette.hero(card.color if card != null else "").darkened(0.3)
	s.color_edge = Palette.hero(card.color if card != null else "")
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	return s


func _clear_detail() -> void:
	for c: Node in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()


func _show(i: int) -> void:
	_selected = i
	for r: int in _rows.size():
		_style_row(_rows[r], r, false)
	_clear_detail()
	var d: Dictionary = decks[i]
	var heroes: PackedStringArray = JsonUtil.as_strings(d["heroes"])
	var cards: Dictionary = JsonUtil.as_dict(d["cards"])
	var problems: PackedStringArray = _problems(d)
	_detail_head(d, heroes, cards, problems.is_empty())

	var notes := PackedStringArray()
	if JsonUtil.as_bool(d["local"]):
		notes.append("Imported on this computer")
	var v: int = JsonUtil.as_int(d.get("version", 0))
	if v > db.version:
		notes.append("Built with cards v%d, you have v%d: sync the shared folder" % [v, db.version])
	if not notes.is_empty():
		_detail.add_child(_muted("  ·  ".join(notes), 15))
	if not problems.is_empty():
		var warn: Label = _muted("Breaks the deck rules: " + "; ".join(problems), 16)
		warn.add_theme_color_override("font_color", Palette.GOLD)
		_detail.add_child(warn)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	_detail.add_child(top)
	for id: String in heroes:
		top.add_child(_card_tile(id, 1, HERO_CARD_H))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	top.add_child(_type_counts(cards))

	var wall := HFlowContainer.new()
	wall.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wall.add_theme_constant_override("h_separation", 8)
	wall.add_theme_constant_override("v_separation", 8)
	_detail.add_child(wall)
	for id: String in _card_order(cards):
		wall.add_child(_card_tile(id, JsonUtil.as_int(cards[id]), CARD_H))


func _detail_head(d: Dictionary, heroes: PackedStringArray, cards: Dictionary, legal: bool) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	_detail.add_child(head)
	var title: String = str(d["name"]).to_upper()
	head.add_child(UiTheme.label(title, 48 if title.length() <= 22 else 32))
	var chip: UiShape = UiShape.chip("LEGAL" if legal else "NOT LEGAL", LEGAL_GREEN if legal else Palette.ACCENT, Color.BLACK if legal else Palette.FG, 16, 28.0, 11.0)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(chip)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var copy := Button.new()
	copy.text = "COPY CODE"
	copy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy.add_theme_font_size_override("font_size", 20)
	copy.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(DeckCode.encode(heroes, cards, db.version))
		copy.text = "COPIED"
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			if is_instance_valid(copy):
				copy.text = "COPY CODE"))
	head.add_child(copy)
	if JsonUtil.as_bool(d["local"]):
		head.add_child(_delete_button(d))
	else:
		# Shared decks are the web app's files: decks/<slug>.json opens as #/decks/<slug>.
		var edit: Button = _web_button("EDIT", &"", 20, "decks/" + str(d["path"]).get_file().get_basename(), "Edit this deck in the web app's deck builder.")
		edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(edit)


## Two clicks, as on Replays: the first asks, the second deletes.
func _delete_button(d: Dictionary) -> Button:
	var del := Button.new()
	del.text = "DELETE"
	del.theme_type_variation = &"Ghost"
	del.tooltip_text = "Imported decks only; shared decks are edited in the web app"
	del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	del.pressed.connect(func() -> void:
		if del.text == "DELETE":
			del.text = "SURE?"
			del.add_theme_color_override("font_color", Palette.ACCENT)
			return
		if DeckStore.delete_local(str(d["path"])):
			_status.text = "%s deleted." % str(d["name"])
			_reload(""))
	return del


func _type_counts(cards: Dictionary) -> VBoxContainer:
	var counts := VBoxContainer.new()
	counts.add_theme_constant_override("separation", 2)
	counts.alignment = BoxContainer.ALIGNMENT_CENTER
	counts.custom_minimum_size.x = 170
	for t: String in TYPE_ORDER:
		var n: int = 0
		for k: Variant in cards:
			var c: CardDef = db.catalog.get_card(str(k))
			if c != null and c.type == t:
				n += JsonUtil.as_int(cards[k])
		var line := HBoxContainer.new()
		counts.add_child(line)
		var l: Label = _muted(t, 17)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(l)
		line.add_child(UiTheme.label(str(n), 26, Palette.GOLD))
	return counts


## The deck's cards in order: by type, then by cost. A card not in cards.json comes last.
func _card_order(cards: Dictionary) -> Array[String]:
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
	var out: Array[String] = []
	for t: String in order:
		if not by_type.has(t):
			continue
		var ids: Array = by_type[t]
		ids.sort_custom(func(a: Variant, b: Variant) -> bool: return _cost(str(a)) < _cost(str(b)) or (_cost(str(a)) == _cost(str(b)) and str(a) < str(b)))
		for id: Variant in ids:
			out.append(str(id))
	return out


func _cost(id: String) -> int:
	var c: CardDef = db.catalog.get_card(id)
	return c.cost if c != null else 99


## A card's picture `h` tall (or its name on a coloured tile) with the copy count in the corner.
func _card_tile(id: String, count: int, h: float) -> Control:
	var c: CardDef = db.catalog.get_card(id)
	var box := Control.new()
	var tex: Texture2D = db.thumb(id)
	var w: float = h * float(tex.get_width()) / float(tex.get_height()) if tex != null else h * 0.71
	box.custom_minimum_size = Vector2(w, h)
	if tex != null:
		var img := TextureRect.new()
		img.texture = tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.add_child(img)
	else:
		var tile := ColorRect.new()
		tile.color = Palette.hero(c.color if c != null else "").darkened(0.5)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		var chip: UiShape = UiShape.chip("×%d" % count, Palette.GOLD, Color.BLACK, 15, 24.0, 8.0)
		chip.position = Vector2(w - chip.custom_minimum_size.x, h - 24.0)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(chip)
	if c == null:
		box.tooltip_text = "%s is not in cards.json (sync the shared folder)" % id
	else:
		box.tooltip_text = "%s  ·  %s %s%s\n%s" % [c.name, c.color, c.type, "  ·  cost %d" % c.cost if c.type != "Hero" else "", c.text]
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	return box


# --- import -------------------------------------------------------------------------------

## The paste form in `parent`, in place of what was there; `keep` is shown in its message line.
func _paste_form(parent: VBoxContainer, keep: String = "") -> void:
	for c: Node in parent.get_children():
		parent.remove_child(c)
		c.queue_free()
	parent.add_child(UiTheme.label("PASTE", 56))
	parent.add_child(_muted("Got a deck code from a friend?", 20))
	parent.add_child(UiTheme.label("DECK CODE", 15, Palette.GOLD))
	_code_in = LineEdit.new()
	_code_in.placeholder_text = "EB1|v%d|…" % db.version
	_code_in.add_theme_font_size_override("font_size", 22)
	_code_in.text_changed.connect(func(_t: String) -> void: _preview_code())
	parent.add_child(_code_in)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	parent.add_child(line)
	_name_in = LineEdit.new()
	_name_in.placeholder_text = NAME_HINT
	_name_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_in.add_theme_font_size_override("font_size", 22)
	_name_in.text_submitted.connect(func(_t: String) -> void: _import())
	line.add_child(_name_in)
	var import_btn := Button.new()
	import_btn.text = "IMPORT"
	import_btn.theme_type_variation = &"Gold"
	import_btn.add_theme_font_size_override("font_size", 26)
	import_btn.pressed.connect(_import)
	line.add_child(import_btn)
	_status = _muted(keep, 16)
	parent.add_child(_status)


## PASTE A CODE: the form in a small window over the screen; a click outside it closes it.
func _open_paste() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_close_paste())
	add_child(dim)
	_paste_layer = dim
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(center)
	var form: VBoxContainer = MenuScreen.card(center, 34)
	form.custom_minimum_size.x = 640
	form.add_theme_constant_override("separation", 16)
	_paste_form(form)
	_code_in.grab_focus()


func _close_paste() -> void:
	if _paste_layer != null:
		_paste_layer.queue_free()
		_paste_layer = null
	_status = _main_status
	_status.text = ""


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
	var deck_name: String = _name_in.text.strip_edges()
	if deck_name.is_empty():
		deck_name = _name_in.placeholder_text if _name_in.placeholder_text != NAME_HINT else "Imported deck"
	for x: Dictionary in decks:
		if str(x["name"]) == deck_name and not JsonUtil.as_bool(x["local"]):
			_status.text = "The shared folder already has a deck called %s; pick another name." % deck_name
			return
	var heroes: PackedStringArray = d["heroes"]
	var cards: Dictionary = d["cards"]
	var version: int = JsonUtil.as_int(d["version"])
	var replaced: bool = DeckStore.local_exists(deck_name)
	if DeckStore.save_local(deck_name, heroes, cards, version).is_empty():
		_status.text = "Could not save the deck."
		return
	var problems: PackedStringArray = DeckCode.check(db.catalog, heroes, cards)
	var said: String = "%s %s.%s" % [deck_name, "replaced" if replaced else "imported",
		"" if problems.is_empty() else " It breaks the deck rules, so Play will not take it as it is."]
	if version > db.version:
		said += " Built with cards v%d, you have v%d: sync the shared folder." % [version, db.version]
	if _paste_layer != null:
		_close_paste()
	_status.text = said
	_reload(deck_name)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and GameSettings.logical_key((event as InputEventKey).keycode) == KEY_ESCAPE:
		if _paste_layer != null:
			_close_paste()
		else:
			_back()


# --- screenshot helpers -------------------------------------------------------------------

## Shows a few random decks (without saving them): nothing is written to this computer.
func demo_decks() -> void:
	decks.clear()
	for i: int in 5:
		var rng := RandomNumberGenerator.new()
		rng.seed = 33 - i * 7
		var d: Dictionary = DeckCode.random_deck(db.catalog, rng)
		decks.append({"name": "Deck %d" % (i + 1), "heroes": d["heroes"], "cards": d["cards"], "local": i == 4,
			"path": "", "version": db.version})
	_fill("")


## The same, with the paste window open and a deck code in it.
func demo_paste() -> void:
	demo_decks()
	_open_paste()
	_code_in.text = DeckCode.encode(JsonUtil.as_strings(decks[0]["heroes"]), JsonUtil.as_dict(decks[0]["cards"]), db.version)
	_preview_code()
