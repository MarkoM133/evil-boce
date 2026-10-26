class_name SideboardPanel
extends CanvasLayer
## Best of 3 (GDD 13): the sideboard on a dimmed screen, two columns. To build it (before a
## series): every card these heroes may take on the left, the sideboard (up to 10) on the
## right; a click adds or takes away one copy. To swap (between games): the deck on the left,
## the sideboard on the right; pick a card on one side, then one on the other, and they trade
## places, up to five swaps a break and never past a card's limit. DONE hands the result to
## `on_done` (the sideboard, or the deck's cards).

const ROW_H: float = 34.0

var db: CardDb
var heroes: PackedStringArray = PackedStringArray()
var swapping: bool = false
var on_done: Callable
## Build: the deck (for "in deck" notes) and the sideboard being built.
var deck_cards: Dictionary = {}
var side: Dictionary = {}
## Swap: the deck and sideboard as the break began, and the working copies.
var base_deck: Dictionary = {}
var base_side: Dictionary = {}
var work_deck: Dictionary = {}
var work_side: Dictionary = {}
var _picked: String = ""
var _picked_left: bool = true

var _left: VBoxContainer
var _right: VBoxContainer
var _left_title: Label
var _right_title: Label
var _foot: Label


## Builds a sideboard for `heroes`; `on_done` gets the sideboard (id -> copies).
static func open_build(parent: Node, db_: CardDb, heroes_: PackedStringArray, deck_cards_: Dictionary,
		side_: Dictionary, on_done_: Callable) -> SideboardPanel:
	var p := SideboardPanel.new()
	p.db = db_
	p.heroes = heroes_
	p.deck_cards = deck_cards_
	p.side = side_.duplicate()
	p.on_done = on_done_
	parent.add_child(p)
	p._build("Sideboard", "Up to %d cards these heroes may take; between games you swap up to %d of them in." % [MatchSeries.SIDEBOARD, MatchSeries.SWAPS])
	return p


## Swaps cards between the deck and the sideboard; `on_done` gets the deck's cards.
static func open_swap(parent: Node, db_: CardDb, heroes_: PackedStringArray, base_deck_: Dictionary,
		base_side_: Dictionary, deck_now: Dictionary, on_done_: Callable) -> SideboardPanel:
	var p := SideboardPanel.new()
	p.db = db_
	p.heroes = heroes_
	p.swapping = true
	p.base_deck = base_deck_.duplicate()
	p.base_side = base_side_.duplicate()
	p.work_deck = deck_now.duplicate()
	p.work_side = {}
	# The working sideboard: what deck and sideboard hold together, less the deck now.
	var pool: Dictionary = base_deck_.duplicate()
	for k: Variant in base_side_:
		pool[k] = JsonUtil.as_int(pool.get(k, 0)) + JsonUtil.as_int(base_side_[k])
	for k: Variant in pool:
		var left: int = JsonUtil.as_int(pool[k]) - JsonUtil.as_int(deck_now.get(k, 0))
		if left > 0:
			p.work_side[k] = left
	p.on_done = on_done_
	parent.add_child(p)
	p._build("Swap cards", "Click a card in the deck, then one in the sideboard: they trade places. Up to %d swaps before this game." % MatchSeries.SWAPS)
	return p


