class_name PlayerCard
extends PanelContainer
## One player's side before a match (Play setup, online lobby): the deck as three hero slices
## with ‹ › to flip through the saved decks (or Random), three stage tiles with the card images
## and two cores of each kind, each picked from a popup or left Random (GDD 7). Edits `loadout`
## and `deck_index` in place and says `changed`.

signal changed

const KIND_COLORS: Dictionary[String, Color] = {"Buff": Color("23b14d"), "Major": Color("f4b62a"), "Debuff": Color("e3120b")}
## A core's value colour in its picker tile, by family (as the core icons: Power gold, Damage red, Knockback blue).
const CORE_FAMILY_COLORS: Dictionary[String, Color] = {"Power": Color("f4c22f"), "Damage": Color("ff5a4a"), "Knockback": Color("4aa3ff")}

var db: CardDb
var decks: Array[Dictionary] = []
## 0 = random, else decks[deck_index - 1].
var deck_index: int = 0
## Random deck: the hero picked for each of its three slots ("" = drawn; Marko 2026-10-26: every
## hero is picked on its own) and the deck built with them ({} = drawn when the match starts).
var chosen: PackedStringArray = PackedStringArray(["", "", ""])
var built: Dictionary = {}
## A random deck built after hero picks is shown only after BUILD / REROLL (the others stay "?").
var _show_built: bool = true
var loadout: Loadout = Loadout.new()
var team: int = 0
## Extra controls in the header (the opponent type in Play setup).
var header_extra: HBoxContainer

var _title: String = ""
## Chaos: deck, stages and cores are random and cannot be changed (set_locked_random).
var _locked: bool = false
## A series (Best of 3): the deck of game one stays; only stages and cores are picked again.
var _deck_locked: bool = false
## Draft: heroes and cards come from the draft; stages and cores are still picked here.
var _drafted: bool = false
## Best of 3: the sideboard of the saved deck (up to 10, remembered by the deck's name), built
## before a series; in a series `swap_handler` opens the swap between games.
var sideboard: Dictionary = {}
var _sideboard_on: bool = false
var swap_handler: Callable = Callable()
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
	var heroes: PackedStringArray = JsonUtil.as_strings(d.get("heroes", []))
	# A random deck drawn after hero picks but not shown yet (no BUILD / REROLL): the other side sees
	# only the picked heroes, the drawn ones stay "?" as they do here (online playtest 2026-11-07:
	# the host saw the guest's drawn heroes the guest had not seen).
	if deck_index == 0 and not _show_built and not d.is_empty():
		heroes = chosen.duplicate()
	# Stages and cores are the player's secret until the match (online playtest 2026-11-07).
	return {"deck_name": str(d.get("name", "")), "heroes": heroes, "stages": [], "cores": [], "hidden": true}


## The random deck as it is now, to be remembered (GameSettings.random_deck); {} for a saved deck.
func random_state() -> Dictionary:
	if deck_index != 0 or _deck_locked or _drafted:
		return {}
	return {"chosen": Array(chosen), "built": built, "shown": _show_built}


## Back to a remembered random deck: the same hero picks and the same drawn deck. Heroes no longer
## in the cards are dropped (and the deck with them).
func restore_random(d: Dictionary) -> void:
	if d.is_empty() or deck_index != 0 or db == null:
		return
	var ids: PackedStringArray = JsonUtil.as_strings(d.get("chosen", []))
	if ids.size() != DeckCode.HERO_COUNT:
		return
	var ok: bool = true
	for i: int in ids.size():
		var c: CardDef = db.catalog.get_card(ids[i]) if not ids[i].is_empty() else null
		if not ids[i].is_empty() and (c == null or c.type != "Hero"):
			ids[i] = ""
			ok = false
	chosen = ids
	var b: Dictionary = JsonUtil.as_dict(d.get("built", {}))
	var heroes: PackedStringArray = JsonUtil.as_strings(b.get("heroes", []))
	var fits: bool = ok and not b.is_empty() and heroes.size() == DeckCode.HERO_COUNT
	for h: String in heroes:
		if db.catalog.get_card(h) == null:
			fits = false
	if fits:
		built = b
		_show_built = JsonUtil.as_bool(d.get("shown", true))
		_changed()
	elif not "".join(chosen).is_empty():
		_build_random(false)
	else:
		built = {}
		_changed()


