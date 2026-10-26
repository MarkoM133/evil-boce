class_name PlayerCard
extends PanelContainer
## One player's side before a match (Play setup, online lobby): the deck as three hero slices
## with ‹ › to flip through the saved decks (or Random), three stage tiles with the card images
## and two cores of each kind, each picked from a popup or left Random (GDD 7). Edits `loadout`
## and `deck_index` in place and says `changed`.

signal changed

const KIND_COLORS: Dictionary[String, Color] = {"Buff": Color("23b14d"), "Major": Color("f4b62a"), "Debuff": Color("e3120b")}

var db: CardDb
var decks: Array[Dictionary] = []
## 0 = random, else decks[deck_index - 1].
var deck_index: int = 0
## Random deck: the leader picked for it ("" = random heroes) and the deck built around it
## ({} = drawn when the match starts).
var leader: String = ""
var built: Dictionary = {}
var loadout: Loadout = Loadout.new()
var team: int = 0
## Extra controls in the header (the opponent type in Play setup).
var header_extra: HBoxContainer

var _title: String = ""
## Chaos: deck, stages and cores are random and cannot be changed (set_locked_random).
var _locked: bool = false
## A series (Best of 3): the deck of game one stays; only stages and cores are picked again.
var _deck_locked: bool = false
var _body: VBoxContainer
var _popup: PopupPanel
var _sb: StyleBoxFlat
var _chip: UiShape
## Someone else's side, only shown (online lobby): {deck_name, heroes, stages, cores}, ids "" for random.
var _shown: Dictionary = {}
var _view_only: bool = false


func setup(db_: CardDb, decks_: Array[Dictionary], title: String, team_: int, deck_name: String, start: Loadout) -> void:
	db = db_
	decks = decks_
	_title = title
	team = team_
	loadout = start
	deck_index = 0
	for i: int in decks.size():
		if str(decks[i]["name"]) == deck_name:
			deck_index = i + 1
	_sb = UiTheme.box(Palette.PANEL_SOLID, 0, Color(0, 0, 0, 0), 22, 18)
	_sb.border_color = Palette.team(team)
	_sb.border_width_top = 4
	add_theme_stylebox_override("panel", _sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	_chip = UiShape.chip(_title.to_upper(), Palette.team(team), Palette.FG, 22, 34.0, 18.0)
	head.add_child(_chip)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	header_extra = HBoxContainer.new()
	header_extra.add_theme_constant_override("separation", 4)
	head.add_child(header_extra)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	col.add_child(_body)
	_popup = PopupPanel.new()
	_popup.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.03, 0.03, 0.98), 0, Palette.GOLD, 16, 14))
	add_child(_popup)
	_rebuild()


## A new name and team colour in the header (online: your seat is known after joining).
func set_header(title: String, team_: int) -> void:
	if title == _title and team_ == team:
		return
	_title = title
	team = team_
	_sb.border_color = Palette.team(team)
	queue_redraw()
	var head: Node = _chip.get_parent()
	var chip: UiShape = UiShape.chip(_title.to_upper(), Palette.team(team), Palette.FG, 22, 34.0, 18.0)
	head.add_child(chip)
	head.move_child(chip, 0)
	_chip.queue_free()
	_chip = chip


## Shows another player's picks without letting anyone change them: `picks_` is
## {deck_name, heroes, stages, cores} with "" (or no heroes) for random.
func show_only(picks_: Dictionary) -> void:
	if _view_only and picks_ == _shown:
		return
	_view_only = true
	_shown = picks_
	loadout = Loadout.new()
	var st: PackedStringArray = JsonUtil.as_strings(picks_.get("stages", []))
	var co: PackedStringArray = JsonUtil.as_strings(picks_.get("cores", []))
	for i: int in mini(st.size(), Loadout.STAGES):
		loadout.stages[i] = st[i]
	for i: int in mini(co.size(), loadout.cores.size()):
		loadout.cores[i] = co[i]
	_rebuild()