func _build(title: String, subtitle: String) -> void:
	layer = 20
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.get_theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var panel := PanelContainer.new()
	var sb: StyleBoxFlat = UiTheme.box(Palette.PANEL_SOLID, 0, Color(0, 0, 0, 0), 28, 22)
	sb.border_color = Palette.ACCENT
	sb.border_width_top = 4
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(1060, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	col.add_child(UiTheme.label(title.to_upper(), 44))
	var sub := Label.new()
	sub.text = subtitle
	sub.add_theme_color_override("font_color", Palette.MUTED)
	sub.add_theme_font_size_override("font_size", 15)
	col.add_child(sub)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	col.add_child(cols)
	var lc: Array = _column(cols)
	_left_title = lc[0]
	_left = lc[1]
	var rc: Array = _column(cols)
	_right_title = rc[0]
	_right = rc[1]
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	_foot = UiTheme.label("", 18, Palette.MUTED)
	_foot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_foot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	foot.add_child(_foot)
	var reset := Button.new()
	reset.text = "RESET" if swapping else "CLEAR"
	reset.theme_type_variation = &"Ghost"
	reset.add_theme_font_size_override("font_size", 18)
	reset.pressed.connect(func() -> void:
		if swapping:
			work_deck = base_deck.duplicate()
			work_side = base_side.duplicate()
		else:
			side.clear()
		_picked = ""
		_fill())
	foot.add_child(reset)
	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.add_theme_font_size_override("font_size", 18)
	cancel.pressed.connect(queue_free)
	foot.add_child(cancel)
	var done := Button.new()
	done.text = "DONE"
	done.theme_type_variation = &"Primary"
	done.add_theme_font_size_override("font_size", 24)
	done.custom_minimum_size = Vector2(170, 0)
	done.pressed.connect(func() -> void:
		on_done.call(work_deck.duplicate() if swapping else side.duplicate())
		queue_free())
	foot.add_child(done)
	_fill()


func _column(parent: Control) -> Array:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	var title: Label = UiTheme.label("", 16, Palette.GOLD)
	box.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 470)
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)
	return [title, list]


static func _total(d: Dictionary) -> int:
	var n: int = 0
	for k: Variant in d:
		n += JsonUtil.as_int(d[k])
	return n


func _fill() -> void:
	for list: VBoxContainer in [_left, _right]:
		for n: Node in list.get_children():
			n.queue_free()
	if swapping:
		_left_title.text = "DECK  ·  %d CARDS" % _total(work_deck)
		_right_title.text = "SIDEBOARD  ·  %d" % _total(work_side)
		for id: String in _sorted(work_deck):
			_left.add_child(_row(id, JsonUtil.as_int(work_deck[id]), "", true))
		for id: String in _sorted(work_side):
			_right.add_child(_row(id, JsonUtil.as_int(work_side[id]), "", false))
		var used: int = MatchSeries._swaps(base_deck, work_deck)
		_foot.text = "SWAPS  %d / %d" % [used, MatchSeries.SWAPS] + (("  ·  PICKED: %s" % _name(_picked)) if not _picked.is_empty() else "")
		_foot.add_theme_color_override("font_color", Palette.GOLD if used > 0 else Palette.MUTED)
		return
	var total: int = _total(side)
	_left_title.text = "CARDS THESE HEROES MAY TAKE"
	_right_title.text = "SIDEBOARD  ·  %d / %d" % [total, MatchSeries.SIDEBOARD]
	var pool: Array[CardDef] = []
	for id: String in heroes:
		var h: CardDef = db.catalog.get_card(id)
		if h != null:
			pool.append(h)
	for c: CardDef in DeckCode._pool(db.catalog, pool):
		var inside: int = JsonUtil.as_int(deck_cards.get(c.id, 0))
		_left.add_child(_row(c.id, 0, ("in deck %d×" % inside) if inside > 0 else "", true))
	for id: String in _sorted(side):
		_right.add_child(_row(id, JsonUtil.as_int(side[id]), "", false))
	_foot.text = "%d of %d chosen" % [total, MatchSeries.SIDEBOARD]
	_foot.add_theme_color_override("font_color", Palette.MUTED)


func _sorted(d: Dictionary) -> PackedStringArray:
	var ids: Array = d.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return _name(str(a)) < _name(str(b)))
	var out := PackedStringArray()
	for x: Variant in ids:
		if JsonUtil.as_int(d[x]) > 0:
			out.append(str(x))
	return out


func _name(id: String) -> String:
	var c: CardDef = db.catalog.get_card(id)
	return c.name if c != null else id


