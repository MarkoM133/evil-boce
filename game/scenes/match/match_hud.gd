class_name MatchHud
extends Control
## Match UI (GDD 11) in the web app's look ("Arena Rush", the in-game UI mockup A): a phase
## ribbon on top, each player's roster of hero slices in the top corners (own left, opponent
## right), a prompt bottom left, the buttons that make sense now bottom right, the hand as a
## fan of card images at the bottom, banners for battles, ring-outs, KOs and claims, the damage
## and choice dialogs and the end screen. It only reads the GameState and emits what was
## clicked; the match scene turns that into moves.

signal pass_pressed(slot: int)
signal choice_pressed(slot: int, roll: bool)
signal keep_pressed(slot: int, keep: bool)
signal no_hero_pressed(slot: int)
signal card_pressed(slot: int, card_id: String)
signal damage_pressed(slot: int, target: String)
## Answer to a "choose" decision (hero, core, card id or branch index; hexes go by click).
signal choose_pressed(slot: int, value: Variant)
signal ability_pressed(slot: int, hero_id: String, card_id: String, index: int)
signal hero_clicked(hero_id: String)
signal hero_hovered(hero_id: String)
signal menu_pressed
signal rematch_pressed
signal watch_replay_pressed
## Setup: the player picked which stage or core to place next.
signal setup_item_pressed(id: String)

const PHASES: Array[String] = [GameState.PHASE_DRAW, GameState.PHASE_SELECT, GameState.PHASE_PREROLL,
	GameState.PHASE_ROLL, GameState.PHASE_POSTROLL, GameState.PHASE_BATTLE, GameState.PHASE_END]
const ROSTER_WIDTH: float = 360.0
const SLICE_HEIGHT: float = 70.0
const CARD_SIZE := Vector2(128, 178)
## Height of the hand strip; the cards stick out of the bottom of the screen a little.
const HAND_HEIGHT: float = 210.0
const BANNER_TIME: float = 0.8
## Log events that get a banner (the rest only go to the log).
const BANNER_EVENTS: Array[String] = ["battle", "ring_out", "ko", "stage_claimed"]

var engine: RulesEngine
var state: GameState
var db: CardDb
var local_slots: PackedInt32Array = PackedInt32Array()
## Hero highlighted from the table (hover on a ball).
var hover_hero: String = ""
## True while the physics runs, so the prompt can say so.
var rolling: bool = false
## Watching a recorded match: no prompts, buttons or end screen, only the table and panels.
var replay: bool = false
## Online: who paused the match ("" when it runs); shown instead of the prompt.
var net_paused: String = ""
## Text of the end screen's first button; "" hides it (an online guest waits for the host).
var rematch_text: String = "Rematch"
## Setup: the stage or core the local player places next (set by the match scene).
var setup_pick: String = ""
## The match summary (MatchRecord.summary) shown on the end screen; set by the match scene.
var end_summary: Dictionary = {}

## How far the hand is lowered (0 = up); it drops when the mouse is over the table (GDD 11).
var _hand_drop: float = 0.0
var _hand_box: Control
var _hand: Control
var _hand_title: Label
var _ribbon: HBoxContainer
var _rosters: Array[VBoxContainer] = []
var _kicker: Label
var _prompt: Label
var _detail: Label
var _actions: VBoxContainer
var _key_hint: Label
var _tray: HBoxContainer
var _log_line: Label
var _log_full: Label
var _log_panel: PanelContainer
var _dialog: PanelContainer
var _dialog_box: VBoxContainer
var _over: Control
var _over_box: VBoxContainer
var _toast_box: Control
var _toast_tween: Tween
var _banner_layer: Control
var _banners: Array[Dictionary] = []
var _banner_busy: bool = false
## How much of state.log has been looked at for banners (-1: not yet, nothing replays).
var _log_seen: int = -1
## The big card above the hand (GDD 11): the card under the mouse ("" = none) and the one shown.
var _hover_cid: String = ""
var _big: TextureRect
var _big_cid: String = ""
## Big card: the height it shows at.
const BIG_HEIGHT: float = 470.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	_build()


# --- public -----------------------------------------------------------------

func setup(engine_: RulesEngine, state_: GameState, db_: CardDb, local: PackedInt32Array) -> void:
	engine = engine_
	state = state_
	db = db_
	local_slots = local
	refresh()


func refresh() -> void:
	if state == null:
		return
	_scan_log()
	_refresh_ribbon()
	for slot: int in state.players.size():
		if slot < _rosters.size():
			_fill_roster(_rosters[slot], slot)
	_refresh_prompt()
	_refresh_hand()
	_refresh_dialog()
	_refresh_log()
	_refresh_over()


