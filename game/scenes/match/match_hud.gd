class_name MatchHud
extends Control
## Match UI (GDD 11) in the web app's look ("Arena Rush", the in-game UI mockup A): a phase
## ribbon on top, each player's roster of hero slices in the top corners (own left, opponent
## right), a prompt bottom left, the buttons that make sense now bottom right, the hand as a
## fan of card images at the bottom, banners for battles, ring-outs, KOs and claims, the damage
## and choice dialogs and the end screen. It only reads the GameState and emits what was
## clicked; the match scene turns that into moves.

signal pass_pressed(slot: int)
## Start: the chosen hero and whether it rolls are locked in (CONFIRM).
signal pick_confirmed(slot: int, hero_id: String, roll: bool)
## A Roll / Stay under a hovered ball picked that hero (Start).
signal ball_choice_made(hero_id: String)
signal keep_pressed(slot: int, keep: bool)
signal no_hero_pressed(slot: int)
## A card from the hand goes on `hero_id` ("" lets the engine pick, when it can only go one way).
signal card_pressed(slot: int, card_id: String, hero_id: String)
## Choosing a hero for a card started, changed or ended (target_heroes empty).
signal targeting_changed
## The battle camera switch (next to the battle bar) was clicked.
signal battle_cam_pressed
## A battle was decided (the BATTLE! banner): its index and the winning team (-1: a tie).
signal battle_resolved(index: int, winner_team: int)
signal damage_pressed(slot: int, target: String)
## Answer to a "choose" decision (hero, core, card id or branch index; hexes go by click).
signal choose_pressed(slot: int, value: Variant)
signal ability_pressed(slot: int, hero_id: String, card_id: String, index: int)
signal hero_clicked(hero_id: String)
signal hero_hovered(hero_id: String)
## A stage or core in the board strip is hovered: its hexes ([] when the mouse left).
signal board_hovered(hexes: Array[Vector2i])
signal menu_pressed
signal rematch_pressed
signal watch_replay_pressed
signal new_match_pressed
## Setup: the player picked which stage or core to place next.
signal setup_item_pressed(id: String)

const PHASES: Array[String] = [GameState.PHASE_START, GameState.PHASE_PREROLL,
	GameState.PHASE_ROLL, GameState.PHASE_POSTROLL, GameState.PHASE_BATTLE, GameState.PHASE_END]
## The ribbon shows the six phases as they are.
const RIBBON_PHASES: Array[String] = PHASES
const ROSTER_WIDTH: float = 360.0
const SLICE_HEIGHT: float = 70.0
const CARD_SIZE := Vector2(128, 178)
## Height of the hand strip; the cards stick out of the bottom of the screen a little.
const HAND_HEIGHT: float = 210.0
## The hand's width; the deck and the graveyard stand right of it (Marko 2026-10-26).
const HAND_WIDTH: float = 760.0
const BANNER_TIME: float = 0.8
## Phase call-outs stay a little longer, to be read.
const PHASE_BANNER_TIME: float = 3.0
## Start too: every phase is called out long enough to notice (Marko 2026-10-26).
const START_BANNER_TIME: float = 3.0
## BATTLE! stays long enough to read both sides' Power.
const BATTLE_BANNER_TIME: float = 1.6
## How far a hovered hand card rises.
const LIFT: float = 56.0
## Log events that get a banner (the rest only go to the log).
const BANNER_EVENTS: Array[String] = ["battle", "battle_locked", "battle_tie_break", "ring_out", "ko", "stage_claimed", "triggered",
	"damage", "deck_damage"]

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
## Only watching (a spectator): no prompts, no buttons, "WATCHING" instead.
var spectating: bool = false
## Text of the end screen's first button; "" hides it (an online guest waits for the host).
var rematch_text: String = "Rematch"
## End screen: NEW MATCH back to the Play setup (local matches only).
var new_match: bool = true
## Setup: the stage or core the local player places next (set by the match scene).
var setup_pick: String = ""
## The match summary (MatchRecord.summary) shown on the end screen; set by the match scene.
var end_summary: Dictionary = {}
## The series line on the end screen ("SERIES 1–0 · GAME 2 NEXT"), set by the match scene.
var series_text: String = ""

## How far the hand is lowered (0 = up); it drops when the mouse is over the table (GDD 11).
var _hand_drop: float = 0.0
var _hand_box: Control
var _hand: Control
var _hand_title: Label
var _mulligan_row: HBoxContainer
## When the dealt starting hand has settled (msec), and the last time its buttons faded in.
var _mulligan_ready_at: int = 0
var _mulligan_faded_in: int = -1
## The starting hand flew in already (it is dealt once; a refresh must not replay it).
var _hand_dealt: bool = false
var _hand_sig: String = ""
var _ribbon: HBoxContainer
var _rosters: Array[VBoxContainer] = []
var _kicker: Label
## The move timer over the prompt (set_clock).
var _clock: Label
var _prompt: Label
var _detail: Label
var _actions: VBoxContainer
var _key_hint: Label
var _fps: Label
var _tray: HBoxContainer
## Energy, bottom left: yours (big) and the opponent's (small, red) above it.
var _energy: EnergyDial
var _energy_them: EnergyDial
var _energy_them_label: Label
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
## The phase last called out by a banner.
var _called_phase: String = ""
## Choosing a hero for a card: whose card, which, the heroes it can go on, why not the others.
var target_slot: int = -1
## Select: the hero each local player has chosen but not yet confirmed (slot -> hero id).
var picks: Dictionary = {}
## Start: whether each local player's pick rolls (slot -> bool; missing = rolls).
var pick_rolls: Dictionary = {}
var _piles: VBoxContainer
var _prompt_card: PanelContainer
## The graveyard pile, left of the hand.
var _grave_spot: Control
var _ball_choice: HBoxContainer
var _choice_hero: String = ""
var _choice_left_at: int = 0
## How long Roll / Stay under a ball stays after the mouse leaves the ball.
const CHOICE_GRACE: float = 0.6
var target_cid: String = ""
var target_heroes: PackedStringArray = PackedStringArray()
var _target_why: Dictionary = {}
var _last_why_by: Dictionary = {}
var _aim_line: Control
## Under the phase ribbon while a battle is fought: which one and who with what Power.
var _battle_bar: HBoxContainer
## Stages and your cores under the ribbon (_refresh_board).
var _board: VBoxContainer
var _board_sig: String = ""
## The battle camera is on (set by the match): letterbox, only the fighting heroes in the rosters.
var battle_cam: bool = false
var _letterbox: Array[ColorRect] = []
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
	# A chosen but unconfirmed hero only lasts the Select phase.
	if state.phase != GameState.PHASE_START and not picks.is_empty():
		picks.clear()
	# Choosing a hero for a card ends when the card can no longer be played.
	if is_targeting() and not (_in_card_round() and state.to_act == target_slot and state.pending.is_empty()
			and state.player(target_slot).hand.has(target_cid)):
		target_cid = ""
		target_slot = -1
		target_heroes = PackedStringArray()
		targeting_changed.emit()
	# A new phase is called out in the middle (not on the first look, e.g. a loaded match).
	if _ribbon_phase(state.phase) != _ribbon_phase(_called_phase) or _called_phase.is_empty():
		# Not while a replay rewinds (its log gets shorter).
		# End is quiet (GDD 11): what it did shows through the log's own banners.
		if not _called_phase.is_empty() and PHASES.has(state.phase) and state.phase != GameState.PHASE_END and state.log.size() >= _log_seen \
				and GameSettings.banners() == "all":
			banner("%s PHASE" % _ribbon_phase(state.phase).to_upper(), Palette.PANEL_SOLID, "TURN %d" % state.turn, "", START_BANNER_TIME if state.phase == GameState.PHASE_START else PHASE_BANNER_TIME)
		_called_phase = state.phase
	else:
		_called_phase = state.phase
	_scan_log()
	_refresh_ribbon()
	_refresh_battle_bar()
	_refresh_board()
	_refresh_energy()
	for slot: int in state.players.size():
		if slot < _rosters.size():
			_fill_roster(_rosters[slot], slot)
	# The hand first: a freshly dealt starting hand says when its buttons may come.
	_refresh_hand()
	_refresh_prompt()
	_prompt_card.visible = not (_prompt.text.is_empty() and _detail.text.is_empty())
	_refresh_piles()
	_refresh_dialog()
	_refresh_over()


## Your energy on the big dial (the hand's owner, else the first local seat), the opponent's on
## the small red one with their name. Hidden before the first turn.
func _refresh_energy() -> void:
	var on: bool = state.turn > 0 and not state.players.is_empty()
	_energy.visible = on
	_energy_them.visible = on
	_energy_them_label.visible = on
	if not on:
		return
	var mine: int = hand_slot()
	if mine < 0:
		mine = local_slots[0] if not local_slots.is_empty() else 0
	var them: int = engine.other_slot(state, mine)
	var cap: int = mini(state.turn, state.settings.max_energy)
	_energy.set_value(state.player(mine).energy, cap, state.settings.max_energy)
	_energy_them.set_value(state.player(them).energy, cap, state.settings.max_energy)
	_energy_them_label.text = "%s  %d/%d" % [player_name(them).to_upper(), state.player(them).energy, cap]


