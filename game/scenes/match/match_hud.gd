class_name MatchHud
extends Control
## Match UI (GDD 11): phase bar, player and hero panels (own left, opponent right), the hand
## of the player who acts, a prompt with the buttons that make sense now, the damage choice,
## a one-line log and the end screen. It only reads the GameState and emits what was clicked;
## the match scene turns that into moves.

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
## Setup: the player picked which stage or core to place next.
signal setup_item_pressed(id: String)

const PHASES: Array[String] = [GameState.PHASE_DRAW, GameState.PHASE_SELECT, GameState.PHASE_PREROLL,
	GameState.PHASE_ROLL, GameState.PHASE_POSTROLL, GameState.PHASE_BATTLE, GameState.PHASE_END]
const PANEL_WIDTH: float = 290.0
const CARD_SIZE := Vector2(132, 84)

var engine: RulesEngine
var state: GameState
var db: CardDb
var local_slots: PackedInt32Array = PackedInt32Array()
## Hero highlighted from the table (hover on a ball).
var hover_hero: String = ""
## True while the physics runs, so the prompt can say so.
var rolling: bool = false
## Setup: the stage or core the local player places next (set by the match scene).
var setup_pick: String = ""
## How far the hand is lowered (0 = up); it drops when the mouse is over the table (GDD 11).
var _hand_drop: float = 0.0
var _hand_box: Control

var _phase_bar: HBoxContainer
var _player_boxes: Array[VBoxContainer] = []
var _prompt: Label
var _actions: HBoxContainer
var _hand: HBoxContainer
var _log_line: Button
var _log_full: Label
var _log_panel: PanelContainer
var _dialog: PanelContainer
var _dialog_box: VBoxContainer
var _over: Control
var _over_title: Label
var _over_info: Label
var _toast: Label
var _toast_tween: Tween


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
	_refresh_phase_bar()
	for slot: int in state.players.size():
		if slot < _player_boxes.size():
			_fill_player(_player_boxes[slot], slot)
	_refresh_prompt()
	_refresh_hand()
	_refresh_dialog()
	_refresh_log()
	_refresh_over()