## A short message under the ribbon on a slanted chip of `color`.
func toast(text: String, color: Color = Palette.GOLD) -> void:
	for c: Node in _toast_box.get_children():
		c.queue_free()
	var fg: Color = Color.BLACK if color.get_luminance() > 0.5 else Palette.FG
	var chip: UiShape = UiShape.chip(text.to_upper(), color, fg, 22, 40.0, 20.0)
	chip.position = Vector2(-chip.custom_minimum_size.x * 0.5, 0)
	_toast_box.add_child(chip)
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_box.modulate.a = 1.0
	_toast_box.position.y = 64
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_box, "position:y", 70.0, 0.12).from(52.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(1.5)
	_toast_tween.tween_property(_toast_box, "modulate:a", 0.0, 0.4)


## A slanted band across the screen (BATTLE!, RING-OUT …): in, hold, out. Queued.
func banner(title: String, color: Color, left: String = "", right: String = "") -> void:
	_banners.append({"title": title, "color": color, "left": left, "right": right})
	if not _banner_busy:
		_next_banner()


## The local slot whose hand and buttons are shown: the one the game waits for.
func hand_slot() -> int:
	if state == null or local_slots.is_empty():
		return -1
	if not state.pending.is_empty():
		var who: int = JsonUtil.as_int(state.pending[0].get("player", -1), -1)
		if local_slots.has(who):
			return who
	if _in_card_round() and local_slots.has(state.to_act):
		return state.to_act
	for slot: int in local_slots:
		if _needs_input(slot):
			return slot
	return local_slots[0]


func player_name(slot: int) -> String:
	var p: PlayerState = state.player(slot)
	return p.name if p != null and not p.name.is_empty() else "Player %d" % (slot + 1)


func hero_name(h: HeroState) -> String:
	var c: CardDef = engine.stat_card(h)
	return c.name if c != null else h.card_id


# --- layout -----------------------------------------------------------------

func _build() -> void:
	var menu := Button.new()
	menu.text = "≡  MENU"
	menu.focus_mode = Control.FOCUS_NONE
	menu.position = Vector2(14, 12)
	menu.add_theme_font_size_override("font_size", 16)
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	add_child(menu)

	_ribbon = HBoxContainer.new()
	_ribbon.add_theme_constant_override("separation", 3)
	_ribbon.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_ribbon.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ribbon.position = Vector2(0, 12)
	_ribbon.alignment = BoxContainer.ALIGNMENT_CENTER
	_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ribbon)

	for side: int in 2:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 7)
		col.custom_minimum_size = Vector2(ROSTER_WIDTH, 0)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if side == 0:
			col.set_anchors_preset(Control.PRESET_TOP_LEFT)
			col.position = Vector2(14, 58)
		else:
			col.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			col.position = Vector2(-ROSTER_WIDTH - 14, 58)
		add_child(col)
		_rosters.append(col)

	# Bottom left: what the game wants now.
	var prompt_col := VBoxContainer.new()
	prompt_col.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	prompt_col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt_col.position = Vector2(16, -18)
	prompt_col.custom_minimum_size = Vector2(430, 0)
	prompt_col.add_theme_constant_override("separation", 4)
	prompt_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt_col)
	_kicker = UiTheme.label("", 15, Palette.GOLD)
	prompt_col.add_child(_kicker)
	_prompt = UiTheme.label("", 28)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.custom_minimum_size = Vector2(430, 0)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_prompt.add_theme_constant_override("outline_size", 6)
	prompt_col.add_child(_prompt)
	_detail = Label.new()
	_detail.add_theme_color_override("font_color", Color("b9b4ab"))
	_detail.add_theme_font_size_override("font_size", 14)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(430, 0)
	prompt_col.add_child(_detail)
	var log_row := HBoxContainer.new()
	log_row.add_theme_constant_override("separation", 10)
	prompt_col.add_child(log_row)
	var log_btn := Button.new()
	log_btn.text = "LOG"
	log_btn.focus_mode = Control.FOCUS_NONE
	log_btn.add_theme_font_size_override("font_size", 15)
	log_btn.pressed.connect(func() -> void: _log_panel.visible = not _log_panel.visible)
	log_row.add_child(log_btn)
	_log_line = Label.new()
	_log_line.add_theme_color_override("font_color", Palette.MUTED)
	_log_line.add_theme_font_size_override("font_size", 13)
	_log_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_line.clip_text = true
	_log_line.custom_minimum_size = Vector2(300, 0)
	_log_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	log_row.add_child(_log_line)

	_log_panel = PanelContainer.new()
	_log_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_log_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_log_panel.position = Vector2(16, -200)
	_log_panel.custom_minimum_size = Vector2(430, 0)
	_log_panel.visible = false
	add_child(_log_panel)
	_log_full = Label.new()
	_log_full.theme_type_variation = &"Muted"
	_log_full.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_panel.add_child(_log_full)

	# Bottom right: the buttons; the main one is red and big.
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.position = Vector2(-16, -18)
	right.alignment = BoxContainer.ALIGNMENT_END
	right.add_theme_constant_override("separation", 6)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)
	_actions = VBoxContainer.new()
	_actions.alignment = BoxContainer.ALIGNMENT_END
	_actions.add_theme_constant_override("separation", 8)
	_actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_actions)
	_key_hint = Label.new()
	_key_hint.add_theme_color_override("font_color", Palette.MUTED)
	_key_hint.add_theme_font_size_override("font_size", 12)
	_key_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(_key_hint)

	# Setup tray: stages / cores still to place, bottom centre.
	_tray = HBoxContainer.new()
	_tray.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tray.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tray.position = Vector2(0, -30)
	_tray.alignment = BoxContainer.ALIGNMENT_CENTER
	_tray.add_theme_constant_override("separation", 8)
	add_child(_tray)

	# The hand: a fan of cards at the bottom; it slides down when the mouse is over the table.
	_hand_box = Control.new()
	_hand_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hand_box.position = Vector2(-450, -HAND_HEIGHT)
	_hand_box.size = Vector2(900, HAND_HEIGHT)
	_hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hand_box)
	_hand = Control.new()
	_hand.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_box.add_child(_hand)
	_hand_title = UiTheme.label("YOUR STARTING HAND", 40)
	_hand_title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hand_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hand_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hand_title.position = Vector2(-300, -64)
	_hand_title.size = Vector2(600, 50)
	_hand_title.visible = false
	_hand_box.add_child(_hand_title)

	var dialog_center := CenterContainer.new()
	dialog_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dialog_center)
	_dialog = PanelContainer.new()
	_dialog.visible = false
	var dsb: StyleBoxFlat = UiTheme.box(Color(0.03, 0.03, 0.03, 0.96), 0, Color(0, 0, 0, 0), 28, 22)
	dsb.border_color = Palette.GOLD
	dsb.border_width_top = 4
	_dialog.add_theme_stylebox_override("panel", dsb)
	dialog_center.add_child(_dialog)
	_dialog_box = VBoxContainer.new()
	_dialog_box.custom_minimum_size = Vector2(420, 0)
	_dialog_box.add_theme_constant_override("separation", 10)
	_dialog.add_child(_dialog_box)

	_banner_layer = Control.new()
	_banner_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner_layer)

	_over = Control.new()
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.visible = false
	add_child(_over)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.add_child(dim)
	var over_center := CenterContainer.new()
	over_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.add_child(over_center)
	_over_box = VBoxContainer.new()
	_over_box.custom_minimum_size = Vector2(760, 0)
	_over_box.add_theme_constant_override("separation", 14)
	over_center.add_child(_over_box)

	_toast_box = Control.new()
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.modulate.a = 0.0
	add_child(_toast_box)


# --- phase ribbon ----------------------------------------------------------------

func _refresh_ribbon() -> void:
	_clear(_ribbon)
	var turn_text: String = "TURN %d" % state.turn if state.turn > 0 else ("MULLIGAN" if state.phase == GameState.PHASE_MULLIGAN else "SETUP")
	var turn: UiShape = UiShape.chip(turn_text, Palette.ACCENT, Palette.FG, 28, 40.0, 22.0)
	if state.turn > 0:
		turn.tooltip_text = "Initiative this turn: %s" % player_name(state.initiative)
		turn.mouse_filter = Control.MOUSE_FILTER_PASS
	_ribbon.add_child(turn)
	if state.turn > 0:
		var first: UiShape = UiShape.chip("▸ " + player_name(state.initiative).to_upper(),
			Palette.team(state.team_of(state.initiative)), Palette.FG, 14, 26.0, 12.0)
		first.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		first.tooltip_text = "Goes first this turn"
		first.mouse_filter = Control.MOUSE_FILTER_PASS
		_ribbon.add_child(first)
		var now: int = PHASES.find(state.phase)
		for i: int in PHASES.size():
			var fill: Color = Palette.PANEL_SOLID
			var fg: Color = Palette.MUTED
			if i < now:
				fill = Palette.SURFACE_2
				fg = Palette.DIM
			elif i == now:
				fill = Palette.FG
				fg = Color.BLACK
			var w: float = UiTheme.display_heavy().get_string_size(PHASES[i].to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 34.0
			var chev: UiShape = UiShape.make(UiShape.Kind.CHEVRON, fill, Vector2(w, 30), PHASES[i].to_upper(), 15, fg)
			chev.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_ribbon.add_child(chev)
	var tag: UiShape = _status_tag()
	if tag != null:
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_ribbon.add_child(tag)


## "YOUR MOVE" (straw) when the game waits for a local player, else who it waits for.
func _status_tag() -> UiShape:
	if replay or state.is_over():
		return null
	if not net_paused.is_empty():
		return UiShape.chip("PAUSED", Palette.FG, Color.BLACK, 16, 30.0)
	if rolling:
		return UiShape.chip("ROLLING…", Palette.SURFACE_2, Palette.FG, 16, 30.0)
	var waiting: int = _waiting_for()
	if waiting < 0:
		return null
	if local_slots.has(waiting):
		var text: String = "YOUR MOVE" if local_slots.size() == 1 else "%s · YOUR MOVE" % player_name(waiting).to_upper()
		return UiShape.chip(text, Palette.GOLD, Color.BLACK, 16, 30.0)
	return UiShape.chip("%s IS PLAYING…" % player_name(waiting).to_upper(), Palette.PANEL_SOLID, Palette.MUTED, 16, 30.0)


## The slot the game waits for now, or -1.
func _waiting_for() -> int:
	if not state.pending.is_empty():
		return JsonUtil.as_int(state.pending[0].get("player", -1), -1)
	if state.phase == GameState.PHASE_SETUP_STAGES or state.phase == GameState.PHASE_SETUP_CORES:
		return state.setup_turn
	if _in_card_round():
		return state.to_act
	for p: PlayerState in state.players:
		if _needs_input(p.slot):
			return p.slot
	return -1


# --- rosters --------------------------------------------------------------------------

func _fill_roster(col: VBoxContainer, slot: int) -> void:
	_clear(col)
	var right: bool = col == _rosters[1]
	var p: PlayerState = state.player(slot)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.layout_direction = Control.LAYOUT_DIRECTION_RTL if right else Control.LAYOUT_DIRECTION_LTR
	col.add_child(head)
	var name_chip: UiShape = UiShape.chip(player_name(slot).to_upper(), Palette.team(state.team_of(slot)), Palette.FG, 19, 30.0)
	head.add_child(name_chip)
	var cap: int = mini(maxi(state.turn, 0), state.settings.max_energy)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 3)
	pips.tooltip_text = "Energy %d of %d" % [p.energy, cap]
	pips.mouse_filter = Control.MOUSE_FILTER_PASS
	for i: int in state.settings.max_energy:
		var lit: bool = i < p.energy
		var pip: UiShape = UiShape.make(UiShape.Kind.DIAMOND, Palette.GOLD if lit else (Palette.LINE if i < cap else Color(0, 0, 0, 0)), Vector2(12, 12))
		if not lit and i >= cap:
			pip.outline = Palette.LINE
			pip.outline_width = 1.0
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pips.add_child(pip)
	head.add_child(pips)
	head.add_child(UiTheme.label("%d/%d" % [p.energy, cap], 19, Palette.GOLD))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var claimed: int = engine.claimed_count(state, slot)
	var stars := HBoxContainer.new()
	stars.add_theme_constant_override("separation", 2)
	stars.tooltip_text = "Stages claimed: %d of %d" % [claimed, state.settings.stages_to_win]
	stars.mouse_filter = Control.MOUSE_FILTER_PASS
	for i: int in state.settings.stages_to_win:
		var star: UiShape = UiShape.make(UiShape.Kind.STAR, Palette.GOLD if i < claimed else Color(0, 0, 0, 0), Vector2(20, 20))
		if i >= claimed:
			star.outline = Palette.DIM
			star.outline_width = 1.5
		star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stars.add_child(star)
	head.add_child(stars)

	var info := Label.new()
	info.add_theme_color_override("font_color", Palette.MUTED)
	info.add_theme_font_size_override("font_size", 13)
	info.text = "Hand %d  ·  Deck %d  ·  Grave %d" % [p.hand.size(), p.deck.size(), p.graveyard.size()]
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	info.tooltip_text = "Graveyard: " + (", ".join(_card_names(p.graveyard)) if not p.graveyard.is_empty() else "empty")
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(info)
	if not p.assists.is_empty():
		var assists := Label.new()
		assists.theme_type_variation = &"Muted"
		assists.text = "Assists: " + ", ".join(_card_names(p.assists))
		assists.horizontal_alignment = info.horizontal_alignment
		assists.tooltip_text = _card_texts(p.assists)
		assists.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(assists)
	if not p.inventory.is_empty():
		var inv := Label.new()
		inv.add_theme_color_override("font_color", Palette.GOLD)
		inv.add_theme_font_size_override("font_size", 13)
		inv.text = "%d core(s) to put back" % p.inventory.size()
		inv.horizontal_alignment = info.horizontal_alignment
		col.add_child(inv)
	for h: HeroState in state.heroes_of(slot):
		col.add_child(_hero_slice(h, right))