## "BATTLE 1 / 2 · LUFFY 5000 VS GIORNO 4000", each side in its team's colour.
func _refresh_battle_bar() -> void:
	for c: Node in _battle_bar.get_children():
		c.queue_free()
	var on: bool = state.phase == GameState.PHASE_BATTLE and state.battle_index >= 0 and state.battle_index < state.battles.size()
	_battle_bar.visible = on
	for bar: ColorRect in _letterbox:
		bar.visible = on and battle_cam
	if not on:
		return
	_battle_bar.add_child(UiShape.chip("BATTLE %d / %d" % [state.battle_index + 1, state.battles.size()], Palette.ACCENT, Palette.FG, 20, 32.0, 16.0))
	var sides: Array[PackedStringArray] = [PackedStringArray(), PackedStringArray()]
	for hid: String in JsonUtil.as_strings(state.battles[state.battle_index].get("heroes", [])):
		var h: HeroState = state.hero(hid)
		if h != null:
			sides[clampi(state.team_of(h.owner), 0, 1)].append("%s %d" % [hero_name(h).to_upper(), engine.stat(state, h, "pwr")])
	for t: int in 2:
		if t == 1:
			_battle_bar.add_child(UiShape.chip("VS", Palette.PANEL_SOLID, Palette.MUTED, 16, 32.0, 10.0))
		_battle_bar.add_child(UiShape.chip("  ·  ".join(sides[t]), Palette.PANEL_SOLID, Palette.team(t).lightened(0.25), 20, 32.0, 16.0))
	# The camera switch: on the battle, or the whole table (key in Settings → Keys).
	var key: String = GameSettings.key_name(GameSettings.key("battle_cam"))
	var sw: UiShape = UiShape.chip(("● BATTLE CAM" if battle_cam else "○ TABLE") + "  ·  " + key,
		Palette.GOLD if battle_cam else Palette.SURFACE_2, Color.BLACK if battle_cam else Palette.FG, 16, 32.0, 14.0)
	sw.mouse_filter = Control.MOUSE_FILTER_STOP
	sw.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sw.tooltip_text = "Battle camera on or off"
	sw.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			battle_cam_pressed.emit())
	_battle_bar.add_child(sw)
	_battle_bar.mouse_filter = Control.MOUSE_FILTER_PASS


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
	# Below the battle bar when one shows.
	var base: float = 108.0 if _battle_bar.visible else 70.0
	_toast_box.position.y = base - 6.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_box, "position:y", base, 0.12).from(base - 18.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(1.5)
	_toast_tween.tween_property(_toast_box, "modulate:a", 0.0, 0.4)


## A slanted band across the screen (BATTLE!, RING-OUT …): in, hold, out. Queued.
func banner(title: String, color: Color, left: String = "", right: String = "", hold: float = BANNER_TIME) -> void:
	# Banners can be cut down to the big moments, or switched off (Settings → Interface).
	if GameSettings.banners() == "off":
		return
	_banners.append({"title": title, "color": color, "left": left, "right": right, "hold": hold})
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
	# Thin black bars top and bottom while the battle camera is on (under everything else).
	for bottom: bool in [false, true]:
		var bar := ColorRect.new()
		bar.color = Color(0, 0, 0, 0.85)
		bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE if bottom else Control.PRESET_TOP_WIDE)
		bar.offset_top = -26.0 if bottom else 0.0
		bar.offset_bottom = 0.0 if bottom else 26.0
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.visible = false
		add_child(bar)
		_letterbox.append(bar)
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
			col.offset_left = -ROSTER_WIDTH - 14
			col.offset_right = -14
			col.offset_top = 58
			# A wider row (an ability tab) grows to the left, onto the table, not off the screen.
			col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		add_child(col)
		_rosters.append(col)

	# Bottom left: what the game wants now.
	# Bottom left corner: your energy big, the opponent's small and red just above it.
	_energy = EnergyDial.new()
	_energy.custom_minimum_size = Vector2(150, 150)
	_energy.size = Vector2(150, 150)
	_energy.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_energy.position = Vector2(14, -164)
	add_child(_energy)
	_energy_them = EnergyDial.new()
	_energy_them.color = Palette.ACCENT
	_energy_them.number_color = Palette.FG
	_energy_them.size = Vector2(52, 52)
	_energy_them.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_energy_them.position = Vector2(20, -226)
	add_child(_energy_them)
	_energy_them_label = UiTheme.label("", 15, Palette.ACCENT)
	_energy_them_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_energy_them_label.position = Vector2(80, -210)
	add_child(_energy_them_label)

	var prompt_col := VBoxContainer.new()
	prompt_col.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	prompt_col.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt_col.position = Vector2(180, -18)
	prompt_col.custom_minimum_size = Vector2(270, 0)
	prompt_col.add_theme_constant_override("separation", 4)
	prompt_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(prompt_col)
	_clock = UiTheme.label("", 22, Palette.GOLD)
	prompt_col.add_child(_clock)
	# What the game asks for sits in a card above the buttons, bottom right (Marko 2026-10-26),
	# like the Start block: one place to look, and room by the hand for the graveyard.
	_prompt_card = PanelContainer.new()
	var pc_sb := StyleBoxFlat.new()
	pc_sb.bg_color = Color(0.08, 0.067, 0.06, 0.92)
	pc_sb.border_color = Palette.GOLD
	pc_sb.border_width_left = 4
	pc_sb.content_margin_left = 12
	pc_sb.content_margin_right = 12
	pc_sb.content_margin_top = 8
	pc_sb.content_margin_bottom = 8
	_prompt_card.add_theme_stylebox_override("panel", pc_sb)
	_prompt_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pcol := VBoxContainer.new()
	pcol.add_theme_constant_override("separation", 2)
	pcol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_card.add_child(pcol)
	_kicker = UiTheme.label("", 13, Palette.GOLD)
	pcol.add_child(_kicker)
	_prompt = UiTheme.label("", 24)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt.custom_minimum_size = Vector2(266, 0)
	pcol.add_child(_prompt)
	_detail = Label.new()
	_detail.add_theme_color_override("font_color", Color("b9b4ab"))
	_detail.add_theme_font_size_override("font_size", 14)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.custom_minimum_size = Vector2(266, 0)
	pcol.add_child(_detail)

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
	right.add_child(_prompt_card)
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

	# Frames per second, top right corner (Settings → Interface).
	_fps = Label.new()
	_fps.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps.position = Vector2(-8, 2)
	_fps.add_theme_color_override("font_color", Palette.DIM)
	_fps.add_theme_font_size_override("font_size", 11)
	_fps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps.visible = GameSettings.show_fps()
	add_child(_fps)

	# Setup tray: stages / cores still to place, bottom centre.
	_tray = HBoxContainer.new()
	_tray.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tray.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tray.position = Vector2(0, -30)
	_tray.alignment = BoxContainer.ALIGNMENT_CENTER
	_tray.add_theme_constant_override("separation", 8)
	add_child(_tray)

	# The deck and the graveyard of the player whose hand shows: the graveyard left of the hand,
	# the deck right of it (Marko 2026-10-26).
	_piles = VBoxContainer.new()
	_piles.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_piles.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_piles.position = Vector2(HAND_WIDTH * 0.5 + 14.0, -16.0)
	_piles.add_theme_constant_override("separation", 18)
	_piles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_piles)
	_grave_spot = Control.new()
	_grave_spot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_grave_spot.position = Vector2(-HAND_WIDTH * 0.5 - 76.0, -94.0)
	_grave_spot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grave_spot)
	# The hand: a fan of cards at the bottom; it slides down when the mouse is over the table.
	_hand_box = Control.new()
	_hand_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hand_box.position = Vector2(-HAND_WIDTH * 0.5, -HAND_HEIGHT)
	_hand_box.size = Vector2(HAND_WIDTH, HAND_HEIGHT)
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
	_hand_title.position = Vector2(-300, -96)
	_hand_title.size = Vector2(600, 50)
	_hand_title.visible = false
	_hand_box.add_child(_hand_title)
	# Mulligan: KEEP and NEW HAND sit right under the cards.
	_mulligan_row = HBoxContainer.new()
	_mulligan_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_mulligan_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_mulligan_row.offset_top = HAND_HEIGHT + 28
	_mulligan_row.offset_bottom = HAND_HEIGHT + 80
	_mulligan_row.add_theme_constant_override("separation", 16)
	_mulligan_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_mulligan_row.visible = false
	_hand_box.add_child(_mulligan_row)

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

	_battle_bar = HBoxContainer.new()
	_battle_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_battle_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_battle_bar.position = Vector2(0, 62)
	_battle_bar.add_theme_constant_override("separation", 0)
	_battle_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_battle_bar.visible = false
	add_child(_battle_bar)

	_board = VBoxContainer.new()
	_board.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_board.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_board.position = Vector2(0, 62)
	_board.add_theme_constant_override("separation", 4)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_board)

	_aim_line = Control.new()
	_aim_line.set_anchors_preset(Control.PRESET_FULL_RECT)
	_aim_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_line.draw.connect(_draw_aim_line)
	add_child(_aim_line)

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
		var now: int = RIBBON_PHASES.find(_ribbon_phase(state.phase))
		for i: int in RIBBON_PHASES.size():
			var fill: Color = Palette.PANEL_SOLID
			var fg: Color = Palette.MUTED
			if i < now:
				fill = Palette.SURFACE_2
				fg = Palette.DIM
			elif i == now:
				fill = Palette.FG
				fg = Color.BLACK
			var label: String = RIBBON_PHASES[i].to_upper()
			var w: float = UiTheme.display_heavy().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 34.0
			var chev: UiShape = UiShape.make(UiShape.Kind.CHEVRON, fill, Vector2(w, 30), label, 15, fg)
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
	# Energy is in the bottom left corner (_refresh_energy); the stage stars sit by the name.
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

	var align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	if not p.assists.is_empty():
		var assists := Label.new()
		assists.theme_type_variation = &"Muted"
		assists.text = "Assists: " + ", ".join(_card_names(p.assists))
		assists.horizontal_alignment = align
		assists.tooltip_text = _card_tip(_card_texts(p.assists))
		assists.mouse_filter = Control.MOUSE_FILTER_PASS
		col.add_child(assists)
	for h: HeroState in state.heroes_of(slot):
		# In the battle camera only the heroes fighting show.
		if battle_cam and not _in_battle(h):
			continue
		col.add_child(_hero_slice(h, right))
	# Under the third hero, so it does not push the heroes down (playtest 2026-10-30).
	if not p.inventory.is_empty():
		var inv := Label.new()
		inv.add_theme_color_override("font_color", Palette.GOLD)
		inv.add_theme_font_size_override("font_size", 13)
		inv.text = "%d core%s to put back" % [p.inventory.size(), "" if p.inventory.size() == 1 else "s"]
		inv.horizontal_alignment = align
		col.add_child(inv)
	# Your own deck and graveyard stand as piles by the hand (_refresh_piles); the counts here
	# are for the other side (and for two players at one screen).
	if local_slots.size() == 1 and local_slots[0] == slot:
		return
	# Under the heroes: what the player holds; the graveyard's cards on hover.
	var info := Label.new()
	info.add_theme_color_override("font_color", Palette.MUTED)
	info.add_theme_font_size_override("font_size", 13)
	info.text = "Hand %d  ·  Deck %d  ·  Grave %d" % [p.hand.size(), p.deck.size(), p.graveyard.size()]
	info.horizontal_alignment = align
	info.tooltip_text = "Graveyard: " + (", ".join(_card_names(p.graveyard)) if not p.graveyard.is_empty() else "empty")
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	# A click shows the cards (open_graveyard).
	info.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var gslot: int = slot
	info.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			open_graveyard(gslot))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_right" if right else "margin_left", 18)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(info)
	col.add_child(pad)