## A series (Best of 3, GDD 13): this deck ({name, heroes, cards}) is played again; stages and
## cores are still the player's to pick.
func set_fixed_deck(d: Dictionary) -> void:
	_deck_locked = true
	deck_index = 0
	built = d
	chosen = PackedStringArray(["", "", ""])
	_rebuild()


## Draft (GDD 13): no deck to pick, the draft makes it. Says whether that changed anything.
func set_drafted(on: bool) -> bool:
	if on == _drafted:
		return false
	_drafted = on
	if on:
		deck_index = 0
		built = {}
		chosen = PackedStringArray(["", "", ""])
	_rebuild()
	return true


## Best of 3 before a series: the SIDEBOARD button for a saved deck.
func set_sideboard_mode(on: bool) -> void:
	if on == _sideboard_on:
		return
	_sideboard_on = on
	_load_sideboard()
	_rebuild()


func _load_sideboard() -> void:
	var d: Dictionary = saved_deck()
	sideboard = GameSettings.sideboard(str(d.get("name", ""))) if _sideboard_on and deck_index > 0 else {}


func _open_sideboard() -> void:
	var d: Dictionary = saved_deck()
	SideboardPanel.open_build(self, db, JsonUtil.as_strings(d.get("heroes", [])), JsonUtil.as_dict(d.get("cards", {})), sideboard,
		func(side: Dictionary) -> void:
			sideboard = side
			GameSettings.set_sideboard(str(d.get("name", "")), side)
			_changed())


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
		chosen = PackedStringArray(["", "", ""])
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
	if _sideboard_on and not sideboard.is_empty() and db != null:
		var sb_err: String = MatchSeries.sideboard_error(db.catalog, JsonUtil.as_strings(d.get("heroes", [])), sideboard)
		if not sb_err.is_empty():
			out.append("sideboard: " + sb_err)
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
	var deck_fixed_: bool = fixed or _deck_locked or _drafted
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
	var name_l: Label = UiTheme.label("DRAFTED DECK" if _drafted else (_shown_deck_name().to_upper() if _view_only else deck_name().to_upper()), 28)
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_box.add_child(name_l)
	if _locked:
		var chaos: Label = UiTheme.label("CHAOS  ·  ALL RANDOM", 12, Palette.GOLD)
		chaos.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		caption.add_child(chaos)
	if _sideboard_on and deck_index > 0 and not _view_only:
		var sbb := Button.new()
		sbb.text = "SIDEBOARD  %d / %d" % [SideboardPanel._total(sideboard), MatchSeries.SIDEBOARD]
		sbb.add_theme_font_size_override("font_size", 12)
		sbb.custom_minimum_size = Vector2(0, 18)
		sbb.tooltip_text = "Best of 3: up to %d cards to swap in between games" % MatchSeries.SIDEBOARD
		sbb.pressed.connect(_open_sideboard)
		caption.add_child(sbb)
	if swap_handler.is_valid() and _deck_locked and not _view_only:
		var sw := Button.new()
		sw.text = "SWAP CARDS"
		sw.theme_type_variation = &"Gold"
		sw.add_theme_font_size_override("font_size", 12)
		sw.custom_minimum_size = Vector2(0, 18)
		sw.tooltip_text = "Swap up to %d cards with your sideboard before this game" % MatchSeries.SWAPS
		sw.pressed.connect(func() -> void: swap_handler.call())
		caption.add_child(sw)
	if _drafted:
		var dr: Label = UiTheme.label("DRAFT  ·  HEROES AND CARDS ARE DRAFTED", 12, Palette.GOLD)
		dr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		caption.add_child(dr)
	if _deck_locked:
		var same: Label = UiTheme.label("SERIES  ·  THE DECK STAYS", 12, Palette.GOLD)
		same.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		caption.add_child(same)
	# The web app's deck builder, on the right of the deck row (Marko 2026-10-26).
	if not _view_only and not _locked and not _deck_locked and not _drafted:
		var builder: Button = WebApp.link("DECK BUILDER", "decks/new", "Build or change decks in the web app; saved decks show here.")
		builder.add_theme_font_size_override("font_size", 14)
		builder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		deck_row.add_child(builder)
	if deck_index == 0 and not deck_fixed_:
		var roll := Button.new()
		roll.text = "REROLL" if not built.is_empty() and _show_built else "BUILD"
		roll.add_theme_font_size_override("font_size", 18)
		roll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		roll.tooltip_text = "Build a random deck now (with the heroes you picked, the rest drawn) and see it before the match"
		roll.pressed.connect(func() -> void: _build_random())
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
		var pickable: bool = deck_index == 0 and not deck_fixed_
		if pickable and (id.is_empty() or not _show_built):
			id = chosen[i]
		heroes.add_child(_hero_tile(id, pickable, i))

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
	_load_sideboard()
	_changed()