## One card as a row: colour stripe, copies, name, type and a note; a click acts on it.
func _row(id: String, copies: int, note: String, left: bool) -> Control:
	var c: CardDef = db.catalog.get_card(id)
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.add_theme_font_size_override("font_size", 16)
	var head: String = ("%d×  " % copies) if copies > 0 else ""
	b.text = "     %s%s   ·   %s%s" % [head, c.name if c != null else id, c.type if c != null else "",
		("   ·   " + note) if not note.is_empty() else ""]
	b.tooltip_text = ("%s  ·  %s %s  ·  cost %d\n%s" % [c.name, c.color, c.type, c.cost, c.text]) if c != null else id
	if swapping and id == _picked and left == _picked_left:
		b.theme_type_variation = &"Gold"
	var stripe := ColorRect.new()
	stripe.color = Palette.hero(c.color if c != null else "")
	stripe.position = Vector2(8, 7)
	stripe.size = Vector2(5, ROW_H - 14)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(stripe)
	b.pressed.connect(func() -> void: _click(id, left))
	return b


func _click(id: String, left: bool) -> void:
	if not swapping:
		_build_click(id, left)
		return
	if _picked.is_empty() or _picked_left == left:
		_picked = "" if _picked == id and _picked_left == left else id
		_picked_left = left
		_fill()
		return
	var out_id: String = _picked if _picked_left else id
	var in_id: String = id if _picked_left else _picked
	_picked = ""
	var err: String = _swap(out_id, in_id)
	_fill()
	if not err.is_empty():
		_foot.text = err.to_upper()
		_foot.add_theme_color_override("font_color", Palette.ACCENT_HOVER)


## One copy of `out_id` leaves the deck, one of `in_id` comes in; "" or why not.
func _swap(out_id: String, in_id: String) -> String:
	if out_id == in_id:
		return ""
	var c: CardDef = db.catalog.get_card(in_id)
	var deck: Dictionary = work_deck.duplicate()
	deck[out_id] = JsonUtil.as_int(deck.get(out_id, 0)) - 1
	if JsonUtil.as_int(deck[out_id]) <= 0:
		deck.erase(out_id)
	deck[in_id] = JsonUtil.as_int(deck.get(in_id, 0)) + 1
	if c != null and JsonUtil.as_int(deck[in_id]) > DeckCode.LIMITS.get(c.type, 0):
		return "%s: at most %d in a deck" % [c.name, DeckCode.LIMITS.get(c.type, 0)]
	if MatchSeries._swaps(base_deck, deck) > MatchSeries.SWAPS:
		return "at most %d swaps before this game" % MatchSeries.SWAPS
	work_deck = deck
	work_side[in_id] = JsonUtil.as_int(work_side.get(in_id, 0)) - 1
	if JsonUtil.as_int(work_side[in_id]) <= 0:
		work_side.erase(in_id)
	work_side[out_id] = JsonUtil.as_int(work_side.get(out_id, 0)) + 1
	return ""


func _build_click(id: String, left: bool) -> void:
	var c: CardDef = db.catalog.get_card(id)
	if left:
		if _total(side) >= MatchSeries.SIDEBOARD:
			_foot.text = "THE SIDEBOARD IS FULL"
			return
		if c != null and JsonUtil.as_int(side.get(id, 0)) >= DeckCode.LIMITS.get(c.type, 0):
			_foot.text = "%s: AT MOST %d" % [c.name.to_upper(), DeckCode.LIMITS.get(c.type, 0)]
			return
		side[id] = JsonUtil.as_int(side.get(id, 0)) + 1
	else:
		side[id] = JsonUtil.as_int(side.get(id, 0)) - 1
		if JsonUtil.as_int(side[id]) <= 0:
			side.erase(id)
	_fill()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and GameSettings.logical_key((event as InputEventKey).keycode) == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