func _hero_slice(h: HeroState, right: bool) -> Control:
	var card: CardDef = engine.stat_card(h)
	var hero_color: Color = Palette.hero(card.color if card != null else "")
	var expanded: bool = _is_expanded(h)
	var active: bool = shown_active(h.owner) == h.id
	var ko: bool = h.is_ko()
	var pickable: bool = _pickable(h)
	var in_battle: bool = _in_battle(h)

	var s := HeroSlice.new()
	s.set_mirrored(right)
	s.art = db.thumb(card.id) if db != null and card != null else null
	s.art_region = HeroSlice.region_for(s.art)
	s.art_fallback = hero_color.darkened(0.3)
	s.bg = Color("222222") if h.id == hover_hero else Palette.PANEL_SOLID
	s.color_edge = hero_color
	if ko:
		s.art_tint = Color(0.35, 0.35, 0.35)
		s.modulate.a = 0.6
	if active:
		s.outline = Palette.GOLD
	elif pickable:
		var chosen_pick: bool = picks.get(h.owner, "") == h.id
		s.outline = Color("ffd36a") if chosen_pick else Color(Palette.GOLD, 0.55)
		s.outline_width = 3.5 if chosen_pick else 2.0
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
		s.tooltip_text = _card_tip("%s\n%s" % [card.name, card.text])

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
	# Picking a hero for a card: who can take it (the one under the mouse is chosen), who not.
	if is_targeting() and h.owner == target_slot and not ko:
		if target_heroes.has(h.id):
			var chosen: bool = h.id == hover_hero
			tag = UiShape.chip("CHOSEN" if chosen else "CAN TAKE IT", Palette.GOLD if chosen else Color(Palette.GOLD, 0.25),
				Color.BLACK if chosen else Palette.GOLD, 12, 20.0, 8.0)
			s.outline = Color("ffd36a") if chosen else Color(Palette.GOLD, 0.8)
			s.outline_width = 3.0
		else:
			var why: String = _short_why(str(_target_why.get(h.id, "")))
			tag = UiShape.chip(why.to_upper(), Palette.SURFACE_2, Palette.MUTED, 11, 20.0, 8.0)
			s.modulate.a = 0.45
	elif is_targeting():
		s.modulate.a = 0.6
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
	# Statuses show as chips under the panel (_effect_chips).
	if ko:
		extra.text = "Knocked out"
		extra.add_theme_color_override("font_color", Palette.MUTED)
	elif not h.equipment.is_empty():
		# Equipment as mini cards after the core slots, empty slots dashed (Marko 2026-10-26):
		# hover = its text, right click = the big card.
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(6, 0)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bottom.add_child(gap)
		for i: int in state.settings.equipment_limit:
			bottom.add_child(_equip_mini(h.equipment[i] if i < h.equipment.size() else ""))
	extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	bottom.add_child(extra)
	if expanded and not ko:
		var stats := RichTextLabel.new()
		stats.bbcode_enabled = true
		# Fixed to the panel's width (it never pushes onto the art at the far end).
		stats.fit_content = false
		stats.custom_minimum_size = Vector2(0, 20)
		stats.clip_contents = true
		stats.scroll_active = false
		stats.autowrap_mode = TextServer.AUTOWRAP_OFF
		stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stats.add_theme_font_override("normal_font", UiTheme.display_italic())
		stats.add_theme_font_size_override("normal_font_size", 15)
		stats.add_theme_color_override("default_color", Palette.FG)
		var parts := PackedStringArray()
		for key: String in ["pwr", "dmg", "rng", "kb"]:
			var value: int = engine.stat(state, h, key)
			var text: String = "%s %d" % [key.to_upper(), value]
			# Green up, red down against the card, whatever moved it: cores, equipment, effects
			# (playtest 2026-10-30: Sandai Kitetsu's +3 DMG stayed white).
			var by: int = value - engine.base_stat(state, h, key)
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
	# The hero's ability as a tab on the panel's outer end, lasting effects as chips under it.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", -6)
	row.layout_direction = Control.LAYOUT_DIRECTION_RTL if right else Control.LAYOUT_DIRECTION_LTR
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(wrap)
	var tabs: Control = _ability_tabs(h, active and not ko, right)
	if tabs != null:
		row.add_child(tabs)
	var out := VBoxContainer.new()
	out.add_theme_constant_override("separation", 3)
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	out.size_flags_horizontal = Control.SIZE_SHRINK_END if right else Control.SIZE_SHRINK_BEGIN
	out.add_child(row)
	var chips: Control = _effect_chips(h, right)
	if chips != null:
		out.add_child(chips)
	return out