## This side's picks as the other players see them (see `show_only`).
func picks() -> Dictionary:
	var d: Dictionary = saved_deck()
	return {"deck_name": str(d.get("name", "")), "heroes": JsonUtil.as_strings(d.get("heroes", [])),
		"stages": Array(loadout.stages), "cores": Array(loadout.cores)}


## A series (Best of 3, GDD 13): this deck ({name, heroes, cards}) is played again; stages and
## cores are still the player's to pick.
func set_fixed_deck(d: Dictionary) -> void:
	_deck_locked = true
	deck_index = 0
	built = d
	leader = ""
	_rebuild()


func deck_fixed() -> bool:
	return _deck_locked


## Chaos (GDD 13): everything random, nothing to pick. Says whether that changed anything.
func set_locked_random(on: bool) -> bool:
	if on == _locked:
		return false
	_locked = on
	if on:
		deck_index = 0
		built = {}
		leader = ""
		loadout = Loadout.random()
	_rebuild()
	return true


## The saved deck picked, the random deck built here, or {} for one drawn at the start.
func saved_deck() -> Dictionary:
	return decks[deck_index - 1] if deck_index > 0 and deck_index <= decks.size() else built


func _shown_deck_name() -> String:
	var n: String = str(_shown.get("deck_name", ""))
	return n if not n.is_empty() else "Random deck"


func deck_name() -> String:
	var d: Dictionary = saved_deck()
	return str(d["name"]) if not d.is_empty() else "Random deck"


## What keeps this side from starting: the deck rules for a saved deck, doubles in the picks.
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	var d: Dictionary = saved_deck()
	if not d.is_empty() and db != null:
		out.append_array(DeckCode.check(db.catalog, JsonUtil.as_strings(d["heroes"]), JsonUtil.as_dict(d["cards"])))
	if db != null:
		out.append_array(loadout.problems(db.catalog))
	return out