func _hero_slice(h: HeroState, right: bool) -> Control:
	var card: CardDef = engine.stat_card(h)
	var hero_color: Color = Palette.hero(card.color if card != null else "")
	var expanded: bool = _is_expanded(h)
	var active: bool = state.active.get(h.owner, "") == h.id
	var ko: bool = h.is_ko()
	var pickable: bool = _pickable(h)
	var in_battle: bool = _in_battle(h)

	var s := HeroSlice.new()
	s.set_mirrored(right)
	s.art = db.thumb(card.id) if db != null and card != null else null
	s.art_region = HeroSlice.region_for(s.art)
	s.art_fallback = hero_color.darkened(0.3)
	s.bg = Color("222222") if h.id == hover_hero else Palette.PANEL_SOLID
	if ko:
		s.art_tint = Color(0.35, 0.35, 0.35)
		s.modulate.a = 0.6
	if active:
		s.outline = Palette.GOLD
	elif pickable:
		s.outline = Color(Palette.GOLD, 0.55)
		s.outline_width = 2.0
	if in_battle:
		s.stripe = Palette.ACCENT
	s.custom_minimum_size = Vector2(ROSTER_WIDTH - 14.0, SLICE_HEIGHT + (22.0 if expanded else 0.0))
	# Inactive heroes sit a little in from the edge, so the active one sticks out.
	s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var shown_id: String = card.id if card != null else ""
	s.gui_input.connect(func(e: InputEvent) -> void:
		if _card_click(e, shown_id):
			return
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				hero_clicked.emit(h.id))
	s.mouse_entered.connect(func() -> void:
		_hovered(shown_id)
		hero_hovered.emit(h.id))
	s.mouse_exited.connect(func() -> void:
		if _hover_cid == shown_id:
			_hover_cid = ""
		hero_hovered.emit(""))
	if card != null:
		s.tooltip_text = "%s\n%s" % [card.name, card.text]

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.content.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.layout_direction = Control.LAYOUT_DIRECTION_RTL if right else Control.LAYOUT_DIRECTION_LTR
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var name_l: Label = UiTheme.label(hero_name(h), 20)
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	var tag: UiShape = _hero_tag(h, active, pickable, in_battle)
	if tag != null:
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(tag)
	var max_hp: int = engine.max_hp(state, h)
	top.add_child(UiTheme.label("%d/%d" % [h.hp, max_hp], 20, Palette.ACCENT if h.hp * 3 <= max_hp and not ko else Palette.FG))

	var segs := UiSegments.new()
	segs.value = h.hp
	segs.max_value = max_hp
	segs.color = Palette.hp(float(h.hp) / maxf(float(max_hp), 1.0))
	segs.mirrored = right
	segs.custom_minimum_size = Vector2(0, 8)
	segs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(segs)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 4)
	bottom.layout_direction = top.layout_direction
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bottom)
	for i: int in state.settings.core_slots:
		bottom.add_child(_core_slot(h.cores[i] if i < h.cores.size() else "", hero_color))
	var extra := Label.new()
	extra.add_theme_font_size_override("font_size", 12)
	extra.clip_text = true
	extra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var status: String = _status_text(h)
	if not status.is_empty():
		extra.text = status
		extra.add_theme_color_override("font_color", Palette.GOLD)
	elif ko:
		extra.text = "Knocked out"
		extra.add_theme_color_override("font_color", Palette.MUTED)
	elif not h.equipment.is_empty():
		extra.text = "Equip: " + ", ".join(_card_names(h.equipment))
		extra.add_theme_color_override("font_color", Palette.MUTED)
	extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	bottom.add_child(extra)
	if expanded and not ko:
		# A stat a core changes is green (up) or red (down).
		var from_cores: Dictionary[String, int] = _core_bonus(h)
		var stats := RichTextLabel.new()
		stats.bbcode_enabled = true
		stats.fit_content = true
		stats.scroll_active = false
		stats.autowrap_mode = TextServer.AUTOWRAP_OFF
		stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats.add_theme_font_override("normal_font", UiTheme.display_italic())
		stats.add_theme_font_size_override("normal_font_size", 15)
		stats.add_theme_color_override("default_color", Palette.FG)
		var parts := PackedStringArray()
		for key: String in ["pwr", "dmg", "rng", "kb"]:
			var text: String = "%s %d" % [key.to_upper(), engine.stat(state, h, key)]
			var by: int = from_cores.get(key, 0)
			if by != 0:
				text = "[color=#%s]%s[/color]" % [(Palette.HP if by > 0 else Palette.ACCENT).to_html(false), text]
			parts.append(text)
		stats.text = ("[right]%s[/right]" if right else "%s") % "   ".join(parts)
		col.add_child(stats)
	# The active hero sticks out of the column; the others sit in a little.
	var wrap := MarginContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_theme_constant_override("margin_right" if right else "margin_left", 0 if active else 14)
	wrap.add_theme_constant_override("margin_left" if right else "margin_right", 14 if active else 0)
	wrap.add_child(s)
	return wrap