## The abilities on a hero's own card and its evolutions: [{card, index, effect, n}] (n: which
## ability of that card, for its name).
func _hero_abilities(h: HeroState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array[String] = [h.card_id]
	for e: String in h.evolutions:
		ids.append(e)
	for cid: String in ids:
		var card: CardDef = engine.catalog.get_card(cid)
		if card == null:
			continue
		var n: int = 0
		for i: int in card.effects.size():
			var e: FxEffect = card.effects[i]
			if not e.optional or e.cond == "WIN":
				continue
			out.append({"card": card, "index": i, "effect": e, "n": n})
			n += 1
	return out


## The ability tab(s) by a hero's panel. The activated hero's shows in full in one of three
## states: it can be used now (straw, click to use), not now (grey, with why), used (dim, ✓).
## The others' fold into a small ⚡ with the names on hover. The opponent's never click.
func _ability_tabs(h: HeroState, active: bool, right: bool) -> Control:
	var list: Array[Dictionary] = _hero_abilities(h)
	if list.is_empty():
		return null
	if not active:
		var names := PackedStringArray()
		for a: Dictionary in list:
			names.append(_ability_title(a))
		var fold: UiShape = UiShape.chip("⚡", Palette.SURFACE_2, Palette.MUTED, 16, 30.0, 10.0)
		fold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		fold.tooltip_text = "\n".join(names)
		fold.mouse_filter = Control.MOUSE_FILTER_STOP
		return fold
	var mine: bool = local_slots.has(h.owner)
	var usable: Array[Dictionary] = []
	if mine and _in_card_round() and state.to_act == h.owner and state.pending.is_empty():
		usable = engine.fx.usable_abilities(state, h.owner)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for a: Dictionary in list:
		var card: CardDef = a["card"]
		var e: FxEffect = a["effect"]
		var index: int = a["index"]
		var key: String = "%s|%s|%d" % [h.id, card.id, index]
		var used: bool = e.once and state.abilities_used.has(key)
		var can: bool = false
		for u: Dictionary in usable:
			if str(u["hero"]) == h.id and str(u["card"]) == card.id and JsonUtil.as_int(u["index"]) == index:
				can = true
		var status: String = "CLICK TO USE"
		if used:
			status = "✓ USED"
		elif not can:
			if e.when != state.phase.to_upper():
				status = "%s PHASE ONLY" % e.when
			elif not mine:
				status = "THEIR ABILITY"
			elif state.to_act != h.owner or not _in_card_round():
				status = "NOT YOUR TURN"
			else:
				status = "NOT NOW"
		var bg: Color = Palette.GOLD if can else (Palette.PANEL_SOLID if used else Palette.SURFACE_2)
		var fg: Color = Color.BLACK if can else (Palette.DIM if used else Palette.FG)
		var tab := PanelContainer.new()
		var sb: StyleBoxFlat = UiTheme.slant(bg, 24, 6)
		if used:
			sb.border_color = Palette.LINE
			sb.set_border_width_all(2)
		tab.add_theme_stylebox_override("panel", sb)
		tab.custom_minimum_size = Vector2(176, 0)
		tab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tab.tooltip_text = _card_tip("%s\n%s" % [_ability_title(a), e.line])
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tab.add_child(v)
		var head: String = "ABILITY" + ("  ·  ONCE PER TURN" if e.once else "")
		v.add_child(UiTheme.label(head, 11, fg if can else Palette.MUTED, false))
		var name_l: Label = UiTheme.label(_ability_title(a).to_upper(), 18, fg)
		name_l.clip_text = true
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(name_l)
		var st: Label = UiTheme.label(status, 11, Color.BLACK if can else (Palette.HP if used else Palette.ACCENT), false)
		v.add_child(st)
		for c: Node in v.get_children():
			(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
			(c as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
		if can:
			tab.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var slot: int = h.owner
			tab.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed \
						and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
					ability_pressed.emit(slot, h.id, card.id, index))
			# A slow glow says it is there to be used.
			var glow: Tween = tab.create_tween().set_loops()
			glow.tween_property(tab, "self_modulate", Color(1.25, 1.2, 1.0), 0.8)
			glow.tween_property(tab, "self_modulate", Color.WHITE, 0.8)
		col.add_child(tab)
	return col


## The ball stopped and a "Roll Phase:" card or ability is on offer: the card shows big, the
## options are buttons, "GO ON" declines (a pass).
func _roll_offer_prompt(d: Dictionary, who: int) -> void:
	_kicker.text = "ROLL PHASE"
	_prompt.text = "Your ball stopped"
	_detail.text = "Use a Roll Phase card or ability now, or go on to Postroll."
	var cards: PackedStringArray = JsonUtil.as_strings(d.get("cards", []))
	if cards.is_empty() and JsonUtil.as_strings(d.get("abilities", [])).is_empty():
		# Everyone is asked, so the other side cannot tell an empty offer from a full one.
		_detail.text = "Nothing to use now; on to Postroll in a moment." if GameSettings.auto_pass() else "Nothing to use now."
	for key: String in JsonUtil.as_strings(d.get("abilities", [])):
		var parts: PackedStringArray = key.split("|")
		if parts.size() != 3:
			continue
		var card: CardDef = engine.catalog.get_card(parts[1])
		var title: String = "%s ability" % parts[1]
		if card != null:
			var n: int = 0
			for i: int in parts[2].to_int():
				if i < card.effects.size() and card.effects[i].optional and card.effects[i].cond != "WIN":
					n += 1
			title = card.ability_name(n) if not card.ability_name(n).is_empty() else "%s: Roll ability" % card.name
		var b: Button = _action(title.to_upper(), func() -> void: ability_pressed.emit(who, parts[0], parts[1], parts[2].to_int()), &"Gold")
		if card != null:
			b.tooltip_text = _card_tip(card.text)
	for cid: String in cards:
		var card: CardDef = engine.catalog.get_card(cid)
		var cost: int = engine.card_cost(state, state.player(who), card) if card != null else 0
		_action("PLAY %s  ·  %d" % [(card.name if card != null else cid).to_upper(), cost],
			func() -> void: card_pressed.emit(who, cid, ""), &"Gold")
	if cards.size() == 1 and _big_cid != cards[0]:
		_show_big(cards[0])
	_action("GO ON", func() -> void: pass_pressed.emit(who), &"Primary")


## The ability's name from the card (Card Engine, underlined), else what kind it is.
func _ability_title(a: Dictionary) -> String:
	var card: CardDef = a["card"]
	var e: FxEffect = a["effect"]
	var name: String = card.ability_name(JsonUtil.as_int(a["n"]))
	return name if not name.is_empty() else "%s ability" % e.when.capitalize()


## What lasts on a hero now, as chips under its panel: bonuses for the phase or the turn
## (green up, red down) and statuses with their turns. Null when nothing does.
func _effect_chips(h: HeroState, right: bool) -> Control:
	var items: Array[Array] = []
	for pair: Array in [[h.phase_bonus, "THIS PHASE"], [h.turn_bonus, "THIS TURN"]]:
		var bonus: Dictionary = pair[0]
		for k: Variant in bonus:
			var v: int = JsonUtil.as_int(bonus[k])
			if v != 0:
				items.append(["%+d %s · %s" % [v, str(k).to_upper(), pair[1]], Palette.HP if v > 0 else Palette.ACCENT])
	var names: Dictionary = {"immune_kb": "IMMUNE TO KB", "stun": "STUNNED", "hold_hit": "NO HIT, DOUBLE KB"}
	for k: String in h.statuses:
		var turns: int = h.statuses[k]
		var label: String = str(names.get(k, k.to_upper()))
		items.append([label if turns < 0 else "%s · %d TURN%s" % [label, turns, "" if turns == 1 else "S"], Palette.GOLD])
	if items.is_empty():
		return null
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.layout_direction = Control.LAYOUT_DIRECTION_RTL if right else Control.LAYOUT_DIRECTION_LTR
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for it: Array in items:
		var color: Color = it[1]
		var chip: UiShape = UiShape.chip(str(it[0]), Palette.SURFACE_2, color, 12, 20.0, 8.0)
		row.add_child(chip)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left" if not right else "margin_right", 22)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)
	return pad


## One of a hero's core slots: what the core there does in short ("PWR+2K", green up, red
## down), else an empty outline. Hover gives the core's name.
func _core_slot(core_id: String, hero_color: Color) -> Control:
	var c: CoreState = state.core(core_id) if not core_id.is_empty() else null
	var card: CardDef = engine.catalog.get_card(c.card_id) if c != null else null
	if card == null or card.bonus.is_empty():
		# An empty slot is a small empty slanted box, the size of a core chip.
		var dot: UiShape = UiShape.make(UiShape.Kind.SLANT, hero_color if c != null else Color(0, 0, 0, 0), Vector2(34, 14))
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


func _hero_tag(h: HeroState, active: bool, pickable: bool, in_battle: bool) -> UiShape:
	if h.is_ko():
		return UiShape.chip("KO", Palette.ACCENT_DEEP, Palette.FG, 13, 20.0, 8.0)
	if in_battle:
		return UiShape.chip("BATTLE", Palette.ACCENT, Palette.FG, 13, 20.0, 8.0)
	if active:
		# What the activated hero does this turn, as far as its own player may know.
		if local_slots.has(h.owner) and state.choices.has(h.owner):
			var rolls: bool = state.choices.get(h.owner, false)
			if not rolls:
				return UiShape.chip("STAYS", Palette.SURFACE_2, Palette.FG, 13, 20.0, 8.0)
			if state.phase == GameState.PHASE_ROLL and not state.aims.has(h.owner):
				return UiShape.chip("THROW ▸", Palette.ACCENT, Palette.FG, 13, 20.0, 8.0)
			if state.phase == GameState.PHASE_PREROLL:
				return UiShape.chip("WILL ROLL", Palette.GOLD, Color.BLACK, 13, 20.0, 8.0)
			if state.phase == GameState.PHASE_ROLL:
				return UiShape.chip("ROLLED ✓", Palette.HP, Color.BLACK, 13, 20.0, 8.0)
		return UiShape.chip("ACTIVE", Palette.GOLD, Color.BLACK, 13, 20.0, 8.0)
	if pickable:
		if picks.get(h.owner, "") == h.id:
			return UiShape.chip("CHOSEN", Palette.GOLD, Color.BLACK, 13, 20.0, 8.0)
		return UiShape.chip("PICK", Color(Palette.GOLD, 0.25), Palette.GOLD, 13, 20.0, 8.0)
	if h.tie_turns > 0:
		return UiShape.chip("LOCKED", Palette.SURFACE_2, Palette.FG, 13, 20.0, 8.0)
	if h.zone == HeroState.ZONE_STRIP:
		return UiShape.chip("START", Color(0, 0, 0, 0), Palette.MUTED, 13, 20.0, 8.0)
	return null


func _pickable(h: HeroState) -> bool:
	if state.phase != GameState.PHASE_START or not local_slots.has(h.owner) or state.active.has(h.owner):
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
	return h.id == hover_hero or shown_active(h.owner) == h.id or _in_battle(h)


# --- prompt and actions -------------------------------------------------------------

func _in_card_round() -> bool:
	match state.phase:
		GameState.PHASE_PREROLL, GameState.PHASE_POSTROLL, GameState.PHASE_BATTLE:
			return not state.round_over
	return false


## True when the game waits for something from this slot.
## Space in Start: the first local seat with a picked hero confirms it.
func confirm_pick() -> void:
	for slot: int in local_slots:
		if not _needs_input(slot):
			continue
		var picked: HeroState = state.hero(str(picks.get(slot, "")))
		if picked == null:
			toast("Pick a hero first", Palette.FG)
			return
		var rolls: bool = picked.zone == HeroState.ZONE_STRIP or pick_rolls.get(slot, true) == true
		pick_confirmed.emit(slot, picked.id, rolls)
		return


func _needs_input(slot: int) -> bool:
	match state.phase:
		GameState.PHASE_MULLIGAN:
			return not state.player(slot).mulligan_done
		GameState.PHASE_START:
			return not state.active.has(slot)
		GameState.PHASE_ROLL:
			return state.choices.get(slot, false) and not state.aims.has(slot) and state.active_hero(slot) != null
	return false


func _refresh_prompt() -> void:
	_clear(_actions)
	_clear(_mulligan_row)
	_mulligan_row.visible = false
	_clear(_tray)
	_prompt.text = ""
	_detail.text = ""
	_key_hint.text = ""
	_kicker.text = _ribbon_phase(state.phase).to_upper() if state.turn > 0 or state.phase == GameState.PHASE_MULLIGAN else ""
	if state.is_over() or replay:
		_kicker.text = ""
		return
	if spectating:
		_kicker.text = "WATCHING"
		_prompt.text = "%s vs %s" % [player_name(0), player_name(1)]
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
		# Roll offers of one stop wait together: a local player answers its own, wherever it sits.
		if str(d.get("type", "")) == RulesEngine.DECISION_ROLL_OFFER:
			for slot: int in local_slots:
				var own: int = engine.roll_offer_index(state, slot)
				if own >= 0:
					d = state.pending[own]
					break
		var who: int = JsonUtil.as_int(d.get("player", -1), -1)
		if not local_slots.has(who):
			_prompt.text = "%s is deciding…" % player_name(who)
		elif str(d.get("type", "")) == RulesEngine.DECISION_RETURN_CORE:
			_prompt.text = "Put a core back"
			_detail.text = "%s: click a highlighted hex." % player_name(who)
		elif str(d.get("type", "")) == FxRuntime.DECISION_CHOOSE and str(d.get("kind", "")) == "hex":
			_prompt.text = str(d.get("prompt", "Pick a hex"))
			_detail.text = "%s: click a highlighted hex." % player_name(who)
		elif str(d.get("type", "")) == RulesEngine.DECISION_ROLL_OFFER:
			_roll_offer_prompt(d, who)
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
				# The buttons come once the dealt cards have settled (Marko 2026-10-26).
				var wait_ms: int = _mulligan_ready_at - Time.get_ticks_msec()
				_mulligan_row.visible = wait_ms <= 0
				if wait_ms > 0:
					get_tree().create_timer(wait_ms / 1000.0).timeout.connect(refresh, CONNECT_ONE_SHOT)
				elif _mulligan_faded_in < _mulligan_ready_at:
					_mulligan_faded_in = _mulligan_ready_at
					_mulligan_row.modulate.a = 0.0
					_mulligan_row.create_tween().tween_property(_mulligan_row, "modulate:a", 1.0, 0.25)
				_mulligan_button("NEW HAND", func() -> void: keep_pressed.emit(slot, false), &"")
				_mulligan_button("KEEP THIS HAND", func() -> void: keep_pressed.emit(slot, true), &"Primary")
			GameState.PHASE_START:
				# Pick a hero, say whether it rolls or stays, confirm (GDD 8, 2026-10-26). Everything
				# for it sits in one block bottom right, by the CONFIRM button (Marko 2026-10-26).
				var picked: HeroState = state.hero(str(picks.get(slot, "")))
				_prompt.text = ""
				_detail.text = ""
				if picked == null:
					_start_card(("%s · " % who.to_upper() if many else "") + "START · PICK A HERO", "Pick a hero",
						"Click one of your heroes, on the table or on the left. Hover a ball to say Roll or Stay.")
				else:
					var must_roll: bool = picked.zone == HeroState.ZONE_STRIP
					var rolls: bool = must_roll or pick_rolls.get(slot, true) == true
					_start_card(("%s · " % who.to_upper() if many else "") + "START · PICK A HERO",
						"%s %s" % [hero_name(picked), "rolls into the arena" if rolls else "stays where it is"],
						"Click another hero to change." + (" In the start zone a hero must roll." if must_roll else ""))
					var row := HBoxContainer.new()
					row.add_theme_constant_override("separation", 6)
					row.size_flags_horizontal = Control.SIZE_FILL
					_actions.add_child(row)
					# In the start zone there is nothing to choose: only ROLL (playtest 2026-10-30).
					for roll_choice: bool in ([true] if must_roll else [true, false]):
						var b := Button.new()
						b.text = "ROLL" if roll_choice else "STAY"
						b.focus_mode = Control.FOCUS_NONE
						b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						b.theme_type_variation = &"Gold" if rolls == roll_choice else &""
						var want: bool = roll_choice
						b.pressed.connect(func() -> void:
							pick_rolls[slot] = want
							refresh())
						row.add_child(b)
					_action("CONFIRM %s" % hero_name(picked).get_slice(",", 0).to_upper(), func() -> void: pick_confirmed.emit(slot, picked.id, rolls), &"Primary")
				if engine.selectable_heroes(state, slot).is_empty():
					_action("No hero can act", func() -> void: no_hero_pressed.emit(slot), &"Primary")
			GameState.PHASE_ROLL:
				_prompt.text = "Throw %s" % hero_name(state.active_hero(slot))
				_detail.text = ("%s: " % who if many else "") + "drag the lit ball back and let go. Right click cancels."
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
				# The activated hero's own abilities are on the tab by its panel.
				if h != null and c != null and (c.type == "Hero" or c.type == "Evolution") and state.active.get(h.owner, "") == h.id:
					continue
				# The ability's name (from the card, else its kind), not its fx.
				var title: String = "%s ability" % e.when.capitalize()
				if c != null:
					var n: int = 0
					for i: int in JsonUtil.as_int(a["index"]):
						if c.effects[i].optional and c.effects[i].cond != "WIN":
							n += 1
					if not c.ability_name(n).is_empty():
						title = c.ability_name(n)
				var text: String = "%s: %s" % [hero_name(h) if h != null else (c.name if c != null else "?"), title]
				var ab: Button = _action(text, func() -> void: ability_pressed.emit(slot, str(a["hero"]), str(a["card"]), JsonUtil.as_int(a["index"])), &"Gold")
				if c != null:
					ab.tooltip_text = _card_tip(c.text)
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
		# As wide as the prompt card above it; a long text is cut, not pushed under the deck
		# (playtest 2026-10-30: CONFIRM KAIDO, HYBRID FORM).
		b.custom_minimum_size = Vector2(290, 0)
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.tooltip_text = text
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.pressed.connect(cb)
	_actions.add_child(b)
	return b


func _process(delta: float) -> void:
	if _fps != null and _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	if _hand_box == null or state == null:
		return
	# A card under the mouse shows on the dial what would be left after paying for it.
	if _energy != null and _energy.visible:
		var left: int = -1
		var slot: int = hand_slot()
		if not _hover_cid.is_empty() and slot >= 0 and state.player(slot).hand.has(_hover_cid):
			var c: CardDef = engine.catalog.get_card(_hover_cid)
			if c != null:
				var cost: int = engine.card_cost(state, state.player(slot), c)
				if cost <= _energy.value:
					left = _energy.value - cost
		if left != _energy.preview:
			_energy.preview = left
			_energy.queue_redraw()
	if state.phase == GameState.PHASE_MULLIGAN:
		# The starting hand sits in the middle, big, and stays up.
		_hand_drop = 0.0
		_hand_box.position.y = size.y * 0.5 - HAND_HEIGHT * 0.5
		return
	# Up while the mouse is near the bottom of the screen (or a hero is being picked for a
	# card), else only the tops of the cards show.
	var up: bool = (get_local_mouse_position().y > size.y - HAND_HEIGHT - 40.0 and state.phase != GameState.PHASE_START) or is_targeting()
	if _aim_line != null and (is_targeting() or _aim_line.get_meta("drawn", false)):
		_aim_line.set_meta("drawn", is_targeting())
		_aim_line.queue_redraw()
	var target: float = 0.0 if up else HAND_HEIGHT - 110.0
	_hand_drop = move_toward(_hand_drop, target, delta * 900.0)
	_hand_box.position.y = size.y - HAND_HEIGHT + 30.0 + _hand_drop


# --- hand ------------------------------------------------------------------------

func _refresh_hand() -> void:
	# A new starting hand (mulligan taken) flies in again.
	if state.phase == GameState.PHASE_MULLIGAN and hand_slot() >= 0 and _hand_sig != ",".join(state.player(hand_slot()).hand):
		_hand_sig = ",".join(state.player(hand_slot()).hand)
		_hand_dealt = false
	# A refresh while the starting hand is still flying in would rebuild it in place and cut
	# the deal short (playtest 2026-10-30: the deal was gone); the same cards stay as they are.
	if state.phase == GameState.PHASE_MULLIGAN and _hand_dealt and _hand.get_child_count() > 0 \
			and Time.get_ticks_msec() < _mulligan_ready_at:
		return
	_clear(_hand)
	var mulligan: bool = state.phase == GameState.PHASE_MULLIGAN
	_hand_title.visible = false
	var slot: int = hand_slot()
	if slot < 0 or state.turn == 0 and not mulligan:
		return
	# No cards are played while balls are aimed; keep the strip free to grab them. In Start the
	# hand shows (Roll or Stay is decided there) but stays low, so the balls can be clicked.
	if state.phase == GameState.PHASE_ROLL and not state.rolled:
		return
	var p: PlayerState = state.player(slot)
	if mulligan and not _needs_input(slot):
		return
	_hand_title.visible = mulligan
	var my_round: bool = _in_card_round() and state.to_act == slot and state.pending.is_empty()
	var n: int = p.hand.size()
	var step: float = minf(176.0 if mulligan else 96.0, (HAND_WIDTH - 40.0) / maxf(float(n), 1.0))
	for i: int in n:
		var cid: String = p.hand[i]
		var check: Dictionary = _play_check(slot, cid) if my_round else {}
		var playable: bool = my_round and check.get("ok", false) == true
		var card: Control = _hand_card(slot, cid, playable, my_round, str(check.get("why", "")),
			JsonUtil.as_strings(check.get("heroes", [])))
		var t: float = i - (n - 1) * 0.5
		card.position = Vector2(_hand.size.x * 0.5 + t * step - CARD_SIZE.x * 0.5, 16.0 + (0.0 if mulligan else t * t * 4.0))
		card.rotation_degrees = 0.0 if mulligan else t * 5.0
		if mulligan:
			card.scale = Vector2.ONE * 1.25
		card.set_meta("rest_y", card.position.y)
		_hand.add_child(card)
		# The starting hand flies in from below, one card after another, and settles (once).
		if mulligan and not _hand_dealt:
			var face: Control = card.get_node_or_null("Face") as Control
			if face != null:
				face.position.y = 520.0
				face.modulate.a = 0.0
				var fly: Tween = face.create_tween().set_parallel()
				fly.tween_property(face, "position:y", 0.0, 0.45).set_delay(0.12 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				fly.tween_property(face, "modulate:a", 1.0, 0.2).set_delay(0.12 * i)
		# The card a hero is being chosen for stays up.
		if cid == target_cid and slot == target_slot:
			_lift(card, true, true)
	if mulligan and not _hand_dealt:
		_mulligan_ready_at = Time.get_ticks_msec() + int((0.12 * maxf(float(n) - 1.0, 0.0) + 0.45 + 0.15) * 1000.0)
	if mulligan:
		_hand_dealt = true
	else:
		_hand_dealt = false


## Messages from the engine that still mean "you can play it" (it asks for a choice after).
const PLAY_ASKS: Array[String] = ["choose an assist to replace"]


## Whether `slot` may play `cid` now, asked of the engine itself: the move is tried on a copy of
## the state, once for each hero the card could go on. {"ok", "why" (the engine's reason when
## not), "heroes" (ids it can go on), "why_by" (hero id -> why not, for the others)}.
func _play_check(slot: int, cid: String, as_turn: bool = false) -> Dictionary:
	var heroes := PackedStringArray()
	var why: String = ""
	var why_by: Dictionary = {}
	var targets: Array[String] = []
	for h: HeroState in engine.card_context_heroes(state, slot):
		targets.append(h.id)
	if targets.is_empty():
		targets.append("")
	for hid: String in targets:
		var copy: GameState = GameState.from_dict(state.to_dict())
		if as_turn:
			# Asked for a player whose turn it is not (auto-pass looks at everyone).
			copy.to_act = slot
		var err: String = engine.apply(copy, Move.make(Move.PLAY_CARD, slot, {"card": cid, "hero": hid}))
		for ask: String in PLAY_ASKS:
			if err.begins_with(ask):
				err = ""
		if err.is_empty():
			if not hid.is_empty():
				heroes.append(hid)
		else:
			if why.is_empty():
				why = err
			if not hid.is_empty():
				why_by[hid] = err
	var ok: bool = not heroes.is_empty() or (targets[0].is_empty() and why.is_empty())
	_last_why_by[cid] = why_by
	return {"ok": ok, "why": "" if ok else why, "heroes": heroes, "why_by": why_by}


# --- choosing a hero for a card (mockup HUD 2) -----------------------------------------

## A playable card was clicked: with one hero to go on (or none to name) it is played at once;
## with more, the player picks one on the table or in the roster.
func _card_chosen(slot: int, cid: String, heroes: PackedStringArray) -> void:
	if heroes.size() <= 1:
		cancel_targeting()
		card_pressed.emit(slot, cid, heroes[0] if heroes.size() == 1 else "")
		return
	if cid == target_cid:
		cancel_targeting()
		return
	target_slot = slot
	target_cid = cid
	target_heroes = heroes
	_target_why = _last_why_by.get(cid, {})
	targeting_changed.emit()
	refresh()


func is_targeting() -> bool:
	return not target_cid.is_empty()


func cancel_targeting() -> void:
	if target_cid.is_empty():
		return
	target_cid = ""
	target_slot = -1
	target_heroes = PackedStringArray()
	_target_why = {}
	targeting_changed.emit()
	refresh()


## Plays the card being targeted on `hero_id` if it can go there; true when it did.
func play_target(hero_id: String) -> bool:
	if target_cid.is_empty() or not target_heroes.has(hero_id):
		return false
	var slot: int = target_slot
	var cid: String = target_cid
	cancel_targeting()
	card_pressed.emit(slot, cid, hero_id)
	return true


## The dashed line from the card being targeted to the mouse.
func _draw_aim_line() -> void:
	if target_cid.is_empty():
		return
	var from := Vector2.ZERO
	var found: bool = false
	for c: Node in _hand.get_children():
		if c is Control and str(c.get_meta("cid", "")) == target_cid:
			var card := c as Control
			from = card.get_global_rect().get_center() - _aim_line.get_global_rect().position
			from.y = card.get_global_rect().position.y - _aim_line.get_global_rect().position.y
			found = true
	if not found:
		return
	var to: Vector2 = _aim_line.get_local_mouse_position()
	var mid := Vector2(from.x, minf(from.y, to.y) - 60.0)
	var pts := PackedVector2Array()
	for i: int in 33:
		var t: float = i / 32.0
		pts.append(from.lerp(mid, t).lerp(mid.lerp(to, t), t))
	for i: int in range(0, 32, 2):
		_aim_line.draw_line(pts[i], pts[i + 1], Palette.GOLD, 5.0, true)
	var dir: Vector2 = (pts[32] - pts[30]).normalized()
	var side := Vector2(-dir.y, dir.x)
	_aim_line.draw_colored_polygon(PackedVector2Array([to + dir * 6.0, to - dir * 14.0 + side * 9.0, to - dir * 14.0 - side * 9.0]), Palette.GOLD)


## Where a card picture of `tex` sits in the card slot: aspect kept, centred across and at the
## top, so a landscape card (an evolution) still shows its top when the hand is lowered.
static func _card_rect(tex: Texture2D) -> Rect2:
	if tex == null:
		return Rect2(Vector2.ZERO, CARD_SIZE)
	var k: float = minf(CARD_SIZE.x / tex.get_width(), CARD_SIZE.y / tex.get_height())
	var s := Vector2(tex.get_width(), tex.get_height()) * k
	return Rect2(Vector2((CARD_SIZE.x - s.x) * 0.5, 0), s)


## One card of the hand: its image, the cost on a diamond, and how it can be used now; `why`
## (shown on hover) says what keeps it from being played.
func _hand_card(slot: int, cid: String, playable: bool, my_round: bool, why: String = "",
		heroes: PackedStringArray = PackedStringArray()) -> Control:
	var c: CardDef = engine.catalog.get_card(cid)
	var root := Control.new()
	root.custom_minimum_size = CARD_SIZE
	root.size = CARD_SIZE
	root.pivot_offset = Vector2(CARD_SIZE.x * 0.5, CARD_SIZE.y)
	root.set_meta("cid", cid)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	# The root stays put and takes the mouse; only its face rises and grows on hover, so the
	# card does not slip out from under the mouse and flicker.
	var face := Control.new()
	face.name = "Face"
	face.size = CARD_SIZE
	face.pivot_offset = Vector2(CARD_SIZE.x * 0.5, CARD_SIZE.y)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(face)
	var tex: Texture2D = db.thumb(cid) if db != null else null
	var pic: Rect2 = _card_rect(tex)
	root.set_meta("pic", pic)
	if tex != null:
		var img := TextureRect.new()
		img.texture = tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_SCALE
		img.position = pic.position
		img.size = pic.size
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img.material = round_corners(pic.size.x / pic.size.y)
		face.add_child(img)
	else:
		var back := ColorRect.new()
		back.color = Palette.hero(c.color if c != null else "").darkened(0.45)
		back.position = pic.position
		back.size = pic.size
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_child(back)
		var name_l: Label = UiTheme.label(c.name if c != null else cid, 18)
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_l.set_anchors_preset(Control.PRESET_FULL_RECT)
		face.add_child(name_l)
	if c != null:
		var poor: bool = my_round and c.cost > state.player(slot).energy
		var cost: UiShape = UiShape.make(UiShape.Kind.DIAMOND, Palette.ACCENT if poor else Palette.GOLD, Vector2(36, 36),
			str(c.cost), 21, Palette.FG if poor else Color.BLACK)
		cost.outline = Color.BLACK
		cost.outline_width = 3.0
		cost.name = "Cost"
		cost.position = pic.position - Vector2(10, 10)
		face.add_child(cost)
		if not c.is_ready():
			var nr: UiShape = UiShape.chip("NOT READY", Palette.SURFACE_2, Palette.MUTED, 12, 20.0, 8.0)
			nr.position = Vector2(CARD_SIZE.x * 0.5 - nr.custom_minimum_size.x * 0.5, pic.end.y - 28)
			face.add_child(nr)
		elif my_round and not playable and not why.is_empty():
			# Why it is grey, on hover.
			var w: UiShape = UiShape.chip(why.to_upper(), Color(0, 0, 0, 0.85), Palette.FG, 10, 18.0, 6.0)
			w.name = "Why"
			w.visible = false
			w.position = Vector2(CARD_SIZE.x * 0.5 - w.custom_minimum_size.x * 0.5, pic.position.y - 26.0)
			face.add_child(w)
		root.tooltip_text = _card_tip("%s  ·  %s %s  ·  cost %d\n%s" % [c.name, c.color, c.type, c.cost, c.text])
		if my_round and not playable:
			# Why it is grey shows above the card on hover; the text block keeps the card's text.
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
				_card_chosen(slot, cid, heroes))
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
		_big.stretch_mode = TextureRect.STRETCH_SCALE
		# It takes the mouse: a right click on it puts it away (any left click does too, _input).
		_big.mouse_filter = Control.MOUSE_FILTER_STOP
		_big.z_index = 50
		_big.material = round_corners()
		_big.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
				_show_big("")
				accept_event())
		add_child(_big)
	_big.visible = tex != null
	if tex == null:
		return
	move_child(_big, -1)
	_big.texture = tex
	var aspect: float = float(tex.get_width()) / tex.get_height()
	var w: float = minf(BIG_HEIGHT * aspect, 700.0)
	_big.size = Vector2(w, w / aspect)
	_big.position = Vector2(size.x * 0.5 - w * 0.5, size.y - _big.size.y - 190.0)
	(_big.material as ShaderMaterial).set_shader_parameter("aspect", aspect)
	_big.modulate.a = 0.0
	_big.create_tween().tween_property(_big, "modulate:a", 1.0, 0.1)


## The card-zoom key (Settings → Keys; held, or pressed on and off) shows the card under the mouse.
func _input(event: InputEvent) -> void:
	# An open big card goes away on any left click (the click does nothing else).
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not _big_cid.is_empty():
		_show_big("")
		get_viewport().set_input_as_handled()
		return
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
	# The starting hand stands still: big already, and its buttons are under it.
	if state != null and state.phase == GameState.PHASE_MULLIGAN:
		return
	# The card a hero is being chosen for stays up when the mouse leaves it.
	if not up and str(card.get_meta("cid", "")) == target_cid:
		return
	var face: Control = card.get_node_or_null("Face") as Control
	if face == null:
		return
	var rest: float = JsonUtil.as_float(card.get_meta("rest_y", card.position.y))
	card.z_index = 10 if up else 0
	var old: Tween = card.get_meta("lift") if card.has_meta("lift") else null
	if old != null and old.is_valid():
		old.kill()
	var t: Tween = card.create_tween().set_parallel(true)
	card.set_meta("lift", t)
	if up:
		# The mouse area grows up over the raised face at once, so moving onto it keeps it up.
		var shown: float = face.position.y + (card.position.y - rest)
		card.position.y = rest - LIFT
		card.size = CARD_SIZE + Vector2(0, LIFT)
		card.pivot_offset = Vector2(CARD_SIZE.x * 0.5, CARD_SIZE.y + LIFT)
		face.position.y = shown + LIFT
		t.tween_property(face, "position:y", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(face, "scale", Vector2.ONE * 1.18, 0.12)
	else:
		t.tween_property(face, "position:y", LIFT, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(face, "scale", Vector2.ONE, 0.12)
		t.chain().tween_callback(func() -> void:
			card.position.y = rest
			card.size = CARD_SIZE
			card.pivot_offset = Vector2(CARD_SIZE.x * 0.5, CARD_SIZE.y)
			face.position.y = 0.0)
	if face.has_node("Why"):
		(face.get_node("Why") as Control).visible = up
	# The straw edge runs round the picture and the cost diamond on its corner.
	var cost: UiShape = face.get_node_or_null("Cost") as UiShape
	if cost != null:
		cost.outline = Palette.GOLD if up and playable else Color.BLACK
		cost.queue_redraw()
	if up and playable and not face.has_node("Edge"):
		var pic: Rect2 = card.get_meta("pic", Rect2(Vector2.ZERO, CARD_SIZE))
		var edge := ReferenceRect.new()
		edge.name = "Edge"
		edge.border_color = Palette.GOLD
		edge.border_width = 3.0
		edge.editor_only = false
		edge.position = pic.position - Vector2(1.5, 1.5)
		edge.size = pic.size + Vector2(3, 3)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_child(edge)
		if cost != null:
			face.move_child(cost, -1)
	elif not up and face.has_node("Edge"):
		face.get_node("Edge").queue_free()


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
	# How many cards go and what is left, like the hero lines (playtest 2026-10-30).
	var from_deck: int = mini(amount, p.deck.size())
	var from_hand: int = amount - from_deck
	var deck_line: String = "DECK   %d cards → %d" % [p.deck.size(), p.deck.size() - from_deck]
	if from_hand > 0:
		deck_line += "   + %d from your hand (%d)" % [from_hand, p.hand.size()]
	_option_button(deck_line, func() -> void: damage_pressed.emit(who, "deck"))


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

## The match so far in words, oldest first (the pause menu shows it).
## A phase gets its own heading before its first line (playtest 2026-10-30: only new turns
## showed); a phase where nothing happened shows nothing.
func log_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var at: String = ""
	for e: Dictionary in state.log:
		var s: String = _describe(e)
		if s.is_empty():
			continue
		var turn: int = JsonUtil.as_int(e.get("turn", 0))
		var phase: String = str(e.get("phase", ""))
		var key: String = "%d|%s" % [turn, _ribbon_phase(phase)]
		# "end of turn" closes the turn itself; it needs no heading.
		if turn > 0 and key != at and str(e.get("type", "")) != "turn_end":
			lines.append("TURN %d · %s" % [turn, _ribbon_phase(phase).to_upper()])
		at = key
		lines.append(s)
	return lines


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
		elif t == "roll_retry":
			toast(_describe(e))
		elif t == "stage_buff":
			# A stage's bonus is easy to miss on the table: say it.
			toast(_describe(e))
	_log_seen = n
	# A replay jumping ahead shows only the last few.
	for e: Dictionary in fresh.slice(maxi(0, fresh.size() - 3)):
		_banner_for(e)


func _banner_for(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"battle":
			# Power is per team: each side's heroes in that battle and their total.
			var power: Dictionary = JsonUtil.as_dict(e.get("power", {}))
			var index: int = JsonUtil.as_int(e.get("index", state.battle_index))
			var ids: PackedStringArray = JsonUtil.as_strings(state.battles[index].get("heroes", [])) if index >= 0 and index < state.battles.size() else PackedStringArray()
			var sides: Array[String] = ["", ""]
			var best: int = -1
			var best_pow: int = -1
			var tie: bool = false
			for t: int in 2:
				var names := PackedStringArray()
				for hid: String in ids:
					var h: HeroState = state.hero(hid)
					if h != null and state.team_of(h.owner) == t:
						names.append(hero_name(h).to_upper())
				# Keys are ints from the engine, strings after a replay or the network.
				var pw: int = 0
				for k: Variant in power:
					if str(k) == str(t):
						pw = JsonUtil.as_int(power[k])
				sides[t] = "%s\n%d" % [" + ".join(names), pw]
				if pw > best_pow:
					best_pow = pw
					best = t
					tie = false
				elif pw == best_pow:
					tie = true
			banner("BATTLE!", Palette.ACCENT, sides[0], sides[1], BATTLE_BANNER_TIME)
			# Who won, said on its own for two seconds (playtest 2026-10-30).
			if not tie and best >= 0:
				var who: String = sides[best].get_slice("\n", 0)
				banner("%s %s THE FIGHT!" % [who, "WINS" if not who.contains(" + ") else "WIN"], Palette.team(best).darkened(0.2), "", "", 2.0)
			battle_resolved.emit(index, -1 if tie else best)
		"damage":
			# A battle's hit, said out loud: who takes how much (playtest 2026-10-30).
			var amount: int = JsonUtil.as_int(e.get("amount", 0))
			if str(e.get("phase", "")) == GameState.PHASE_BATTLE and amount > 0:
				banner("%s TAKES %d DAMAGE" % [_hero_label(str(e.get("hero", ""))).to_upper(), amount], Palette.ACCENT_DEEP, "", "HP %d" % JsonUtil.as_int(e.get("hp", 0)), 1.6)
		"deck_damage":
			if str(e.get("phase", "")) == GameState.PHASE_BATTLE:
				var p: PlayerState = state.player(JsonUtil.as_int(e.get("player", 0)))
				banner("%s DECKS %d!" % [player_name(p.slot).to_upper(), JsonUtil.as_int(e.get("amount", 0))], Palette.ACCENT_DEEP, "", "%d LEFT IN THE DECK" % p.deck.size(), 1.6)
		"ring_out":
			banner("RING-OUT", Palette.GOLD, "", _hero_label(str(e.get("hero", ""))).to_upper())
		"ko":
			banner("KO", Palette.ACCENT_DEEP, "", _hero_label(str(e.get("hero", ""))).to_upper())
		"stage_claimed":
			var st: StageState = state.stage(str(e.get("stage", "")))
			banner("STAGE CLAIMED", Palette.GOLD, player_name(JsonUtil.as_int(e.get("player", 0))).to_upper(),
				_card_name(st.card_id if st != null else "").to_upper())
		"triggered":
			var name: String = _triggered_name(e)
			if not name.is_empty():
				banner(name.to_upper(), Palette.GOLD, _hero_label(str(e.get("hero", ""))).to_upper(), "")
		"battle_locked":
			# A tie (GDD 10): nobody is hurt, the heroes stay locked and fight again next turn.
			banner("TIE!", Palette.GOLD, _heroes_line(e).to_upper(), "SAME POWER · FIGHT AGAIN NEXT TURN", BATTLE_BANNER_TIME)
			toast("Tie: %s. Nobody takes damage; they stay locked and fight this battle again next turn." % _heroes_line(e))
		"battle_tie_break":
			banner("TIE AGAIN!", Palette.ACCENT, _heroes_line(e).to_upper(), "BOTH KNOCKED BACK", BATTLE_BANNER_TIME)
			toast("Second tie: %s. Both heroes are knocked back towards their own side." % _heroes_line(e))


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
	t.tween_interval(JsonUtil.as_float(b.get("hold", BANNER_TIME), BANNER_TIME) * GameSettings.anim_scale())
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
		"roll_retry":
			return "%s did not leave the start strip: throw again" % hero_l
		"stage_buff":
			var sb: StageState = state.stage(str(e.get("stage", "")))
			var stat: String = {"pwr": "Power", "dmg": "DMG", "kb": "KB", "rng": "Range", "hp": "HP"}.get(str(e.get("stat", "")), str(e.get("stat", "")))
			return "%s: %s %+d %s" % [_card_name(sb.card_id if sb != null else ""), hero_l, JsonUtil.as_int(e.get("amount", 0)), stat]
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
		"triggered":
			var name: String = _triggered_name(e)
			return "%s: %s" % [hero_l, name if not name.is_empty() else _card_name(str(e.get("card", "")))]
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
			return "Tie: %s, locked, fight again next turn" % _heroes_line(e)
		"battle_tie_break":
			return "Second tie: %s, both knocked back" % _heroes_line(e)
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
	if not series_text.is_empty():
		_over_box.add_child(UiTheme.label(series_text, 26, Palette.GOLD))
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
	if new_match:
		var fresh := Button.new()
		fresh.text = "NEW MATCH"
		fresh.tooltip_text = "Back to the setup: other decks, map or rules"
		fresh.add_theme_font_size_override("font_size", 22)
		fresh.pressed.connect(func() -> void: new_match_pressed.emit())
		buttons.add_child(fresh)
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
	var balance: Button = WebApp.link("BALANCE", "balance", "Win rates of heroes and cards from every match played.")
	balance.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buttons.add_child(balance)
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


## An engine reason in a few words, for a chip.
static func _short_why(err: String) -> String:
	var e: String = err.to_lower()
	if e.contains("cannot take this card") or e.contains("colour") or e.contains("color"):
		return "wrong colour"
	if e.contains("evolution is for") or e.contains("evolution level"):
		return "wrong hero"
	if e.contains("already has"):
		return "already has it"
	if e.contains("start zone"):
		return "in the start zone"
	if e.contains("energy"):
		return "not enough energy"
	if e.contains("damage"):
		return "too little HP"
	return "can't take it"


## The ribbon's name for a rules phase: Draw and Select are both "start".
static func _ribbon_phase(phase: String) -> String:
	# Old replays still carry draw and select frames.
	return "start" if phase == "draw" or phase == "select" else phase


## A card's text on hover, unless switched off (Settings → Interface: card text on hover).
static func _card_tip(text: String) -> String:
	return text if GameSettings.hover_text() else ""


## A material that cuts a card picture's corners round (the JPGs carry black corners).
static func round_corners(aspect: float = 0.714) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://ui/round_corners.gdshader")
	m.set_shader_parameter("aspect", aspect)
	return m


func _mulligan_button(text: String, cb: Callable, kind: StringName) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if kind != &"":
		b.theme_type_variation = kind
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(220, 52)
	b.pressed.connect(cb)
	_mulligan_row.add_child(b)
	return b


## Auto-pass (GDD 8): true when the local player to act has nothing playable now: no card the
## engine would accept and no ability on offer. The match passes for them after a short wait.
func nothing_to_play(slot: int) -> bool:
	if not _in_card_round() or state.to_act != slot or not state.pending.is_empty():
		return false
	return not can_play(slot)


## Whether `slot` has a card it could play or an ability it could use in this card round, its
## turn or not. Only meaningful where its hand is known (not the opponent's, for a guest).
## The roll offer of `slot` still waiting, or {} (answered, or the balls are still rolling).
func own_roll_offer(slot: int) -> Dictionary:
	var i: int = engine.roll_offer_index(state, slot)
	return state.pending[i] if i >= 0 else {}


## An offer with nothing on it: the player only waits it out (or goes on by hand).
static func empty_offer(d: Dictionary) -> bool:
	return not d.is_empty() and JsonUtil.as_strings(d.get("cards", [])).is_empty() and JsonUtil.as_strings(d.get("abilities", [])).is_empty()


func can_play(slot: int) -> bool:
	if not engine.fx.usable_abilities(state, slot).is_empty():
		return true
	for cid: String in state.player(slot).hand:
		if _play_check(slot, cid, true).get("ok", false) == true:
			return true
	return false


## The move timer: `seconds` left for `who` ("" = you); below zero hides it. Your last five
## seconds go red.
func set_clock(seconds: int, who: String) -> void:
	var text: String = ""
	if seconds >= 0:
		text = ("TIME  %d" % seconds) if who.is_empty() else "%s  ·  %d" % [who.to_upper(), seconds]
	if text == _clock.text:
		return
	_clock.text = text
	_clock.add_theme_color_override("font_color", Palette.ACCENT_HOVER if seconds >= 0 and seconds <= 5 and who.is_empty() else Palette.GOLD)


## The hero `slot` activated, as this screen may show it: in the Start phase the others' picks
## stay hidden until everyone has confirmed (they come out together, GDD 8).
func shown_active(slot: int) -> String:
	if state.phase == GameState.PHASE_START and not local_slots.has(slot):
		return ""
	return state.active.get(slot, "")


## The name of an ability that fired by itself ("triggered"): the card names its abilities in
## order, passives aside. "" when the card gives none.
func _triggered_name(e: Dictionary) -> String:
	var card: CardDef = engine.catalog.get_card(str(e.get("card", "")))
	var index: int = JsonUtil.as_int(e.get("index", -1), -1)
	if card == null or index < 0 or index >= card.effects.size():
		return ""
	var n: int = 0
	for i: int in index:
		if card.effects[i].when != "PASSIVE":
			n += 1
	return card.ability_name(n)


## The Start block's text, above its Roll / Stay and CONFIRM (bottom right): a gold kicker, a
## title and a line, on a dark card with a gold edge.
func _start_card(kicker: String, title: String, line: String) -> void:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.067, 0.06, 0.92)
	sb.border_color = Palette.GOLD
	sb.border_width_left = 4
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(290, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)
	col.add_child(UiTheme.label(kicker, 13, Palette.GOLD))
	var t: Label = UiTheme.label(title, 24)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(266, 0)
	col.add_child(t)
	var d := Label.new()
	d.text = line
	d.add_theme_color_override("font_color", Color("b9b4ab"))
	d.add_theme_font_size_override("font_size", 13)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(266, 0)
	col.add_child(d)
	_actions.add_child(card)


## Start: Roll / Stay right under a hovered ball of yours (Marko 2026-10-26). A click picks that
## hero and says whether it rolls; CONFIRM still locks it in.
func show_ball_choice(hero_id: String, at: Vector2) -> void:
	var h: HeroState = state.hero(hero_id) if state != null else null
	if h == null:
		hide_ball_choice(true)
		return
	if _ball_choice == null:
		_ball_choice = HBoxContainer.new()
		_ball_choice.add_theme_constant_override("separation", 4)
		add_child(_ball_choice)
		for roll_choice: bool in [true, false]:
			var b := Button.new()
			b.text = "ROLL" if roll_choice else "STAY"
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(68, 30)
			b.add_theme_font_size_override("font_size", 16)
			var want: bool = roll_choice
			b.pressed.connect(func() -> void:
				var hero: HeroState = state.hero(_choice_hero)
				if hero == null:
					return
				picks[hero.owner] = hero.id
				pick_rolls[hero.owner] = want
				hide_ball_choice(true)
				ball_choice_made.emit(hero.id)
				refresh())
			_ball_choice.add_child(b)
	_choice_left_at = 0
	_choice_hero = hero_id
	var must_roll: bool = h.zone == HeroState.ZONE_STRIP
	var picked: bool = str(picks.get(h.owner, "")) == hero_id
	var rolls: bool = must_roll or not picked or pick_rolls.get(h.owner, true) == true
	var roll_b: Button = _ball_choice.get_child(0)
	var stay_b: Button = _ball_choice.get_child(1)
	roll_b.theme_type_variation = &"Gold" if picked and rolls else &""
	stay_b.theme_type_variation = &"Gold" if picked and not rolls else &""
	# In the start zone a hero must roll: STAY is not offered at all.
	stay_b.visible = not must_roll
	_ball_choice.reset_size()
	_ball_choice.position = at - Vector2(_ball_choice.size.x * 0.5, 0)
	_ball_choice.visible = true


## Hides the ball's Roll / Stay, unless the mouse is on them or was off them for less than
## CHOICE_GRACE seconds (it is on its way from the ball to them).
func hide_ball_choice(force: bool = false) -> void:
	if _ball_choice == null or not _ball_choice.visible:
		return
	if not force:
		if _ball_choice.get_global_rect().grow(16).has_point(get_global_mouse_position()):
			_choice_left_at = 0
			return
		var now: int = Time.get_ticks_msec()
		if _choice_left_at == 0:
			_choice_left_at = now
		if now - _choice_left_at < int(CHOICE_GRACE * 1000.0):
			return
	_choice_left_at = 0
	_ball_choice.visible = false


## One equipment slot in a hero panel: the card's picture, small, or a dashed empty slot.
func _equip_mini(cid: String) -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(22, 30)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(3)
	sb.set_border_width_all(1)
	sb.border_color = Color(Palette.MUTED, 0.6)
	if cid.is_empty():
		sb.border_blend = false
		box.add_theme_stylebox_override("panel", sb)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.modulate.a = 0.5
		return box
	sb.border_color = Color(1, 1, 1, 0.5)
	box.add_theme_stylebox_override("panel", sb)
	var card: CardDef = engine.catalog.get_card(cid)
	var tex: Texture2D = db.thumb(cid) if db != null else null
	if tex != null:
		var pic := TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(pic)
	else:
		var l: Label = UiTheme.label((card.name if card != null else cid).left(2).to_upper(), 11)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
	if card != null:
		box.tooltip_text = _card_tip("%s\n%s" % [card.name, card.text])
	box.mouse_entered.connect(func() -> void: _hovered(cid))
	box.gui_input.connect(func(e: InputEvent) -> void: _card_click(e, cid))
	return box


## The piles by the hand: the graveyard left (its top card, faded; hover lists it, right click
## shows it big), the deck right (a stack), each with its count.
func _refresh_piles() -> void:
	if _piles == null or state == null:
		return
	_clear(_piles)
	_clear(_grave_spot)
	var slot: int = hand_slot()
	if slot < 0 and not local_slots.is_empty():
		slot = local_slots[0]
	var p: PlayerState = state.player(slot) if slot >= 0 else null
	_piles.visible = p != null
	_grave_spot.visible = p != null
	if not _piles.visible:
		return
	var top: String = p.graveyard[p.graveyard.size() - 1] if not p.graveyard.is_empty() else ""
	var grave: Control = _pile(top, "GRAVE %d" % p.graveyard.size(), false)
	grave.tooltip_text = "Graveyard: " + (", ".join(_card_names(p.graveyard)) if not p.graveyard.is_empty() else "empty")
	var who: int = slot
	grave.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	grave.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			open_graveyard(who))
	_grave_spot.add_child(grave)
	_piles.add_child(_pile("", "DECK %d" % p.deck.size(), true))


## One pile: a face-down stack (deck) or the top card faded (graveyard; an empty slot when none),
## its count on a dark tab under it.
func _pile(cid: String, count: String, face_down: bool) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(56, 78)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var layers: int = 3 if face_down else 1
	for i: int in layers:
		var k: int = layers - 1 - i
		var card := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(5)
		sb.set_border_width_all(2)
		sb.border_color = Color("141110")
		sb.bg_color = Palette.ACCENT.darkened(0.15 * k) if face_down else Color(0.42, 0.37, 0.33, 0.45 if cid.is_empty() else 0.9)
		card.add_theme_stylebox_override("panel", sb)
		card.position = Vector2(2.0 * k, -2.0 * k)
		card.size = Vector2(56, 78)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(card)
	if not face_down and not cid.is_empty():
		var tex: Texture2D = db.thumb(cid) if db != null else null
		if tex != null:
			var pic := TextureRect.new()
			pic.texture = tex
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			pic.position = Vector2(3, 3)
			pic.size = Vector2(50, 72)
			pic.modulate = Color(1, 1, 1, 0.7)
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(pic)
	var tab: UiShape = UiShape.chip(count, Color("141110"), Palette.FG, 12, 18.0, 6.0)
	tab.position = Vector2(-4, 66)
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tab)
	return box


## Whether the mouse is on the Roll / Stay under a ball.
func ball_choice_has_mouse() -> bool:
	return _ball_choice != null and _ball_choice.visible \
			and _ball_choice.get_global_rect().grow(8).has_point(get_global_mouse_position())


## A player's graveyard laid out as cards over the table (Marko 2026-10-26): the latest first;
## hover a card for its text, a click anywhere else closes it.
func open_graveyard(slot: int) -> void:
	var p: PlayerState = state.player(slot) if state != null else null
	if p == null:
		return
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	overlay.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			overlay.queue_free())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)
	var title: Label = UiTheme.label("%s · GRAVEYARD  %d" % [player_name(slot).to_upper(), p.graveyard.size()], 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	if p.graveyard.is_empty():
		var none: Label = UiTheme.label("No cards yet", 22, Palette.DIM)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(none)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(minf(size.x - 120.0, 1180.0), minf(size.y - 220.0, 640.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.visible = not p.graveyard.is_empty()
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = maxi(1, int((scroll.custom_minimum_size.x + 12.0) / 172.0))
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for i: int in range(p.graveyard.size() - 1, -1, -1):
		var cid: String = p.graveyard[i]
		var card: CardDef = engine.catalog.get_card(cid)
		var tex: Texture2D = db.large(cid) if db != null and db.large(cid) != null else (db.thumb(cid) if db != null else null)
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(160, 224)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture = tex
		pic.mouse_filter = Control.MOUSE_FILTER_PASS
		if card != null:
			pic.tooltip_text = _card_tip("%s\n%s" % [card.name, card.text])
		grid.add_child(pic)


## "Zoro vs Shanks" for an event's "heroes".
func _heroes_line(e: Dictionary) -> String:
	var names := PackedStringArray()
	for id: String in JsonUtil.as_strings(e.get("heroes", [])):
		names.append(_hero_label(id))
	return " vs ".join(names)


# --- stages and cores at a glance (playtest 2026-10-30) ---------------------------------

## Under the phase ribbon: all six stages (yours as cards from the start, marked HIDDEN until
## they turn face up; the other side's as "?" until then) and your cores (HIDDEN or PUBLIC, and
## on whom). Hover shows where it is on the table, a click shows the card big.
func _refresh_board() -> void:
	if _board == null:
		return
	var on: bool = state.turn > 0 and not state.is_over()
	_board.visible = on
	_board.position.y = 112.0 if _battle_bar.visible else 62.0
	if not on:
		return
	var viewer: int = hand_slot() if hand_slot() >= 0 else (local_slots[0] if not local_slots.is_empty() else -1)
	var sig: String = "%d|%s" % [viewer, str(local_slots)]
	for st: StageState in state.stages:
		sig += "|%s:%s:%s:%d:%s" % [st.id, st.card_id, st.revealed, st.claimed_by, st.placed]
	for c: CoreState in state.cores:
		sig += "|%s:%s:%s:%s" % [c.id, c.place, c.face_up, c.holder]
	if sig == _board_sig:
		return
	_board_sig = sig
	_clear(_board)
	var stages := HBoxContainer.new()
	stages.add_theme_constant_override("separation", 6)
	stages.alignment = BoxContainer.ALIGNMENT_CENTER
	stages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(stages)
	# The viewer's stages first, then the other side's.
	var order: Array[StageState] = []
	for st: StageState in state.stages:
		if st.owner == viewer:
			order.append(st)
	for st: StageState in state.stages:
		if st.owner != viewer:
			order.append(st)
	for st: StageState in order:
		stages.add_child(_board_stage(st))
	if viewer < 0:
		return
	var mine: Array[CoreState] = []
	for c: CoreState in state.cores:
		if c.owner == viewer:
			mine.append(c)
	if mine.is_empty():
		return
	var cores := HBoxContainer.new()
	cores.add_theme_constant_override("separation", 4)
	cores.alignment = BoxContainer.ALIGNMENT_CENTER
	cores.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(cores)
	var cap: Label = UiTheme.label("YOUR CORES", 12, Palette.GOLD)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cores.add_child(cap)
	for c: CoreState in mine:
		cores.add_child(_board_core(c))


func _board_stage(st: StageState) -> Control:
	var known: bool = st.revealed or local_slots.has(st.owner)
	var card: CardDef = engine.catalog.get_card(st.card_id) if known and not st.card_id.is_empty() else null
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(70, 46)
	tile.clip_contents = true
	var sb: StyleBoxFlat = UiTheme.box(Palette.SURFACE_2, 4, Color(0, 0, 0, 0), 0, 0)
	sb.set_border_width_all(3 if st.is_claimed() else 2)
	sb.border_color = Palette.team(state.team_of(st.claimed_by)) if st.is_claimed() else Color(Palette.team(state.team_of(st.owner)), 0.7)
	tile.add_theme_stylebox_override("panel", sb)
	var tex: Texture2D = db.thumb(card.id) if card != null and db != null else null
	if tex != null:
		var art := TextureRect.new()
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Yours but still face down: you know it, the table does not yet.
		art.modulate = Color(1, 1, 1, 1.0 if st.revealed else 0.45)
		tile.add_child(art)
	else:
		var q: Label = UiTheme.label("?", 26, Palette.DIM)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tile.add_child(q)
	var word: String = "CLAIMED" if st.is_claimed() else ("HIDDEN" if not st.revealed and card != null else "")
	if not word.is_empty():
		var tag: Label = UiTheme.label(word, 10, Palette.GOLD if st.is_claimed() else Palette.FG)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		tag.add_theme_constant_override("outline_size", 4)
		tag.add_theme_color_override("font_outline_color", Color.BLACK)
		tile.add_child(tag)
	var whose: String = player_name(st.owner)
	if card != null:
		tile.tooltip_text = "%s (%s's stage%s)%s" % [card.name, whose, ", face down" if not st.revealed else "",
			("\n" + _card_tip(card.text)) if not _card_tip(card.text).is_empty() else ""]
	else:
		tile.tooltip_text = "%s's stage, face down until a hero stops on it" % whose
	if st.is_claimed():
		tile.tooltip_text += "\nClaimed by %s" % player_name(st.claimed_by)
	_board_hover(tile, st.footprint() if st.placed else [] as Array[Vector2i], card)
	return tile


func _board_core(c: CoreState) -> Control:
	var card: CardDef = engine.catalog.get_card(c.card_id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var chip: Control = _core_slot(c.id, Palette.SURFACE_2)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(chip)
	var where: String = ""
	var hexes: Array[Vector2i] = []
	match c.place:
		CoreState.ON_FIELD:
			where = "PUBLIC" if c.face_up else "HIDDEN"
			hexes.append(c.hex)
		CoreState.ON_HERO:
			var h: HeroState = state.hero(c.holder)
			where = hero_name(h).get_slice(",", 0).to_upper() if h != null else "ON A HERO"
			if h != null and h.is_on_map():
				hexes.append(h.hex)
		CoreState.IN_INVENTORY:
			where = "TO PUT BACK"
		_:
			where = "NOT PLACED"
	var w: Label = UiTheme.label(where, 9, Palette.MUTED if where != "HIDDEN" else Palette.FG)
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(w)
	box.tooltip_text = "%s%s" % [card.name if card != null else "Core",
		"\nFace down: only you know it" if c.place == CoreState.ON_FIELD and not c.face_up else ""]
	_board_hover(box, hexes, card)
	return box


func _board_hover(c: Control, hexes: Array[Vector2i], card: CardDef) -> void:
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if card != null else Control.CURSOR_ARROW
	c.mouse_entered.connect(func() -> void: board_hovered.emit(hexes))
	c.mouse_exited.connect(func() -> void: board_hovered.emit([] as Array[Vector2i]))
	c.gui_input.connect(func(e: InputEvent) -> void:
		if card != null and e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_toggle_big(card.id)
			c.accept_event())