func toast(text: String, color: Color = Palette.GOLD) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


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
	menu.text = "MENU"
	menu.focus_mode = Control.FOCUS_NONE
	menu.position = Vector2(12, 12)
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	add_child(menu)

	_phase_bar = HBoxContainer.new()
	_phase_bar.add_theme_constant_override("separation", 14)
	_phase_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_phase_bar.position = Vector2(-330, 14)
	_phase_bar.size = Vector2(660, 30)
	_phase_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_phase_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_phase_bar)

	for side: int in 2:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
		if side == 0:
			panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
			panel.position = Vector2(12, 56)
		else:
			panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			panel.position = Vector2(-PANEL_WIDTH - 12, 56)
		add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		panel.add_child(box)
		_player_boxes.append(box)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.position = Vector2(-450, -CARD_SIZE.y - 24)
	bottom.size = Vector2(900, 0)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 8)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom)
	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_override("font", UiTheme.display_bold())
	_prompt.add_theme_font_size_override("font_size", 22)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_prompt.add_theme_constant_override("outline_size", 6)
	bottom.add_child(_prompt)
	_actions = HBoxContainer.new()
	_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_actions.add_theme_constant_override("separation", 8)
	bottom.add_child(_actions)
	# The hand sits on its own under the prompt so it can slide down out of the way.
	_hand_box = Control.new()
	_hand_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hand_box.position = Vector2(-600, -CARD_SIZE.y - 12)
	_hand_box.size = Vector2(1200, CARD_SIZE.y)
	_hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hand_box)
	_hand = HBoxContainer.new()
	_hand.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hand.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand.add_theme_constant_override("separation", 6)
	_hand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_box.add_child(_hand)

	_log_line = Button.new()
	_log_line.flat = true
	_log_line.focus_mode = Control.FOCUS_NONE
	_log_line.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_log_line.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_log_line.position = Vector2(12, -40)
	_log_line.add_theme_font_override("font", UiTheme.body_font())
	_log_line.add_theme_font_size_override("font_size", 14)
	_log_line.add_theme_color_override("font_color", Palette.MUTED)
	_log_line.pressed.connect(func() -> void: _log_panel.visible = not _log_panel.visible)
	add_child(_log_line)
	_log_panel = PanelContainer.new()
	var log_panel: PanelContainer = _log_panel
	log_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	log_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	log_panel.position = Vector2(12, -48)
	log_panel.custom_minimum_size = Vector2(380, 0)
	log_panel.visible = false
	add_child(log_panel)
	_log_full = Label.new()
	_log_full.theme_type_variation = &"Muted"
	_log_full.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_panel.add_child(_log_full)

	var dialog_center := CenterContainer.new()
	dialog_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dialog_center)
	_dialog = PanelContainer.new()
	_dialog.visible = false
	dialog_center.add_child(_dialog)
	_dialog_box = VBoxContainer.new()
	_dialog_box.custom_minimum_size = Vector2(340, 0)
	_dialog_box.add_theme_constant_override("separation", 8)
	_dialog.add_child(_dialog_box)

	_over = Control.new()
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.visible = false
	add_child(_over)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.add_child(dim)
	var over_center := CenterContainer.new()
	over_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.add_child(over_center)
	var over_panel := PanelContainer.new()
	over_center.add_child(over_panel)
	var over_col := VBoxContainer.new()
	over_col.custom_minimum_size = Vector2(320, 0)
	over_col.add_theme_constant_override("separation", 10)
	over_panel.add_child(over_col)
	_over_title = Label.new()
	_over_title.theme_type_variation = &"Big"
	_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_col.add_child(_over_title)
	_over_info = Label.new()
	_over_info.theme_type_variation = &"Muted"
	_over_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_col.add_child(_over_info)
	var rematch := Button.new()
	rematch.text = "Rematch"
	rematch.pressed.connect(func() -> void: rematch_pressed.emit())
	over_col.add_child(rematch)
	var back := Button.new()
	back.text = "Main menu"
	back.pressed.connect(func() -> void: menu_pressed.emit())
	over_col.add_child(back)

	_toast = Label.new()
	_toast.add_theme_font_override("font", UiTheme.display_bold())
	_toast.add_theme_font_size_override("font_size", 28)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("outline_size", 8)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.position = Vector2(-400, 52)
	_toast.size = Vector2(800, 40)
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)


# --- phase bar -------------------------------------------------------------------

func _refresh_phase_bar() -> void:
	_clear(_phase_bar)
	var turn := Label.new()
	turn.text = "TURN %d" % maxi(state.turn, 1) if state.turn > 0 else "SETUP"
	turn.add_theme_font_override("font", UiTheme.display_bold())
	turn.add_theme_font_size_override("font_size", 20)
	_phase_bar.add_child(turn)
	if state.turn > 0:
		var first := Label.new()
		first.text = "▸ " + player_name(state.initiative)
		first.add_theme_font_override("font", UiTheme.display_font())
		first.add_theme_font_size_override("font_size", 17)
		first.add_theme_color_override("font_color", Palette.team(state.team_of(state.initiative)))
		first.tooltip_text = "Initiative this turn"
		first.mouse_filter = Control.MOUSE_FILTER_PASS
		_phase_bar.add_child(first)
	for ph: String in PHASES:
		var l := Label.new()
		l.text = ph.to_upper()
		l.add_theme_font_override("font", UiTheme.display_font())
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", Palette.GOLD if ph == state.phase else Color(Palette.MUTED, 0.6))
		_phase_bar.add_child(l)


# --- player and hero panels ---------------------------------------------------------