## One of a hero's core slots: what the core there does in short ("PWR+2K", green up, red
## down), else an empty outline. Hover gives the core's name.
func _core_slot(core_id: String, hero_color: Color) -> Control:
	var c: CoreState = state.core(core_id) if not core_id.is_empty() else null
	var card: CardDef = engine.catalog.get_card(c.card_id) if c != null else null
	if card == null or card.bonus.is_empty():
		var dot: UiShape = UiShape.make(UiShape.Kind.DIAMOND, hero_color if c != null else Color(0, 0, 0, 0), Vector2(10, 10))
		if c == null:
			dot.outline = Palette.DIM
			dot.outline_width = 1.5
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if card != null:
			dot.tooltip_text = card.name
		return dot
	var key: String = card.bonus.keys()[0]
	var v: int = card.bonus[key]
	var amount: String = ("%+dK" % (v / 1000)) if key == "pwr" and v % 1000 == 0 else "%+d" % v
	var chip: UiShape = UiShape.chip(key.to_upper() + amount.replace("-", "−"), Color("1b1f20"),
		Palette.HP if v > 0 else Palette.ACCENT, 11, 16.0, 6.0)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.tooltip_text = "%s core: %s" % [card.kind, card.name]
	return chip


## What the hero's active cores add to each stat ({"pwr": 2000, "kb": -1}).
func _core_bonus(h: HeroState) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	for cid: String in h.cores:
		var c: CoreState = state.core(cid)
		var card: CardDef = engine.catalog.get_card(c.card_id) if c != null else null
		if card == null:
			continue
		for k: String in card.bonus:
			out[k] = out.get(k, 0) + card.bonus[k]
	return out


func _hero_tag(h: HeroState, active: bool, pickable: bool, in_battle: bool) -> UiShape:
	if h.is_ko():
		return UiShape.chip("KO", Palette.ACCENT_DEEP, Palette.FG, 13, 20.0, 8.0)
	if in_battle:
		return UiShape.chip("BATTLE", Palette.ACCENT, Palette.FG, 13, 20.0, 8.0)
	if active:
		return UiShape.chip("ACTIVE", Palette.GOLD, Color.BLACK, 13, 20.0, 8.0)
	if pickable:
		return UiShape.chip("PICK", Color(Palette.GOLD, 0.25), Palette.GOLD, 13, 20.0, 8.0)
	if h.tie_turns > 0:
		return UiShape.chip("LOCKED", Palette.SURFACE_2, Palette.FG, 13, 20.0, 8.0)
	if h.zone == HeroState.ZONE_STRIP:
		return UiShape.chip("START", Color(0, 0, 0, 0), Palette.MUTED, 13, 20.0, 8.0)
	return null


func _pickable(h: HeroState) -> bool:
	if state.phase != GameState.PHASE_SELECT or not local_slots.has(h.owner) or state.active.has(h.owner):
		return false
	for x: HeroState in engine.selectable_heroes(state, h.owner):
		if x.id == h.id:
			return true
	return false


func _in_battle(h: HeroState) -> bool:
	if state.phase != GameState.PHASE_BATTLE or state.battle_index < 0 or state.battle_index >= state.battles.size():
		return false
	return JsonUtil.as_strings(state.battles[state.battle_index].get("heroes", [])).has(h.id)


func _is_expanded(h: HeroState) -> bool:
	return h.id == hover_hero or state.active.get(h.owner, "") == h.id or _in_battle(h)


# --- prompt and actions -------------------------------------------------------------

func _in_card_round() -> bool:
	match state.phase:
		GameState.PHASE_PREROLL, GameState.PHASE_POSTROLL, GameState.PHASE_BATTLE:
			return not state.round_over
		GameState.PHASE_ROLL:
			return state.rolled and not state.round_over
	return false


## True when the game waits for something from this slot.
func _needs_input(slot: int) -> bool:
	match state.phase:
		GameState.PHASE_MULLIGAN:
			return not state.player(slot).mulligan_done
		GameState.PHASE_SELECT:
			return not state.active.has(slot)
		GameState.PHASE_PREROLL:
			return not state.choices.has(slot) and state.active_hero(slot) != null
		GameState.PHASE_ROLL:
			return state.choices.get(slot, false) and not state.aims.has(slot) and state.active_hero(slot) != null
	return false


func _refresh_prompt() -> void:
	_clear(_actions)
	_clear(_tray)
	_prompt.text = ""
	_detail.text = ""
	_key_hint.text = ""
	_kicker.text = state.phase.to_upper() if state.turn > 0 or state.phase == GameState.PHASE_MULLIGAN else ""
	if state.is_over() or replay:
		_kicker.text = ""
		return
	if not net_paused.is_empty():
		_kicker.text = "PAUSED"
		_prompt.text = net_paused
		return
	if rolling:
		_prompt.text = "Rolling…"
		return
	if state.phase == GameState.PHASE_SETUP_STAGES or state.phase == GameState.PHASE_SETUP_CORES:
		_setup_prompt()
		return
	if not state.pending.is_empty():
		var d: Dictionary = state.pending[0]
		var who: int = JsonUtil.as_int(d.get("player", -1), -1)
		if not local_slots.has(who):
			_prompt.text = "%s is deciding…" % player_name(who)
		elif str(d.get("type", "")) == RulesEngine.DECISION_RETURN_CORE:
			_prompt.text = "Put a core back"
			_detail.text = "%s: click a highlighted hex." % player_name(who)
		elif str(d.get("type", "")) == FxRuntime.DECISION_CHOOSE and str(d.get("kind", "")) == "hex":
			_prompt.text = str(d.get("prompt", "Pick a hex"))
			_detail.text = "%s: click a highlighted hex." % player_name(who)
		return
	var any_local: bool = false
	for slot: int in local_slots:
		if not _needs_input(slot):
			continue
		any_local = true
		var who: String = player_name(slot)
		var many: bool = local_slots.size() > 1
		match state.phase:
			GameState.PHASE_MULLIGAN:
				_prompt.text = "Keep this hand?"
				_detail.text = ("%s: " % who if many else "") + "a new hand is drawn once."
				_action("New hand", func() -> void: keep_pressed.emit(slot, false))
				_action("KEEP", func() -> void: keep_pressed.emit(slot, true), &"Primary")
			GameState.PHASE_SELECT:
				_prompt.text = "Pick a hero"
				_detail.text = ("%s: " % who if many else "") + "click one of your heroes to activate it."
				if engine.selectable_heroes(state, slot).is_empty():
					_action("No hero can act", func() -> void: no_hero_pressed.emit(slot), &"Primary")
			GameState.PHASE_PREROLL:
				var h: HeroState = state.active_hero(slot)
				_prompt.text = "Roll or Stay?"
				_detail.text = ("%s: " % who if many else "") + "%s rolls into the arena, or stays where it is." % hero_name(h)
				var stay: Button = _action("STAY", func() -> void: choice_pressed.emit(slot, false))
				stay.disabled = h.zone == HeroState.ZONE_STRIP
				if stay.disabled:
					stay.tooltip_text = "A hero in the start zone must roll"
				_action("ROLL", func() -> void: choice_pressed.emit(slot, true), &"Primary")
			GameState.PHASE_ROLL:
				_prompt.text = "Aim and throw"
				_detail.text = ("%s: " % who if many else "") + "drag %s back, release to lock the throw in. Right click cancels." % hero_name(state.active_hero(slot))
		break
	if _in_card_round():
		var slot: int = state.to_act
		var battle: String = _battle_line()
		if local_slots.has(slot):
			if not any_local:
				_prompt.text = "Play a card or pass" if battle.is_empty() else "Battle! Play a card or pass"
				_detail.text = (battle + "  ·  " if not battle.is_empty() else "") + ("%s to act." % player_name(slot) if local_slots.size() > 1 else "Click a card in your hand to play it.")
			for a: Dictionary in engine.fx.usable_abilities(state, slot):
				var h: HeroState = state.hero(str(a["hero"]))
				var c: CardDef = engine.catalog.get_card(str(a["card"]))
				var e: FxEffect = a["effect"]
				var text: String = "%s: %s" % [hero_name(h) if h != null else (c.name if c != null else "?"), e.line.get_slice(":", 1).strip_edges()]
				var ab: Button = _action(text, func() -> void: ability_pressed.emit(slot, str(a["hero"]), str(a["card"]), JsonUtil.as_int(a["index"])), &"Gold")
				if c != null:
					ab.tooltip_text = c.text
			# One red button at a time: while Roll / Stay waits, passing is the quiet option.
			_action("PASS", func() -> void: pass_pressed.emit(slot), &"" if any_local else &"Primary")
			_key_hint.text = "SPACE = PASS"
		elif not any_local:
			_prompt.text = "%s is playing…" % player_name(slot)
			_detail.text = battle
	elif not any_local:
		if state.phase == GameState.PHASE_ROLL and state.awaiting_roll:
			_prompt.text = "Rolling…"
		else:
			_prompt.text = "Waiting for the opponent…"