func _rebuild() -> void:
	for c: Node in _body.get_children():
		c.queue_free()
	# Deck: name with arrows, then the three heroes.
	var deck_row := HBoxContainer.new()
	deck_row.add_theme_constant_override("separation", 8)
	_body.add_child(deck_row)
	var prev := Button.new()
	prev.text = "‹"
	prev.add_theme_font_size_override("font_size", 26)
	prev.tooltip_text = "Previous deck"
	prev.pressed.connect(func() -> void: _flip(-1))
	var fixed: bool = _view_only or _locked
	var deck_fixed_: bool = fixed or _deck_locked
	if not deck_fixed_:
		deck_row.add_child(prev)
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_theme_constant_override("separation", 0)
	deck_row.add_child(name_box)
	var caption := HBoxContainer.new()
	caption.add_theme_constant_override("separation", 10)
	name_box.add_child(caption)
	caption.add_child(UiTheme.label("DECK", 13, Palette.GOLD))
	if not _view_only:
		var builder: Button = WebApp.link("DECK BUILDER", "decks/new", "Build or change decks in the web app; saved decks show here.")
		builder.visible = not _locked and not _deck_locked
		builder.add_theme_font_size_override("font_size", 12)
		builder.add_theme_constant_override("h_separation", 2)
		builder.custom_minimum_size = Vector2(0, 18)
		caption.add_child(builder)
	var name_l: Label = UiTheme.label(_shown_deck_name().to_upper() if _view_only else deck_name().to_upper(), 28)
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_box.add_child(name_l)
	if _locked:
		var chaos: Label = UiTheme.label("CHAOS  ·  ALL RANDOM", 12, Palette.GOLD)
		chaos.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		caption.add_child(chaos)
	if _deck_locked:
		var same: Label = UiTheme.label("SERIES  ·  THE DECK STAYS", 12, Palette.GOLD)
		same.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		caption.add_child(same)
	if deck_index == 0 and not deck_fixed_:
		var roll := Button.new()
		roll.text = "REROLL" if not built.is_empty() else "BUILD"
		roll.add_theme_font_size_override("font_size", 18)
		roll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		roll.tooltip_text = "Build a random deck now (around the leader, if you picked one) and see it before the match"
		roll.pressed.connect(_build_random)
		deck_row.add_child(roll)
	var next := Button.new()
	next.text = "›"
	next.add_theme_font_size_override("font_size", 26)
	next.tooltip_text = "Next deck"
	next.pressed.connect(func() -> void: _flip(1))
	if not deck_fixed_:
		deck_row.add_child(next)
	var heroes := HBoxContainer.new()
	heroes.add_theme_constant_override("separation", 6)
	_body.add_child(heroes)
	var ids: PackedStringArray = JsonUtil.as_strings((_shown if _view_only else saved_deck()).get("heroes", []))
	for i: int in DeckCode.HERO_COUNT:
		var id: String = ids[i] if i < ids.size() else ""
		if i == 0 and deck_index == 0 and not deck_fixed_ and id.is_empty():
			id = leader
		heroes.add_child(_hero_tile(id, i == 0 and deck_index == 0 and not deck_fixed_))

	# Stages.
	_body.add_child(UiTheme.label("STAGES", 13, Palette.GOLD))
	var stages := HBoxContainer.new()
	stages.add_theme_constant_override("separation", 8)
	_body.add_child(stages)
	for i: int in Loadout.STAGES:
		stages.add_child(_stage_tile(i))

	# Cores: two of each kind.
	_body.add_child(UiTheme.label("CORES", 13, Palette.GOLD))
	var cores := HBoxContainer.new()
	cores.add_theme_constant_override("separation", 22)
	_body.add_child(cores)
	for k: int in Loadout.CORE_KINDS.size():
		var group := VBoxContainer.new()
		group.add_theme_constant_override("separation", 4)
		cores.add_child(group)
		var kind: String = Loadout.CORE_KINDS[k]
		var lab := Label.new()
		lab.text = kind.to_upper()
		lab.add_theme_color_override("font_color", Palette.MUTED)
		lab.add_theme_font_size_override("font_size", 12)
		group.add_child(lab)
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 6)
		group.add_child(pair)
		for j: int in Loadout.CORES_PER_KIND:
			pair.add_child(_core_button(k * Loadout.CORES_PER_KIND + j))
	var all_random := Button.new()
	all_random.text = "ALL RANDOM"
	all_random.theme_type_variation = &"Ghost"
	all_random.add_theme_font_size_override("font_size", 15)
	all_random.size_flags_horizontal = Control.SIZE_SHRINK_END
	all_random.size_flags_vertical = Control.SIZE_SHRINK_END
	all_random.pressed.connect(func() -> void:
		loadout = Loadout.random()
		_changed())
	if not fixed:
		cores.add_child(all_random)
	else:
		all_random.free()

	var probs: PackedStringArray = problems() if not _view_only else PackedStringArray()
	if not probs.is_empty():
		var warn := Label.new()
		warn.text = "Fix: " + "; ".join(probs)
		warn.add_theme_color_override("font_color", Palette.GOLD)
		warn.add_theme_font_size_override("font_size", 13)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warn.custom_minimum_size = Vector2(400, 0)
		_body.add_child(warn)


func _flip(step: int) -> void:
	deck_index = posmod(deck_index + step, decks.size() + 1)
	_changed()


func _changed() -> void:
	_rebuild()
	changed.emit()