func _fill_player(box: VBoxContainer, slot: int) -> void:
	_clear(box)
	var p: PlayerState = state.player(slot)
	var team_color: Color = Palette.team(state.team_of(slot))
	var head := HBoxContainer.new()
	box.add_child(head)
	var name_l := Label.new()
	name_l.text = player_name(slot).to_upper()
	name_l.add_theme_font_override("font", UiTheme.display_bold())
	name_l.add_theme_font_size_override("font_size", 22)
	name_l.add_theme_color_override("font_color", team_color)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_l)
	var energy := Label.new()
	energy.text = "⚡ %d/%d" % [p.energy, mini(maxi(state.turn, 0), state.settings.max_energy)]
	energy.add_theme_font_override("font", UiTheme.display_bold())
	energy.add_theme_font_size_override("font_size", 22)
	energy.add_theme_color_override("font_color", Palette.GOLD)
	energy.tooltip_text = "Energy"
	energy.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(energy)

	var stars: String = ""
	for i: int in state.settings.stages_to_win:
		stars += "★" if i < engine.claimed_count(state, slot) else "☆"
	var info := Label.new()
	info.theme_type_variation = &"Muted"
	info.text = "Deck %d  ·  Hand %d  ·  Grave %d  ·  %s" % [p.deck.size(), p.hand.size(), p.graveyard.size(), stars]
	info.tooltip_text = "Graveyard: " + (", ".join(_card_names(p.graveyard)) if not p.graveyard.is_empty() else "empty")
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(info)
	if not p.assists.is_empty():
		var assists := Label.new()
		assists.theme_type_variation = &"Muted"
		assists.text = "Assists: " + ", ".join(_card_names(p.assists))
		assists.tooltip_text = _card_texts(p.assists)
		assists.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(assists)
	if not p.inventory.is_empty():
		var inv := Label.new()
		inv.theme_type_variation = &"Muted"
		inv.text = "Inventory: %d core(s) to put back" % p.inventory.size()
		box.add_child(inv)
	for h: HeroState in state.heroes_of(slot):
		box.add_child(_hero_row(h))


func _hero_row(h: HeroState) -> Control:
	var card: CardDef = engine.catalog.get_card(h.card_id)
	var hero_color: Color = Palette.hero(card.color if card != null else "")
	var expanded: bool = _is_expanded(h)
	var active: bool = state.active.get(h.owner, "") == h.id

	var panel := PanelContainer.new()
	var bg: Color = Color(1, 1, 1, 0.07) if h.id == hover_hero else Color(1, 1, 1, 0.02)
	var sb: StyleBoxFlat = UiTheme.box(bg, 3, Palette.GOLD if active else Color(0, 0, 0, 0), 8, 5)
	sb.border_width_left = 4
	sb.border_color = Palette.GOLD if active else hero_color
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				hero_clicked.emit(h.id))
	panel.mouse_entered.connect(func() -> void: hero_hovered.emit(h.id))
	panel.mouse_exited.connect(func() -> void: hero_hovered.emit(""))
	if card != null:
		panel.tooltip_text = card.text

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var name_l := Label.new()
	name_l.text = hero_name(h)
	name_l.add_theme_font_override("font", UiTheme.display_bold())
	name_l.add_theme_font_size_override("font_size", 18)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	top.add_child(name_l)
	var tag := Label.new()
	tag.theme_type_variation = &"Muted"
	match h.zone:
		HeroState.ZONE_STRIP:
			tag.text = "START"
		HeroState.ZONE_KO:
			tag.text = "KO"
			tag.add_theme_color_override("font_color", Palette.ACCENT)
		_:
			tag.text = ""
	if h.tie_turns > 0:
		tag.text = "LOCKED"
	if h.has_status("stun"):
		tag.text = "STUN"
	top.add_child(tag)
	var hp := Label.new()
	var max_hp: int = engine.max_hp(state, h)
	hp.text = "%d/%d" % [h.hp, max_hp]
	hp.add_theme_font_override("font", UiTheme.display_bold())
	hp.add_theme_font_size_override("font_size", 18)
	hp.add_theme_color_override("font_color", Palette.ACCENT if h.hp * 3 <= max_hp else Palette.FG)
	top.add_child(hp)

	var bar := _hp_bar(h.hp, max_hp, hero_color)
	col.add_child(bar)

	var cores := Label.new()
	cores.theme_type_variation = &"Muted"
	var dots: String = ""
	for i: int in state.settings.core_slots:
		dots += "●" if i < h.cores.size() else "○"
	cores.text = "Cores " + dots
	col.add_child(cores)
	var status: String = _status_text(h)
	if not status.is_empty():
		var st := Label.new()
		st.theme_type_variation = &"Muted"
		st.text = status
		st.add_theme_color_override("font_color", Palette.GOLD)
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(st)
	if expanded:
		var stats := Label.new()
		stats.theme_type_variation = &"Muted"
		stats.text = "PWR %d  ·  DMG %d  ·  RNG %d  ·  KB %d" % [engine.stat(state, h, "pwr"),
			engine.stat(state, h, "dmg"), engine.stat(state, h, "rng"), engine.stat(state, h, "kb")]
		stats.add_theme_color_override("font_color", Palette.FG)
		col.add_child(stats)
		if not h.equipment.is_empty():
			var eq := Label.new()
			eq.theme_type_variation = &"Muted"
			eq.text = "Equip: " + ", ".join(_card_names(h.equipment))
			eq.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			col.add_child(eq)
		if not h.evolutions.is_empty():
			var ev := Label.new()
			ev.theme_type_variation = &"Muted"
			ev.text = "Evolution %d" % h.evolutions.size()
			col.add_child(ev)
	return panel