## Setup (GDD 7): stages, then cores, placed in turn. The tray lists what is left; the picked one
## is straw, its legal hexes light up on the table.
func _setup_prompt() -> void:
	var who: int = state.setup_turn
	var stages: bool = state.phase == GameState.PHASE_SETUP_STAGES
	_kicker.text = "SETUP · " + ("STAGES" if stages else "CORES")
	if not local_slots.has(who):
		_prompt.text = "%s is placing a %s…" % [player_name(who), "stage" if stages else "core"]
		return
	_prompt.text = "Place a stage" if stages else "Place a core"
	_detail.text = ("In the middle third of the map." if stages else "In the opponent's half.") + "  Pick one below, then click a highlighted hex."
	if local_slots.size() > 1:
		_detail.text = "%s: " % player_name(who) + _detail.text
	for id: String in setup_items(state, who):
		var b := Button.new()
		b.text = _setup_label(id)
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = &"Gold" if id == setup_pick else &""
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(func() -> void: setup_item_pressed.emit(id))
		var tip: String = _setup_tip(id)
		if not tip.is_empty():
			b.tooltip_text = tip
		_tray.add_child(b)


## Stages (or cores, in the core phase) `slot` still has to place.
static func setup_items(s: GameState, slot: int) -> PackedStringArray:
	var out := PackedStringArray()
	if s.phase == GameState.PHASE_SETUP_STAGES:
		for st: StageState in s.stages:
			if st.owner == slot and not st.placed:
				out.append(st.id)
	elif s.phase == GameState.PHASE_SETUP_CORES:
		for c: CoreState in s.cores:
			if c.owner == slot and c.place == CoreState.UNPLACED:
				out.append(c.id)
	return out


func _setup_label(id: String) -> String:
	var st: StageState = state.stage(id)
	if st != null:
		var card: CardDef = engine.catalog.get_card(st.card_id)
		var terrain: String = Terrain.name_of(card.terrain) if card != null and card.terrain != Terrain.Type.NONE else ""
		return (card.name if card != null else st.card_id) + ("  ·  " + terrain if not terrain.is_empty() else "")
	var c: CoreState = state.core(id)
	var cc: CardDef = engine.catalog.get_card(c.card_id) if c != null else null
	return "Core · %s" % (cc.kind if cc != null and not cc.kind.is_empty() else "?")


func _setup_tip(id: String) -> String:
	var st: StageState = state.stage(id)
	var card: CardDef = engine.catalog.get_card(st.card_id if st != null else state.core(id).card_id)
	return card.text if card != null else ""


## Status line for a hero: "Immune to KB (1 turn) · Hold hit".
func _status_text(h: HeroState) -> String:
	var names: Dictionary = {"immune_kb": "Immune to KB", "stun": "Stunned", "hold_hit": "No hit, double KB"}
	var parts := PackedStringArray()
	for k: String in h.statuses:
		var label: String = str(names.get(k, k.capitalize()))
		var turns: int = h.statuses[k]
		parts.append(label if turns < 0 else "%s (%d turn%s)" % [label, turns, "" if turns == 1 else "s"])
	return "  ·  ".join(parts)


## "Battle 1/2: Giorno vs Shanks", or "" outside a battle.
func _battle_line() -> String:
	if state.phase != GameState.PHASE_BATTLE or state.battle_index < 0 or state.battle_index >= state.battles.size():
		return ""
	var names := PackedStringArray()
	for id: String in JsonUtil.as_strings(state.battles[state.battle_index].get("heroes", [])):
		var h: HeroState = state.hero(id)
		if h != null:
			names.append(hero_name(h))
	return "Battle %d/%d: %s" % [state.battle_index + 1, state.battles.size(), " vs ".join(names)]


func _action(text: String, cb: Callable, kind: StringName = &"") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.theme_type_variation = kind
	if kind == &"Primary":
		b.add_theme_font_size_override("font_size", 34)
		b.custom_minimum_size = Vector2(220, 0)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.pressed.connect(cb)
	_actions.add_child(b)
	return b


func _process(delta: float) -> void:
	if _hand_box == null or state == null:
		return
	if state.phase == GameState.PHASE_MULLIGAN:
		# The starting hand sits in the middle, big, and stays up.
		_hand_drop = 0.0
		_hand_box.position.y = size.y * 0.5 - HAND_HEIGHT * 0.5
		return
	# Up while the mouse is near the bottom of the screen, else only the tops of the cards show.
	var up: bool = get_local_mouse_position().y > size.y - HAND_HEIGHT - 40.0
	var target: float = 0.0 if up else HAND_HEIGHT - 110.0
	_hand_drop = move_toward(_hand_drop, target, delta * 900.0)
	_hand_box.position.y = size.y - HAND_HEIGHT + 30.0 + _hand_drop


# --- hand ------------------------------------------------------------------------

func _refresh_hand() -> void:
	_clear(_hand)
	var mulligan: bool = state.phase == GameState.PHASE_MULLIGAN
	_hand_title.visible = false
	var slot: int = hand_slot()
	if slot < 0 or state.turn == 0 and not mulligan:
		return
	# No cards are played while heroes are picked and aimed; keep the strip free to grab balls.
	if state.phase == GameState.PHASE_SELECT or state.phase == GameState.PHASE_ROLL and not state.rolled:
		return
	var p: PlayerState = state.player(slot)
	if mulligan and not _needs_input(slot):
		return
	_hand_title.visible = mulligan
	var my_round: bool = _in_card_round() and state.to_act == slot and state.pending.is_empty()
	var n: int = p.hand.size()
	var step: float = minf(176.0 if mulligan else 96.0, 860.0 / maxf(float(n), 1.0))
	for i: int in n:
		var cid: String = p.hand[i]
		var check: Dictionary = _play_check(slot, cid) if my_round else {}
		var playable: bool = my_round and check.get("ok", false) == true
		var card: Control = _hand_card(slot, cid, playable, my_round, str(check.get("why", "")))
		var t: float = i - (n - 1) * 0.5
		card.position = Vector2(_hand.size.x * 0.5 + t * step - CARD_SIZE.x * 0.5, 16.0 + (0.0 if mulligan else t * t * 4.0))
		card.rotation_degrees = 0.0 if mulligan else t * 5.0
		if mulligan:
			card.scale = Vector2.ONE * 1.25
		card.set_meta("rest_y", card.position.y)
		_hand.add_child(card)


## Messages from the engine that still mean "you can play it" (it asks for a choice after).
const PLAY_ASKS: Array[String] = ["choose an assist to replace"]