## A hero of the deck as a slanted art slice with its name; "?" for a random deck. The first
## slot of a random deck is its leader: a click picks it.
func _hero_tile(id: String, leader_slot: bool = false) -> Control:
	var s := HeroSlice.new()
	s.custom_minimum_size = Vector2(176, 70)
	var card: CardDef = db.catalog.get_card(id) if db != null and not id.is_empty() else null
	s.art = db.thumb(id) if card != null else null
	s.art_region = HeroSlice.region_for(s.art)
	s.art_fallback = Palette.hero(card.color if card != null else "").darkened(0.3) if card != null else Palette.SURFACE_2
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	if leader_slot:
		# Over the art, so the name keeps its room.
		var chip: UiShape = UiShape.chip("LEADER", Palette.GOLD, Color.BLACK, 11, 18.0, 7.0)
		chip.position = Vector2(14, -9)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.add_child(chip)
	var l: Label = UiTheme.label(card.name if card != null else "?", 15 if card != null else 30,
		Palette.FG if card != null else Palette.DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	s.content.add_child(l)
	if card != null:
		s.tooltip_text = "%s\n%s" % [card.name, card.text]
	else:
		s.tooltip_text = "Three random heroes, drawn when the match starts"
	if leader_slot:
		s.tooltip_text = "Leader: click to pick the hero the random deck is built around\n\n" + s.tooltip_text
		s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		s.mouse_entered.connect(func() -> void:
			s.outline = Palette.GOLD
			s.queue_redraw())
		s.mouse_exited.connect(func() -> void:
			s.outline = Color(0, 0, 0, 0)
			s.queue_redraw())
		s.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
					and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_pick_leader())
	return s


## A random deck around the leader (or three random heroes), shown now and played as it is.
func _build_random() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	built = DeckCode.random_deck(db.catalog, rng, leader)
	var lead: CardDef = db.catalog.get_card(leader) if not leader.is_empty() else null
	built["name"] = "Random · " + (lead.name if lead != null else "rolled")
	_changed()


func _stage_tile(slot: int) -> Control:
	return card_tile(db, loadout.stages[slot], Vector2(186, 108), Callable() if _view_only or _locked else func() -> void: _pick_stage(slot))


## A card as a slanted picture tile (the art part of its image) with its name, and for a stage
## its terrain; "?" for none. Clicks call `on_click`; hover gives it a straw edge.
static func card_tile(db_: CardDb, id: String, tile: Vector2, on_click: Callable, used: bool = false) -> Control:
	var card: CardDef = db_.catalog.get_card(id) if db_ != null and not id.is_empty() else null
	var s := HeroSlice.new()
	s.custom_minimum_size = tile
	s.art_w = tile.x
	s.set_mirrored(false)
	s.art = db_.thumb(id) if card != null else null
	if s.art != null:
		s.art_region = Rect2(0.08, 0.09, 0.84, 0.42) if s.art.get_height() > s.art.get_width() else HeroSlice.region_for(s.art)
	s.art_fallback = Palette.SURFACE_2
	s.art_tint = Color(0.35, 0.35, 0.35) if used else Color(0.85, 0.85, 0.85)
	var clickable: bool = on_click.is_valid() and not used
	s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_FORBIDDEN if used else Control.CURSOR_ARROW
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.content.add_child(col)
	if card != null:
		if card.terrain != Terrain.Type.NONE:
			var chip: UiShape = UiShape.chip(Terrain.name_of(card.terrain).to_upper(), Palette.GOLD, Color.BLACK, 13, 20.0, 8.0)
			chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			col.add_child(chip)
		var name_l: Label = UiTheme.label(card.name, 19)
		name_l.add_theme_color_override("font_outline_color", Color.BLACK)
		name_l.add_theme_constant_override("outline_size", 6)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(name_l)
		s.tooltip_text = "Already picked" if used else "%s\n%s" % [card.name, card.text]
	else:
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(UiTheme.label("?  RANDOM", 22, Palette.DIM))
		s.tooltip_text = "Random"
	s.mouse_entered.connect(func() -> void:
		if clickable:
			s.outline = Palette.GOLD
			s.queue_redraw())
	s.mouse_exited.connect(func() -> void:
		s.outline = Color(0, 0, 0, 0)
		s.queue_redraw())
	s.gui_input.connect(func(e: InputEvent) -> void:
		if clickable and e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				on_click.call())
	return s