func _hp_bar(hp: int, max_hp: int, color: Color) -> Control:
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 4)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := ColorRect.new()
	back.color = Color(1, 1, 1, 0.08)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(back)
	var fill := ColorRect.new()
	fill.color = color
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(float(hp) / maxf(float(max_hp), 1.0), 0.0, 1.0)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	return bar


func _is_expanded(h: HeroState) -> bool:
	if h.id == hover_hero or state.active.get(h.owner, "") == h.id:
		return true
	if state.phase == GameState.PHASE_BATTLE and state.battle_index >= 0 and state.battle_index < state.battles.size():
		return JsonUtil.as_strings(state.battles[state.battle_index].get("heroes", [])).has(h.id)
	return false


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
	_prompt.text = ""
	if state.is_over():
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
			_prompt.text = "%s: click a highlighted hex to put a core back" % player_name(who)
		elif str(d.get("type", "")) == FxRuntime.DECISION_CHOOSE and str(d.get("kind", "")) == "hex":
			_prompt.text = "%s: %s (click a highlighted hex)" % [player_name(who), str(d.get("prompt", ""))]
		return
	var any_local: bool = false
	for slot: int in local_slots:
		if not _needs_input(slot):
			continue
		any_local = true
		var who: String = player_name(slot)
		match state.phase:
			GameState.PHASE_MULLIGAN:
				_prompt.text = "%s: keep this hand?" % who
				_action("Keep", func() -> void: keep_pressed.emit(slot, true))
				_action("Mulligan", func() -> void: keep_pressed.emit(slot, false))
			GameState.PHASE_SELECT:
				_prompt.text = "%s: click one of your heroes to activate it" % who
				if engine.selectable_heroes(state, slot).is_empty():
					_action("No hero can act", func() -> void: no_hero_pressed.emit(slot))
			GameState.PHASE_PREROLL:
				var h: HeroState = state.active_hero(slot)
				_prompt.text = "%s: Roll or Stay with %s?" % [who, hero_name(h)]
				_action("%s · Roll" % who, func() -> void: choice_pressed.emit(slot, true))
				var stay: Button = _action("%s · Stay" % who, func() -> void: choice_pressed.emit(slot, false))
				stay.disabled = h.zone == HeroState.ZONE_STRIP
				if stay.disabled:
					stay.tooltip_text = "A hero in the start zone must roll"
			GameState.PHASE_ROLL:
				_prompt.text = "%s: drag %s to aim, release to lock it in" % [who, hero_name(state.active_hero(slot))]
		break
	if _in_card_round():
		var slot: int = state.to_act
		if local_slots.has(slot):
			if not any_local:
				_prompt.text = "%s: play a card or pass%s" % [player_name(slot), _battle_suffix()]
			for a: Dictionary in engine.fx.usable_abilities(state, slot):
				var h: HeroState = state.hero(str(a["hero"]))
				var c: CardDef = engine.catalog.get_card(str(a["card"]))
				var e: FxEffect = a["effect"]
				var label: String = "%s: %s" % [hero_name(h) if h != null else (c.name if c != null else "?"), e.line.get_slice(":", 1).strip_edges()]
				var ab: Button = _action(label, func() -> void: ability_pressed.emit(slot, str(a["hero"]), str(a["card"]), JsonUtil.as_int(a["index"])))
				if c != null:
					ab.tooltip_text = c.text
			var pass_btn: Button = _action("Pass  (Space)", func() -> void: pass_pressed.emit(slot))
			pass_btn.add_theme_color_override("font_color", Palette.GOLD)
		elif not any_local:
			_prompt.text = "%s is playing…%s" % [player_name(slot), _battle_suffix()]
	elif not any_local:
		if state.phase == GameState.PHASE_ROLL and state.awaiting_roll:
			_prompt.text = "Rolling…"
		else:
			_prompt.text = "Waiting for the opponent…"