## Whether `slot` may play `cid` now, asked of the engine itself: the move is tried on a copy of
## the state, once for each hero the card could go on. {"ok", "why" (the engine's reason when
## not), "heroes" (ids it can go on)}.
func _play_check(slot: int, cid: String) -> Dictionary:
	var heroes := PackedStringArray()
	var why: String = ""
	var targets: Array[String] = []
	for h: HeroState in engine.card_context_heroes(state, slot):
		targets.append(h.id)
	if targets.is_empty():
		targets.append("")
	for hid: String in targets:
		var copy: GameState = GameState.from_dict(state.to_dict())
		var err: String = engine.apply(copy, Move.make(Move.PLAY_CARD, slot, {"card": cid, "hero": hid}))
		for ask: String in PLAY_ASKS:
			if err.begins_with(ask):
				err = ""
		if err.is_empty():
			if not hid.is_empty():
				heroes.append(hid)
		elif why.is_empty():
			why = err
	var ok: bool = not heroes.is_empty() or (targets[0].is_empty() and why.is_empty())
	return {"ok": ok, "why": "" if ok else why, "heroes": heroes}


## Where a card picture of `tex` sits in the card slot (aspect kept, centred).
static func _card_rect(tex: Texture2D) -> Rect2:
	if tex == null:
		return Rect2(Vector2.ZERO, CARD_SIZE)
	var k: float = minf(CARD_SIZE.x / tex.get_width(), CARD_SIZE.y / tex.get_height())
	var s := Vector2(tex.get_width(), tex.get_height()) * k
	return Rect2((CARD_SIZE - s) * 0.5, s)


## One card of the hand: its image, the cost on a diamond, and how it can be used now; `why`
## (shown on hover) says what keeps it from being played.
func _hand_card(slot: int, cid: String, playable: bool, my_round: bool, why: String = "") -> Control:
	var c: CardDef = engine.catalog.get_card(cid)
	var root := Control.new()
	root.custom_minimum_size = CARD_SIZE
	root.size = CARD_SIZE
	root.pivot_offset = Vector2(CARD_SIZE.x * 0.5, CARD_SIZE.y)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	var tex: Texture2D = db.thumb(cid) if db != null else null
	var pic: Rect2 = _card_rect(tex)
	root.set_meta("pic", pic)
	var back := ColorRect.new()
	back.color = Palette.hero(c.color if c != null else "").darkened(0.45)
	back.position = pic.position
	back.size = pic.size
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(back)
	if tex != null:
		var img := TextureRect.new()
		img.texture = tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_SCALE
		img.position = pic.position
		img.size = pic.size
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(img)
	else:
		var name_l: Label = UiTheme.label(c.name if c != null else cid, 18)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_l.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(name_l)
	if c != null:
		var poor: bool = my_round and c.cost > state.player(slot).energy
		var cost: UiShape = UiShape.make(UiShape.Kind.DIAMOND, Palette.ACCENT if poor else Palette.GOLD, Vector2(36, 36),
			str(c.cost), 21, Palette.FG if poor else Color.BLACK)
		cost.outline = Color.BLACK
		cost.outline_width = 3.0
		cost.name = "Cost"
		cost.position = pic.position - Vector2(10, 10)
		root.add_child(cost)
		if not c.is_ready():
			var nr: UiShape = UiShape.chip("NOT READY", Palette.SURFACE_2, Palette.MUTED, 12, 20.0, 8.0)
			nr.position = Vector2(CARD_SIZE.x * 0.5 - nr.custom_minimum_size.x * 0.5, pic.end.y - 28)
			root.add_child(nr)
		elif my_round and not playable and not why.is_empty():
			# Why it is grey, on hover.
			var w: UiShape = UiShape.chip(why.to_upper(), Color(0, 0, 0, 0.85), Palette.FG, 10, 18.0, 6.0)
			w.name = "Why"
			w.visible = false
			w.position = Vector2(CARD_SIZE.x * 0.5 - w.custom_minimum_size.x * 0.5, pic.end.y + 4.0)
			root.add_child(w)
		root.tooltip_text = "%s  ·  %s %s  ·  cost %d\n%s" % [c.name, c.color, c.type, c.cost, c.text]
		if my_round and not playable:
			root.tooltip_text = why.capitalize() + "\n\n" + root.tooltip_text if not why.is_empty() else root.tooltip_text
			root.modulate = Color(0.45, 0.45, 0.45)
		elif not my_round:
			root.modulate = Color(0.88, 0.88, 0.88)
	root.mouse_entered.connect(func() -> void:
		_hovered(cid)
		_lift(root, true, playable))
	root.mouse_exited.connect(func() -> void:
		if _hover_cid == cid:
			_hover_cid = ""
		_lift(root, false, playable))
	root.gui_input.connect(func(e: InputEvent) -> void:
		if _card_click(e, cid):
			return
		if playable and e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				card_pressed.emit(slot, cid))
	return root


## Shows card `cid` big above the hand (or hides it with ""); again for the same card hides it.
func _toggle_big(cid: String) -> void:
	_show_big("" if cid == _big_cid else cid)


func _show_big(cid: String) -> void:
	var tex: Texture2D = null
	if not cid.is_empty() and db != null:
		tex = db.large(cid) if db.large(cid) != null else db.thumb(cid)
	if tex == null:
		cid = ""
	_big_cid = cid
	if _big == null:
		_big = TextureRect.new()
		_big.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_big.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_big.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_big.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		add_child(_big)
	_big.visible = tex != null
	if tex == null:
		return
	move_child(_big, -1)
	_big.texture = tex
	var w: float = minf(BIG_HEIGHT * tex.get_width() / tex.get_height(), 700.0)
	_big.size = Vector2(w, BIG_HEIGHT)
	_big.position = Vector2(size.x * 0.5 - w * 0.5, size.y - BIG_HEIGHT - 190.0)
	_big.modulate.a = 0.0
	_big.create_tween().tween_property(_big, "modulate:a", 1.0, 0.1)


## The card-zoom key (Settings → Keys; held, or pressed on and off) shows the card under the mouse.
func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var k := event as InputEventKey
	if k.echo or k.keycode != GameSettings.key("card_zoom"):
		return
	if GameSettings.zoom_mode() == "press":
		if k.pressed:
			_toggle_big(_hover_cid)
	else:
		_show_big(_hover_cid if k.pressed else "")


## The mouse is on card `cid`; with the zoom key held, the big card follows it.
func _hovered(cid: String) -> void:
	_hover_cid = cid
	if GameSettings.zoom_mode() == "hold" and Input.is_key_pressed(GameSettings.key("card_zoom")):
		_show_big(cid)