func _core_button(slot: int) -> Button:
	var kind: String = Loadout.core_kind(slot)
	var id: String = loadout.cores[slot]
	var card: CardDef = db.catalog.get_card(id) if db != null and not id.is_empty() else null
	var b := Button.new()
	b.flat = true
	b.custom_minimum_size = Vector2(44, 44)
	var empty := StyleBoxEmpty.new()
	for st: String in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, empty)
	var color: Color = KIND_COLORS.get(kind, Palette.FG)
	var d: UiShape = UiShape.make(UiShape.Kind.DIAMOND, color if card != null else Color(0, 0, 0, 0), Vector2(40, 40),
		kind.left(1) if card != null else "?", 18, Color.BLACK if card != null else Palette.DIM)
	if card == null:
		d.outline = Color(color, 0.7)
	d.position = Vector2(2, 2)
	b.add_child(d)
	b.tooltip_text = ("%s core: %s\n%s" % [kind, card.name, card.text]) if card != null else "%s core: random" % kind
	if not _view_only and not _locked:
		b.pressed.connect(func() -> void: _pick_core(slot))
	else:
		b.mouse_default_cursor_shape = Control.CURSOR_ARROW
	return b


# --- pickers ----------------------------------------------------------------------------

## The leader of a random deck: picking one builds the deck around it, Random goes back to a
## deck drawn at the start.
func _pick_leader() -> void:
	var items: Array[Dictionary] = [{"id": "", "name": "RANDOM", "tex": null}]
	for c: CardDef in db.catalog.of_type("Hero"):
		items.append({"id": c.id, "name": c.name, "tex": db.thumb(c.id)})
	_open_popup("Leader", items, func(id: String) -> void:
		leader = id
		if id.is_empty():
			built = {}
			_changed()
		else:
			_build_random())


func _pick_stage(slot: int) -> void:
	var items: Array[Dictionary] = [{"id": "", "name": "RANDOM", "tex": null}]
	for c: CardDef in db.catalog.of_type("Stage"):
		var terrain: String = Terrain.name_of(c.terrain) if c.terrain != Terrain.Type.NONE else ""
		items.append({"id": c.id, "name": c.name + ("\n" + terrain.to_upper() if not terrain.is_empty() else ""),
			"tex": db.thumb(c.id), "used": loadout.stages.has(c.id) and loadout.stages[slot] != c.id})
	_open_popup("Stage %d" % (slot + 1), items, func(id: String) -> void:
		loadout.stages[slot] = id
		_changed())


func _pick_core(slot: int) -> void:
	var kind: String = Loadout.core_kind(slot)
	var items: Array[Dictionary] = [{"id": "", "name": "RANDOM", "tex": null}]
	for c: CardDef in db.catalog.of_type("Core"):
		if c.kind == kind:
			items.append({"id": c.id, "name": c.name, "tex": db.thumb(c.id), "text": c.text,
				"used": loadout.cores.has(c.id) and loadout.cores[slot] != c.id})
	_open_popup("%s core" % kind, items, func(id: String) -> void:
		loadout.cores[slot] = id
		_changed())


func _open_popup(title: String, items: Array[Dictionary], on_pick: Callable) -> void:
	for c: Node in _popup.get_children():
		c.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_popup.add_child(col)
	col.add_child(UiTheme.label(title.to_upper(), 28))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	col.add_child(grid)
	for it: Dictionary in items:
		var id: String = str(it["id"])
		var pick := func() -> void:
			_popup.hide()
			on_pick.call(id)
		grid.add_child(card_tile(db, id, Vector2(210, 120), pick, JsonUtil.as_bool(it.get("used", false))))
	_popup.popup_centered()