## Setup (GDD 7): stages, then cores, placed in turn. The tray lists what is left; the picked one
## is gold, its legal hexes light up on the table.
func _setup_prompt() -> void:
	var who: int = state.setup_turn
	var stages: bool = state.phase == GameState.PHASE_SETUP_STAGES
	if not local_slots.has(who):
		_prompt.text = "%s is placing a %s…" % [player_name(who), "stage" if stages else "core"]
		return
	_prompt.text = ("%s: place a stage in the middle third" if stages else "%s: place a core in the opponent's half") % player_name(who) \
		+ "  ·  pick one below, click a highlighted hex"
	for id: String in setup_items(state, who):
		var b: Button = _action(_setup_label(id), func() -> void: setup_item_pressed.emit(id))
		if id == setup_pick:
			b.add_theme_color_override("font_color", Palette.GOLD)
			b.add_theme_stylebox_override("normal", UiTheme.box(Palette.BUTTON, 3, Palette.GOLD))
		var tip: String = _setup_tip(id)
		if not tip.is_empty():
			b.tooltip_text = tip


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


func _process(delta: float) -> void:
	if _hand_box == null:
		return
	# Up while the mouse is near the bottom of the screen, else only the tops of the cards show.
	var up: bool = get_local_mouse_position().y > size.y - CARD_SIZE.y - 70.0
	var target: float = 0.0 if up else CARD_SIZE.y - 24.0
	_hand_drop = move_toward(_hand_drop, target, delta * 600.0)
	_hand_box.position.y = size.y - CARD_SIZE.y - 12.0 + _hand_drop


func _battle_suffix() -> String:
	if state.phase != GameState.PHASE_BATTLE or state.battle_index < 0 or state.battle_index >= state.battles.size():
		return ""
	var names := PackedStringArray()
	for id: String in JsonUtil.as_strings(state.battles[state.battle_index].get("heroes", [])):
		var h: HeroState = state.hero(id)
		if h != null:
			names.append(hero_name(h))
	return "   ·   BATTLE %d/%d: %s" % [state.battle_index + 1, state.battles.size(), " vs ".join(names)]


func _action(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	_actions.add_child(b)
	return b


# --- hand ------------------------------------------------------------------------

func _refresh_hand() -> void:
	_clear(_hand)
	var slot: int = hand_slot()
	if slot < 0 or state.turn == 0 and state.phase != GameState.PHASE_MULLIGAN:
		return
	# No cards are played while heroes are picked and aimed; keep the strip free to grab balls.
	if state.phase == GameState.PHASE_SELECT or state.phase == GameState.PHASE_ROLL and not state.rolled:
		return
	var p: PlayerState = state.player(slot)
	var can_play: bool = _in_card_round() and state.to_act == slot and state.pending.is_empty()
	for cid: String in p.hand:
		_hand.add_child(_card_button(slot, cid, can_play and _affordable(p, cid)))


func _affordable(p: PlayerState, cid: String) -> bool:
	var c: CardDef = engine.catalog.get_card(cid)
	return c != null and c.cost <= p.energy


func _card_button(slot: int, cid: String, enabled: bool) -> Button:
	var c: CardDef = engine.catalog.get_card(cid)
	var b := Button.new()
	b.custom_minimum_size = CARD_SIZE
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 15)
	if c == null:
		b.text = cid
		return b
	b.text = "%s\n%d · %s" % [c.name, c.cost, c.type]
	b.tooltip_text = "%s  (%s, %s, cost %d)\n%s" % [c.name, c.type, c.color, c.cost, c.text]
	var col: Color = Palette.hero(c.color)
	var normal: StyleBoxFlat = UiTheme.box(Palette.BUTTON, 3, Color(0, 0, 0, 0), 8, 6)
	normal.border_width_top = 4
	normal.border_color = col
	b.add_theme_stylebox_override("normal", normal)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Palette.BUTTON_HOVER
	b.add_theme_stylebox_override("hover", hover)
	var off: StyleBoxFlat = normal.duplicate()
	off.bg_color = Color("201b17")
	b.add_theme_stylebox_override("disabled", off)
	b.disabled = not enabled
	b.add_theme_color_override("font_disabled_color", Palette.MUTED)
	b.pressed.connect(func() -> void: card_pressed.emit(slot, cid))
	return b