func _changed() -> void:
	_rebuild()
	changed.emit()


## A hero of the deck as a slanted art slice with its name; "?" for a random deck. In a random
## deck every slot is picked on its own: a click picks that hero, Random leaves it to the draw.
func _hero_tile(id: String, pickable: bool = false, slot: int = 0) -> Control:
	var s := HeroSlice.new()
	s.custom_minimum_size = Vector2(176, 70)
	var card: CardDef = db.catalog.get_card(id) if db != null and not id.is_empty() else null
	s.art = db.thumb(id) if card != null else null
	s.art_region = HeroSlice.region_for(s.art)
	s.art_fallback = Palette.hero(card.color if card != null else "").darkened(0.3) if card != null else Palette.SURFACE_2
	s.mouse_filter = Control.MOUSE_FILTER_PASS
	if pickable and not id.is_empty() and slot < chosen.size() and chosen[slot] == id:
		# Over the art, so the name keeps its room.
		var chip: UiShape = UiShape.chip("PICKED", Palette.GOLD, Color.BLACK, 11, 18.0, 7.0)
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
		s.tooltip_text = "A random hero, drawn when the match starts"
	if pickable:
		s.tooltip_text = "Click to pick this hero (Random leaves it to the draw)\n\n" + s.tooltip_text
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
				_pick_hero(slot))
	return s


## A random deck with the heroes picked (the rest drawn), shown now and played as it is.
func _build_random(show: bool = true) -> void:
	_show_built = show
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	built = DeckCode.random_deck(db.catalog, rng, chosen)
	var names := PackedStringArray()
	for id: String in chosen:
		var c: CardDef = db.catalog.get_card(id) if not id.is_empty() else null
		if c != null:
			names.append(c.name)
	built["name"] = "Random · " + (", ".join(names) if not names.is_empty() else "rolled")
	_changed()


func _stage_tile(slot: int) -> Control:
	var hidden: bool = _view_only and JsonUtil.as_bool(_shown.get("hidden", false))
	return card_tile(db, loadout.stages[slot], Vector2(186, 108), Callable() if _view_only or _locked else func() -> void: _pick_stage(slot),
		false, "?  HIDDEN" if hidden else "?  RANDOM")