## Right click shows the card big; any other click puts it away.
func _card_click(e: InputEvent, cid: String) -> bool:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		if (e as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			_toggle_big(cid)
			accept_event()
			return true
		if not _big_cid.is_empty():
			_show_big("")
	return false


## Hover: the card rises, straightens and grows; a playable one gets a straw edge.
func _lift(card: Control, up: bool, playable: bool) -> void:
	var rest: float = JsonUtil.as_float(card.get_meta("rest_y", card.position.y))
	card.z_index = 10 if up else 0
	var t: Tween = card.create_tween().set_parallel(true)
	t.tween_property(card, "position:y", rest - (56.0 if up else 0.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(card, "scale", Vector2.ONE * (1.18 if up else 1.0), 0.12)
	if card.has_node("Why"):
		(card.get_node("Why") as Control).visible = up
	# The straw edge runs round the picture and the cost diamond on its corner.
	var cost: UiShape = card.get_node_or_null("Cost") as UiShape
	if cost != null:
		cost.outline = Palette.GOLD if up and playable else Color.BLACK
		cost.queue_redraw()
	if up and playable:
		var pic: Rect2 = card.get_meta("pic", Rect2(Vector2.ZERO, CARD_SIZE))
		var edge := ReferenceRect.new()
		edge.name = "Edge"
		edge.border_color = Palette.GOLD
		edge.border_width = 3.0
		edge.editor_only = false
		edge.position = pic.position - Vector2(1.5, 1.5)
		edge.size = pic.size + Vector2(3, 3)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(edge)
		if cost != null:
			card.move_child(cost, -1)
	elif not up and card.has_node("Edge"):
		card.get_node("Edge").queue_free()


# --- dialogs ------------------------------------------------------------------------

func _refresh_dialog() -> void:
	_clear(_dialog_box)
	_dialog.visible = false
	if state.pending.is_empty():
		return
	var d: Dictionary = state.pending[0]
	var who: int = JsonUtil.as_int(d.get("player", -1), -1)
	if not local_slots.has(who):
		return
	if str(d.get("type", "")) == FxRuntime.DECISION_CHOOSE:
		_choose_dialog(d, who)
		return
	if str(d.get("type", "")) != RulesEngine.DECISION_DAMAGE:
		return
	_dialog.visible = true
	var amount: int = JsonUtil.as_int(d.get("amount", 0))
	var winner: HeroState = state.hero(str(d.get("winner", "")))
	_dialog_box.add_child(UiTheme.label("BATTLE LOST · %s" % player_name(who).to_upper(), 15, Palette.GOLD))
	_dialog_box.add_child(UiTheme.label("Where do %d DMG go?" % amount, 36))
	var sub := Label.new()
	sub.add_theme_color_override("font_color", Palette.MUTED)
	sub.text = "The hit from %s lands on a hero, or on the deck." % (hero_name(winner) if winner != null else "?")
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_box.add_child(sub)
	for id: String in JsonUtil.as_strings(d.get("targets", [])):
		var h: HeroState = state.hero(id)
		if h == null:
			continue
		_option_button("%s   HP %d → %d" % [hero_name(h).to_upper(), h.hp, maxi(h.hp - amount, 0)],
			func() -> void: damage_pressed.emit(who, id))
	var p: PlayerState = state.player(who)
	_option_button("DECK   %d cards, %d in hand" % [p.deck.size(), p.hand.size()], func() -> void: damage_pressed.emit(who, "deck"))


## A card effect asks for a hero, core, card or branch (hexes are clicked on the table).
func _choose_dialog(d: Dictionary, who: int) -> void:
	var kind: String = str(d.get("kind", ""))
	if kind == "hex":
		return
	_dialog.visible = true
	var ctx: Dictionary = JsonUtil.as_dict(JsonUtil.as_dict(d.get("resume", {})).get("ctx", {}))
	_dialog_box.add_child(UiTheme.label(_card_name(str(ctx.get("card", ""))).to_upper(), 15, Palette.GOLD))
	var title: Label = UiTheme.label(str(d.get("prompt", "Choose")), 36)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_box.add_child(title)
	if local_slots.size() > 1:
		var sub := Label.new()
		sub.add_theme_color_override("font_color", Palette.MUTED)
		sub.text = player_name(who)
		_dialog_box.add_child(sub)
	var options: Array = JsonUtil.as_array(d.get("options", []))
	for i: int in options.size():
		var o: Variant = options[i]
		var text: String = str(o)
		match kind:
			"hero":
				var h: HeroState = state.hero(str(o))
				text = "%s   HP %d" % [hero_name(h).to_upper(), h.hp] if h != null else str(o)
			"core":
				var c: CoreState = state.core(str(o))
				text = "%s CORE AT %s" % ["FACE-UP" if c != null and c.face_up else "FACE-DOWN", str(c.hex) if c != null else "?"]
			"card":
				text = _card_name(str(o)).to_upper()
		var value: Variant = i if kind == "option" else o
		_option_button(text, func() -> void: choose_pressed.emit(who, value))


func _option_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(420, 50)
	b.pressed.connect(cb)
	_dialog_box.add_child(b)
	return b


# --- log and banners -----------------------------------------------------------------

func _refresh_log() -> void:
	var lines := PackedStringArray()
	for e: Dictionary in state.log:
		var s: String = _describe(e)
		if not s.is_empty():
			lines.append(s)
	_log_line.text = lines[lines.size() - 1] if not lines.is_empty() else ""
	var start: int = maxi(0, lines.size() - 16)
	_log_full.text = "\n".join(lines.slice(start))


## New log entries since the last look: banners for the big moments. The first look (and a
## replay stepping back) only takes note.
func _scan_log() -> void:
	var n: int = state.log.size()
	if _log_seen < 0 or n < _log_seen:
		_log_seen = n
		return
	var fresh: Array[Dictionary] = []
	for i: int in range(_log_seen, n):
		var e: Dictionary = state.log[i]
		var t: String = str(e.get("type", ""))
		if BANNER_EVENTS.has(t):
			fresh.append(e)
		elif t == "stage_revealed":
			var st: StageState = state.stage(str(e.get("stage", "")))
			var card: CardDef = engine.catalog.get_card(st.card_id) if st != null else null
			if card != null:
				var terrain: String = Terrain.name_of(card.terrain) if card.terrain != Terrain.Type.NONE else ""
				toast("Stage revealed · %s%s" % [card.name, (" · " + terrain) if not terrain.is_empty() else ""])
	_log_seen = n
	# A replay jumping ahead shows only the last few.
	for e: Dictionary in fresh.slice(maxi(0, fresh.size() - 3)):
		_banner_for(e)


func _banner_for(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"battle":
			var power: Dictionary = JsonUtil.as_dict(e.get("power", {}))
			var sides := PackedStringArray()
			for id: Variant in power:
				var h: HeroState = state.hero(str(id))
				sides.append("%s\n%d" % [(hero_name(h) if h != null else str(id)).to_upper(), JsonUtil.as_int(power[id])])
			banner("BATTLE!", Palette.ACCENT, sides[0] if sides.size() > 0 else "", sides[1] if sides.size() > 1 else "")
		"ring_out":
			banner("RING-OUT", Palette.GOLD, "", _hero_label(str(e.get("hero", ""))).to_upper())
		"ko":
			banner("KO", Palette.ACCENT_DEEP, "", _hero_label(str(e.get("hero", ""))).to_upper())
		"stage_claimed":
			var st: StageState = state.stage(str(e.get("stage", "")))
			banner("STAGE CLAIMED", Palette.GOLD, player_name(JsonUtil.as_int(e.get("player", 0))).to_upper(),
				_card_name(st.card_id if st != null else "").to_upper())


func _next_banner() -> void:
	if _banners.is_empty():
		_banner_busy = false
		return
	_banner_busy = true
	var b: Dictionary = _banners.pop_front()
	var color: Color = b["color"]
	var fg: Color = Color.BLACK if color.get_luminance() > 0.5 else Palette.FG
	var w: float = size.x + 200.0
	var band := Panel.new()
	var sb: StyleBoxFlat = UiTheme.box(color, 0)
	sb.border_color = Color.BLACK
	sb.set_border_width_all(6)
	band.add_theme_stylebox_override("panel", sb)
	band.size = Vector2(w, 100)
	band.pivot_offset = band.size * 0.5
	band.position = Vector2(-100.0 - w, size.y * 0.5 - 50.0)
	band.rotation_degrees = -3.0
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_layer.add_child(band)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(row)
	row.add_child(_banner_side(str(b["left"]), fg, true))
	var title: Label = UiTheme.label(str(b["title"]), 84, fg)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 10 if fg == Palette.FG else 0)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	row.add_child(_banner_side(str(b["right"]), fg, false))
	var t: Tween = band.create_tween()
	t.tween_property(band, "position:x", -100.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(BANNER_TIME)
	t.tween_property(band, "position:x", size.x + 100.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		band.queue_free()
		_next_banner())


func _banner_side(text: String, fg: Color, left: bool) -> Label:
	var l: Label = UiTheme.label(text, 26, fg)
	l.custom_minimum_size = Vector2(220, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if left else HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _describe(e: Dictionary) -> String:
	var t: String = str(e.get("type", ""))
	var hero_l: String = _hero_label(str(e.get("hero", "")))
	match t:
		"damage":
			return "%s takes %d (HP %d)" % [hero_l, JsonUtil.as_int(e.get("amount", 0)), JsonUtil.as_int(e.get("hp", 0))]
		"deck_damage":
			return "%s: %d cards from the deck" % [player_name(JsonUtil.as_int(e.get("player", 0))), JsonUtil.as_int(e.get("amount", 0))]
		"ko":
			return "%s is KO" % hero_l
		"ring_out":
			return "%s rings out" % hero_l
		"knockback":
			return "%s knocked back %d" % [hero_l, JsonUtil.as_int(e.get("steps", 0))]
		"stage_revealed":
			var st: StageState = state.stage(str(e.get("stage", "")))
			return "Stage revealed: %s" % _card_name(st.card_id if st != null else "")
		"stage_claimed":
			var st2: StageState = state.stage(str(e.get("stage", "")))
			return "%s claims %s" % [player_name(JsonUtil.as_int(e.get("player", 0))), _card_name(st2.card_id if st2 != null else "")]
		"core_activated":
			return "%s activates a core" % hero_l
		"equipped", "evolved", "action":
			return "%s → %s" % [_card_name(str(e.get("card", ""))), hero_l]
		"assist":
			return "Assist: %s" % _card_name(str(e.get("card", "")))
		"heal":
			return "%s heals %d (HP %d)" % [hero_l, JsonUtil.as_int(e.get("amount", 0)), JsonUtil.as_int(e.get("hp", 0))]
		"ability":
			return "%s uses %s" % [hero_l, _card_name(str(e.get("card", "")))]
		"wall":
			return "Wall placed"
		"fx_skipped":
			return "%s: %s" % [_card_name(str(e.get("card", ""))), str(e.get("why", ""))]
		"roll_again":
			return "%s rolls again" % hero_l
		"core_revealed":
			return "A core is revealed"
		"energy":
			return "%s energy %+d" % [player_name(JsonUtil.as_int(e.get("player", 0))), JsonUtil.as_int(e.get("amount", 0))]
		"discard":
			return "%s discards %s" % [player_name(JsonUtil.as_int(e.get("player", 0))), _card_name(str(e.get("card", "")))]
		"battle_locked":
			return "Battle tied, heroes locked"
		"turn_end":
			return "— end of turn %d —" % JsonUtil.as_int(e.get("turn", 0))
		"match_end":
			return "Match over"
	return ""


# --- end of the match ----------------------------------------------------------------

func _refresh_over() -> void:
	var was: bool = _over.visible
	_over.visible = state.is_over() and not replay
	if not _over.visible:
		return
	_clear(_over_box)
	var reasons: Dictionary = {"ko": "ALL HEROES KO", "stages": "STAGES CLAIMED", "deckout": "DECK-OUT",
		"surrender": "SURRENDER", "draw": "DRAW"}
	_over_box.add_child(UiTheme.label("%s  ·  TURN %d" % [str(reasons.get(state.result, state.result.to_upper())), state.turn], 18, Palette.GOLD))
	var title: String = "DRAW"
	var title_color: Color = Palette.FG
	if state.winner >= 0:
		if local_slots.size() == 1:
			title = "VICTORY" if local_slots.has(state.winner) else "DEFEAT"
			title_color = Palette.FG if local_slots.has(state.winner) else Palette.MUTED
		else:
			title = "%s WINS" % player_name(state.winner).to_upper()
	# The title with a red shadow behind it, like the app's stickers.
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(0, 130)
	_over_box.add_child(stack)
	var shadow: Label = UiTheme.label(title, 120, Palette.ACCENT)
	shadow.position = Vector2(8, 8)
	stack.add_child(shadow)
	var main: Label = UiTheme.label(title, 120, title_color)
	main.add_theme_color_override("font_outline_color", Color.BLACK)
	main.add_theme_constant_override("outline_size", 8)
	stack.add_child(main)
	if state.winner >= 0:
		var strips := HBoxContainer.new()
		strips.add_theme_constant_override("separation", 6)
		_over_box.add_child(strips)
		for h: HeroState in state.heroes_of(state.winner):
			var s := HeroSlice.new()
			var card: CardDef = engine.stat_card(h)
			s.art = db.thumb(card.id) if db != null and card != null else null
			s.art_region = HeroSlice.region_for(s.art)
			s.art_fallback = Palette.hero(card.color if card != null else "")
			s.custom_minimum_size = Vector2(HeroSlice.ART_W + HeroSlice.CUT + 4.0, 56)
			if h.is_ko():
				s.art_tint = Color(0.35, 0.35, 0.35)
			s.tooltip_text = hero_name(h)
			strips.add_child(s)
	if not end_summary.is_empty():
		_over_box.add_child(_stats_table())
	if rematch_text.is_empty():
		var wait := Label.new()
		wait.add_theme_color_override("font_color", Palette.MUTED)
		wait.text = "The host can take everyone back to the lobby."
		_over_box.add_child(wait)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	_over_box.add_child(buttons)
	if not rematch_text.is_empty():
		var again := Button.new()
		again.text = rematch_text.to_upper()
		again.theme_type_variation = &"Primary"
		again.add_theme_font_size_override("font_size", 28)
		again.pressed.connect(func() -> void: rematch_pressed.emit())
		buttons.add_child(again)
	var watch := Button.new()
	watch.text = "WATCH REPLAY"
	watch.add_theme_font_size_override("font_size", 22)
	watch.pressed.connect(func() -> void: watch_replay_pressed.emit())
	buttons.add_child(watch)
	var back := Button.new()
	back.text = "MENU"
	back.add_theme_font_size_override("font_size", 22)
	back.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(back)
	if not was:
		_over_box.modulate.a = 0.0
		_over_box.scale = Vector2(1.08, 1.08)
		var t: Tween = _over_box.create_tween().set_parallel(true)
		t.tween_property(_over_box, "modulate:a", 1.0, 0.25)
		t.tween_property(_over_box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Per player, from the match summary that also goes to stats/ (GDD 11: the end shows stats).
func _stats_table() -> Control:
	var panel := PanelContainer.new()
	var grid := GridContainer.new()
	var players: Array = JsonUtil.as_array(end_summary.get("players", []))
	grid.columns = players.size() + 1
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	panel.add_child(grid)
	grid.add_child(Control.new())
	for p: Variant in players:
		var d: Dictionary = JsonUtil.as_dict(p)
		grid.add_child(UiTheme.label(str(d.get("name", "")).to_upper(), 20, Palette.team(JsonUtil.as_int(d.get("slot", 0)))))
	for row: Array in [["Stages claimed", "stages_claimed"], ["Heroes KO", "kos_suffered"], ["Ring-outs", "ring_outs_suffered"]]:
		var l := Label.new()
		l.text = str(row[0])
		l.add_theme_color_override("font_color", Palette.MUTED)
		grid.add_child(l)
		for p: Variant in players:
			grid.add_child(UiTheme.label(str(JsonUtil.as_int(JsonUtil.as_dict(p).get(str(row[1]), 0))), 26))
	var battles := Label.new()
	battles.text = "Battles"
	battles.add_theme_color_override("font_color", Palette.MUTED)
	grid.add_child(battles)
	grid.add_child(UiTheme.label(str(JsonUtil.as_int(end_summary.get("battles", 0))), 26))
	for i: int in players.size() - 1:
		grid.add_child(Control.new())
	return panel


# --- helpers ------------------------------------------------------------------------

func _hero_label(id: String) -> String:
	var h: HeroState = state.hero(id)
	return hero_name(h) if h != null else id


func _card_name(cid: String) -> String:
	var c: CardDef = engine.catalog.get_card(cid)
	return c.name if c != null else cid


func _card_names(ids: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for cid: String in ids:
		out.append(_card_name(cid))
	return out


func _card_texts(ids: PackedStringArray) -> String:
	var out := PackedStringArray()
	for cid: String in ids:
		var c: CardDef = engine.catalog.get_card(cid)
		if c != null:
			out.append("%s: %s" % [c.name, c.text])
	return "\n".join(out)


static func _clear(node: Node) -> void:
	for c: Node in node.get_children():
		node.remove_child(c)
		c.queue_free()