# --- damage choice ------------------------------------------------------------------

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
	var title := Label.new()
	title.theme_type_variation = &"Big"
	title.text = "%d DMG" % amount
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog_box.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = &"Muted"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.text = "%s lost the battle. Where does the hit from %s go?" % [player_name(who), hero_name(winner) if winner != null else "?"]
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog_box.add_child(sub)
	var p: PlayerState = state.player(who)
	var deck_btn := Button.new()
	deck_btn.text = "Deck  (%d cards, %d in hand)" % [p.deck.size(), p.hand.size()]
	deck_btn.pressed.connect(func() -> void: damage_pressed.emit(who, "deck"))
	_dialog_box.add_child(deck_btn)
	for id: String in JsonUtil.as_strings(d.get("targets", [])):
		var h: HeroState = state.hero(id)
		if h == null:
			continue
		var b := Button.new()
		b.text = "%s  (HP %d → %d)" % [hero_name(h), h.hp, maxi(h.hp - amount, 0)]
		b.pressed.connect(func() -> void: damage_pressed.emit(who, id))
		_dialog_box.add_child(b)


## A card effect asks for a hero, core, card or branch (hexes are clicked on the table).
func _choose_dialog(d: Dictionary, who: int) -> void:
	var kind: String = str(d.get("kind", ""))
	if kind == "hex":
		return
	_dialog.visible = true
	var title := Label.new()
	title.theme_type_variation = &"Big"
	title.text = str(d.get("prompt", "Choose"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dialog_box.add_child(title)
	var sub := Label.new()
	sub.theme_type_variation = &"Muted"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ctx: Dictionary = JsonUtil.as_dict(JsonUtil.as_dict(d.get("resume", {})).get("ctx", {}))
	sub.text = "%s  ·  %s" % [player_name(who), _card_name(str(ctx.get("card", "")))]
	_dialog_box.add_child(sub)
	var options: Array = JsonUtil.as_array(d.get("options", []))
	for i: int in options.size():
		var o: Variant = options[i]
		var b := Button.new()
		match kind:
			"hero":
				var h: HeroState = state.hero(str(o))
				b.text = "%s  (HP %d)" % [hero_name(h), h.hp] if h != null else str(o)
			"core":
				var c: CoreState = state.core(str(o))
				b.text = "%s core at %s" % ["face-up" if c != null and c.face_up else "face-down", str(c.hex) if c != null else "?"]
			"card":
				b.text = _card_name(str(o))
			_:
				b.text = str(o)
		var value: Variant = i if kind == "option" else o
		b.pressed.connect(func() -> void: choose_pressed.emit(who, value))
		_dialog_box.add_child(b)


# --- log and end -----------------------------------------------------------------------

func _refresh_log() -> void:
	var lines := PackedStringArray()
	for e: Dictionary in state.log:
		var s: String = _describe(e)
		if not s.is_empty():
			lines.append(s)
	_log_line.text = ("≡  " + lines[lines.size() - 1]) if not lines.is_empty() else "≡"
	var start: int = maxi(0, lines.size() - 16)
	_log_full.text = "\n".join(lines.slice(start))


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


func _refresh_over() -> void:
	_over.visible = state.is_over()
	if not _over.visible:
		return
	var reasons: Dictionary = {"ko": "all heroes KO", "stages": "stages claimed", "deckout": "deck-out",
		"surrender": "surrender", "draw": "draw"}
	if state.winner < 0:
		_over_title.text = "DRAW"
	else:
		_over_title.text = "%s WINS" % player_name(state.winner).to_upper()
		_over_title.add_theme_color_override("font_color", Palette.team(state.team_of(state.winner)))
	_over_info.text = "%s  ·  turn %d" % [str(reasons.get(state.result, state.result)), state.turn]


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