## A card as a slanted picture tile (the art part of its image) with its name, and for a stage
## its terrain; "?" for none. Clicks call `on_click`; hover gives it a straw edge.
static func card_tile(db_: CardDb, id: String, tile: Vector2, on_click: Callable, used: bool = false, empty_label: String = "?  RANDOM") -> Control:
	var card: CardDef = db_.catalog.get_card(id) if db_ != null and not id.is_empty() else null
	var s := HeroSlice.new()
	s.custom_minimum_size = tile
	s.art_w = tile.x
	s.set_mirrored(false)
	s.art = db_.thumb(id) if card != null else null
	# A core is a hex token in the middle of a white card: the tile shows that token whole,
	# on the dark tile, not the top of the picture.
	var core_pic: Texture2D = s.art if card != null and card.type == "Core" else null
	if core_pic != null:
		s.art = null
	if s.art != null:
		s.art_region = Rect2(0.08, 0.09, 0.84, 0.42) if s.art.get_height() > s.art.get_width() else HeroSlice.region_for(s.art)
	s.art_fallback = Palette.SURFACE_2
	if core_pic != null:
		# Its value big, in its family's colour (Power gold, Damage red, Knockback blue).
		var family: String = card.core_family()
		var value: String = card.name.split(" ")[0]
		var tint: Color = CORE_FAMILY_COLORS[family] if CORE_FAMILY_COLORS.has(family) else Palette.FG
		var big: Label = UiTheme.label(value, 40, tint)
		big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		big.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		big.offset_bottom = -22
		big.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.add_child(big)
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
		if core_pic != null:
			col.alignment = BoxContainer.ALIGNMENT_END
		var name_l: Label = UiTheme.label(card.core_family().to_upper() if core_pic != null else card.name, 15 if core_pic != null else 19)
		name_l.add_theme_color_override("font_outline_color", Color.BLACK)
		name_l.add_theme_constant_override("outline_size", 6)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(name_l)
		s.tooltip_text = "Already picked" if used else "%s\n%s" % [card.name, card.text]
	else:
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(UiTheme.label(empty_label, 22, Palette.DIM))
		s.tooltip_text = "Hidden until the match" if empty_label.contains("HIDDEN") else "Random"
	s.mouse_entered.connect(func() -> void:
		if clickable:
			s.outline = Palette.GOLD
			s.queue_redraw())
	s.mouse_exited.connect(func() -> void:
		# A picked tile keeps its gold edge (`rest_outline`).
		s.outline = s.get_meta("rest_outline", Color(0, 0, 0, 0))
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
	# The picked core's value on it (playtest 2026-10-30: B / M / D told nothing).
	var d: UiShape = UiShape.make(UiShape.Kind.DIAMOND, color if card != null else Color(0, 0, 0, 0), Vector2(40, 40),
		_core_short(card) if card != null else "?", 12 if card != null else 18, Color.BLACK if card != null else Palette.DIM)
	if card == null:
		d.outline = Color(color, 0.7)
	d.position = Vector2(2, 2)
	b.add_child(d)
	b.tooltip_text = ("%s core: %s\n%s" % [kind, card.name, card.text]) if card != null else "%s core: random" % kind
	if not _view_only and not _locked:
		b.pressed.connect(_open_core_picker)
	else:
		b.mouse_default_cursor_shape = Control.CURSOR_ARROW
	return b


# --- pickers ----------------------------------------------------------------------------

## One hero slot of a random deck: a hero (not one picked in another slot) or Random. With a
## hero picked the deck is built now; all Random goes back to a deck drawn at the start.
func _pick_hero(slot: int) -> void:
	var items: Array[Dictionary] = [{"id": "", "name": "RANDOM", "tex": null}]
	for c: CardDef in db.catalog.of_type("Hero"):
		var elsewhere: bool = chosen.has(c.id) and chosen[slot] != c.id
		items.append({"id": c.id, "name": c.name, "tex": db.thumb(c.id), "used": elsewhere})
	_open_popup("Hero %d" % (slot + 1), items, func(id: String) -> void:
		chosen[slot] = id
		if "".join(chosen).is_empty():
			built = {}
			_changed()
		else:
			# The other slots stay "?" (playtest 2026-10-30): the deck is drawn now but only
			# shown after BUILD or REROLL.
			_build_random(false))


func _pick_stage(slot: int) -> void:
	var items: Array[Dictionary] = [{"id": "", "name": "RANDOM", "tex": null}]
	for c: CardDef in db.catalog.of_type("Stage"):
		var terrain: String = Terrain.name_of(c.terrain) if c.terrain != Terrain.Type.NONE else ""
		items.append({"id": c.id, "name": c.name + ("\n" + terrain.to_upper() if not terrain.is_empty() else ""),
			"tex": db.thumb(c.id), "used": loadout.stages.has(c.id) and loadout.stages[slot] != c.id})
	# Stages as whole cards, so their effect can be read (playtest 2026-10-30).
	_open_popup("Stage %d" % (slot + 1), items, func(id: String) -> void:
		loadout.stages[slot] = id
		_changed(), true)


## All six cores in one window (playtest 2026-10-30: one window per slot was awkward): a row per
## kind, two picks each. A click picks a core (the older pick of the row makes room when both
## are taken) or drops a picked one; RANDOM leaves the row to the draw.
func _open_core_picker() -> void:
	for c: Node in _popup.get_children():
		c.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_popup.add_child(col)
	col.add_child(UiTheme.label("CORES", 28))
	var hint := Label.new()
	hint.text = "Two of each kind. Click to pick or drop one; ROLL picks two at random. A row with nothing picked is drawn when the match starts."
	hint.add_theme_color_override("font_color", Palette.MUTED)
	# Wrapped to the rows' width (playtest 2026-11-07: one long line left empty room beside the tiles).
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(570, 0)
	col.add_child(hint)
	for k: int in Loadout.CORE_KINDS.size():
		var kind: String = Loadout.CORE_KINDS[k]
		var first: int = k * Loadout.CORES_PER_KIND
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		col.add_child(row)
		var row_ids := PackedStringArray()
		var kind_color: Color = KIND_COLORS.get(kind, Palette.FG)
		# The row's name with ROLL right under it (Marko 2026-11-02: at the left, not a bar below).
		var head := VBoxContainer.new()
		head.custom_minimum_size = Vector2(90, 0)
		head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_theme_constant_override("separation", 6)
		row.add_child(head)
		var name_l: Label = UiTheme.label(kind.to_upper(), 18, kind_color)
		head.add_child(name_l)
		var roll := Button.new()
		roll.text = "ROLL"
		roll.focus_mode = Control.FOCUS_NONE
		roll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		roll.add_theme_font_size_override("font_size", 14)
		roll.tooltip_text = "Two %s cores at random" % kind
		head.add_child(roll)
		for c: CardDef in db.catalog.of_type("Core"):
			if c.kind != kind:
				continue
			var id: String = c.id
			var at: int = -1
			for j: int in Loadout.CORES_PER_KIND:
				if loadout.cores[first + j] == id:
					at = first + j
			var tile: HeroSlice = _core_choice(id, at >= 0, func() -> void:
				if at >= 0:
					loadout.cores[at] = ""
				else:
					var free: int = -1
					for j: int in Loadout.CORES_PER_KIND:
						if free < 0 and loadout.cores[first + j].is_empty():
							free = first + j
					if free < 0:
						# Both taken: the older pick goes, the new one comes last.
						for j: int in range(1, Loadout.CORES_PER_KIND):
							loadout.cores[first + j - 1] = loadout.cores[first + j]
						free = first + Loadout.CORES_PER_KIND - 1
					loadout.cores[free] = id
				_core_picked())
			row.add_child(tile)
			row_ids.append(id)
		roll.pressed.connect(func() -> void: _roll_row(first, row_ids))
	var done := Button.new()
	done.text = "DONE"
	done.theme_type_variation = &"Primary"
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	done.pressed.connect(func() -> void: _popup.hide())
	col.add_child(done)
	if not _popup.visible:
		_popup_fitted()


## A core tile in the picker, gold edged (along its slant) with PICKED when it is one of the row's picks.
func _core_choice(id: String, picked: bool, on_click: Callable) -> HeroSlice:
	var tile: HeroSlice = card_tile(db, id, Vector2(150, 96), on_click)
	if picked:
		_set_edge(tile, true)
	if picked and not id.is_empty():
		# On the tile itself: a container would stretch it over the whole frame.
		var chip: UiShape = UiShape.chip("PICKED", Palette.GOLD, Color.BLACK, 11, 18.0, 7.0)
		chip.position = Vector2(14, 4)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(chip)
	return tile


static func _set_edge(tile: HeroSlice, on: bool) -> void:
	var c: Color = Palette.GOLD if on else Color(0, 0, 0, 0)
	tile.set_meta("rest_outline", c)
	tile.outline = c
	tile.outline_width = 3.0
	tile.queue_redraw()


## ROLL on a row: two of the row's cores at random, at once (Marko 2026-11-02: no slot machine here).
func _roll_row(first: int, ids: PackedStringArray) -> void:
	if ids.size() < Loadout.CORES_PER_KIND:
		return
	var order: Array = range(ids.size())
	order.shuffle()
	for j: int in Loadout.CORES_PER_KIND:
		loadout.cores[first + j] = ids[JsonUtil.as_int(order[j])]
	_core_picked()


func _core_picked() -> void:
	_changed()
	_open_core_picker()


## A core's value in short for its diamond: "+2K", "+2", "−1".
static func _core_short(card: CardDef) -> String:
	if card.bonus.is_empty():
		return card.kind.left(1)
	var key: String = card.bonus.keys()[0]
	var v: int = card.bonus[key]
	var text: String = ("%+dK" % (v / 1000)) if key == "pwr" and v % 1000 == 0 else "%+d" % v
	return text.replace("-", "−")


## A card as its whole picture (a stage with its effect text); dimmed when picked elsewhere.
func _whole_card(id: String, on_click: Callable, used: bool) -> Control:
	var card: CardDef = db.catalog.get_card(id)
	var tile := PanelContainer.new()
	# The hover edge goes around the card, outside the picture and as round as its corners (playtest
	# 2026-11-07: drawn under the picture it only showed as gold bits in the round corners).
	var sb: StyleBoxFlat = UiTheme.box(Color(0, 0, 0, 0), 11, Color(0, 0, 0, 0), 4, 4)
	sb.set_border_width_all(3)
	sb.border_color = Color(0, 0, 0, 0)
	sb.anti_aliasing = true
	tile.add_theme_stylebox_override("panel", sb)
	var art := TextureRect.new()
	art.texture = db.thumb(id)
	art.custom_minimum_size = Vector2(170, 238)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.modulate = Color(0.4, 0.4, 0.4) if used else Color.WHITE
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(art)
	tile.tooltip_text = "Already picked" if used else ("%s\n%s" % [card.name, card.text] if card != null else "")
	tile.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN if used else Control.CURSOR_POINTING_HAND
	if not used:
		tile.mouse_entered.connect(func() -> void: sb.border_color = Palette.GOLD)
		tile.mouse_exited.connect(func() -> void: sb.border_color = Color(0, 0, 0, 0))
		tile.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
					and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				on_click.call())
	return tile


func _open_popup(title: String, items: Array[Dictionary], on_pick: Callable, whole_cards: bool = false) -> void:
	for c: Node in _popup.get_children():
		c.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_popup.add_child(col)
	col.add_child(UiTheme.label(title.to_upper(), 28))
	var back := Button.new()
	back.text = "BACK"
	back.theme_type_variation = &"Ghost"
	back.size_flags_horizontal = Control.SIZE_SHRINK_END
	back.pressed.connect(func() -> void: _popup.hide())
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
		var used: bool = JsonUtil.as_bool(it.get("used", false))
		if whole_cards and not id.is_empty() and db.thumb(id) != null:
			grid.add_child(_whole_card(id, pick, used))
		else:
			grid.add_child(card_tile(db, id, Vector2(210, 120) if not whole_cards else Vector2(170, 238), pick, used))
	col.add_child(back)
	_popup_fitted()


## Opens the popup as big as what it holds now (it kept the size of the last one: the cores
## window opened as big as the stages one, with empty room below and beside).
func _popup_fitted() -> void:
	# The first time it opens the content has not been laid out yet, so the window came up too big
	# (Marko 2026-11-08): size it to the content's minimum, and once more a frame later.
	_popup.size = Vector2i.ZERO
	_popup.reset_size()
	var wanted: Vector2i = _popup_content_size()
	_popup.popup_centered(wanted)
	await get_tree().process_frame
	if not _popup.visible:
		return
	var again: Vector2i = _popup_content_size()
	if again != _popup.size:
		_popup.size = again
		_popup.move_to_center()


## The size the popup's content needs now (its panel's margins included).
func _popup_content_size() -> Vector2i:
	var sb: StyleBox = _popup.get_theme_stylebox("panel")
	var pad: Vector2 = Vector2(sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT), sb.get_margin(SIDE_TOP) + sb.get_margin(SIDE_BOTTOM)) if sb != null else Vector2.ZERO
	var inner: Vector2 = Vector2.ZERO
	for c: Node in _popup.get_children():
		if c is Control:
			inner = inner.max((c as Control).get_combined_minimum_size())
	return Vector2i((inner + pad).ceil())
