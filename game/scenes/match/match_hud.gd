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
## A lost battle's hit confirmed: the hero that takes it and the hand cards (ids) that take 1 DMG each.
signal damage_pressed(slot: int, target: String, cards: Array)
## The energy claim variant's End phase split: {stage id: energy}.
signal energy_pressed(slot: int, split: Dictionary)
## Answer to a "choose" decision (hero, core, card id or branch index; hexes go by click).
signal choose_pressed(slot: int, value: Variant)
signal ability_pressed(slot: int, hero_id: String, card_id: String, index: int)
signal hero_clicked(hero_id: String)
signal hero_hovered(hero_id: String)
## A stage or core in the board strip is hovered: its hexes ([] when the mouse left).
signal board_hovered(hexes: Array[Vector2i])
## A card went onto a hero (log: equipped, evolved, action): the table shows it coming down.
signal card_played(card_id: String, hero_id: String)
## A hero's ability went off (used or by itself): the table shows its effect.
signal ability_fired(hero_id: String, card_id: String)
## The centre is taken by a band (true) or free again (false): the match waits while it is taken.
signal announcing_changed(busy: bool)
## The KO announcement of these heroes is up (the bands before it gone): Evil Bochet takes them down now.
signal ko_due(ids: PackedStringArray)
## The battle the bar, the scale and the table show changed (see shown_battle).
signal shown_battle_changed
signal menu_pressed
## Leave the match for the main menu (the drop screen).
signal leave_pressed
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
## The hand's width.
const HAND_WIDTH: float = 760.0
## The deck and the graveyard: how big, how far from the left, and how far above the bottom.
const PILE_SCALE: float = 0.75
const PILES_X: float = 180.0
const DECK_PILE_Y: float = -148.0
const GRAVE_PILE_Y: float = -78.0
const BANNER_TIME: float = 0.8
## An ability tab's name: the room it has (the tab less its slanted sides) and the smallest letters.
const ABILITY_NAME_W: float = 126.0
const ABILITY_NAME_MIN: int = 12
## The setup tray while the other player places: darker, not see-through.
const TRAY_WAITING := Color(0.42, 0.42, 0.42, 1.0)
## Phase call-outs stay a little longer, to be read.
const PHASE_BANNER_TIME: float = 2.2
## Start too: every phase is called out long enough to notice (Marko 2026-10-26).
const START_BANNER_TIME: float = 2.2
## BATTLE! stays long enough to read both sides' Power.
const BATTLE_BANNER_TIME: float = 1.6
## The combo card stays over the screen this long (a click or Enter puts it away sooner).
const COMBO_SHOW_TIME: float = 2.6
## The KO announcement (_ko_show): about this long on the screen; it waits at most KO_WAIT_MOST seconds
## for Evil Bochet's claws, and with him the right card is dragged off KO_DRAG_GAP after the left (KO6).
## Stat colours (item 25, B3b, Marko 2026-11-09): up or down, for good, this phase, this turn.
const BONUS_LASTING_UP := Color("3ddc68")
const BONUS_PHASE_UP := Color("35d9d0")
const BONUS_TURN_UP := Color("4aa3ff")
const BONUS_LASTING_DOWN := Color("ff4a4a")
const BONUS_PHASE_DOWN := Color("ffd23f")
const BONUS_TURN_DOWN := Color("ff8a2a")
const KO_SHOW_TIME: float = 2.4
const KO_WAIT_MOST: float = 3.0
const KO_DRAG_GAP: float = 0.16
## The combo window's cards: how tall, and how far the two overlap.
const COMBO_CARD_H: float = 190.0
const COMBO_PARTS_OVERLAP: int = -46
## The two cards going into one: where they wait beside each other (in card widths from the middle),
## where they come from for a player who did not choose it, how big they get, and how long it takes.
const COMBO_SIDE: float = 0.75
const COMBO_SPREAD: float = 1.6
const COMBO_FLY_SCALE: float = 1.7
const COMBO_FLY_TIME: float = 0.26
const COMBO_DASH_TIME: float = 0.2
## Half a breath of the edge on a stage energy just went into.
const ENERGY_PULSE_TIME: float = 0.7
const TOAST_H: float = 40.0
const TOAST_PAD: float = 20.0
const TOAST_FONT: int = 22
const TOAST_FONT_MIN: int = 13
const TOAST_CLEAR: float = 14.0
## How dark the table gets behind the starting hand, and how fast.
const MULLIGAN_DIM: float = 0.55
const MULLIGAN_DIM_TIME: float = 0.2
## The card beside a choice it asks for: how tall, upright and on its side.
const CHOICE_CARD_H: float = 250.0
const CHOICE_CARD_H_WIDE: float = 170.0
## The battle's balance bar: how far down, and how far it keeps from what stands beside it.
const TUG_Y: float = 106.0
const TUG_CLEAR: float = 14.0
## How far in from the strip above it, the same on both sides.
const TUG_INSET: float = 30.0
## A hero's picture in the damage choice: alone, and among several.
const DAMAGE_HERO_W: float = 158.0
const DAMAGE_HERO_W_MANY: float = 128.0
const DAMAGE_HERO_H: float = 196.0
## The stage box's fold chevron: its control, the x where its lines start and end, how far from the
## top of the box, and the gap between those lines and the team's colour edge.
const FOLD_CHEVRON_SIZE: Vector2 = Vector2(16, 16)
const FOLD_CHEVRON_INK: Vector2 = Vector2(3, 13)
const FOLD_CHEVRON_Y: float = 7.0
const FOLD_CHEVRON_GAP: float = 8.0
## The +X on a stage energy just went into: how long it pops up, and how long it floats away.
const ENERGY_GAIN_IN: float = 0.3
const ENERGY_GAIN_OUT: float = 0.45
## The table stays this long after the deciding moment before the end screen (a click skips it).
const END_HOLD_TIME: float = 2.2
## The table stays this long after the last band, before the end screen (Marko 2026-11-09: the end
## came as a flash). A click or Enter skips it.
const END_PAUSE_TIME: float = 2.0
## A band's words keep this far from the screen's sides, and a long side wraps at this width.
const BAND_MARGIN: float = 110.0
const BAND_SIDE_W: float = 340.0
const BAND_PAD_Y: float = 40.0
const ENERGY_BANNER_TIME: float = 1.0
## The other side's Equipment or Assist stays this long before it flies to its place.
const POP_TIME: float = 1.3
## A merged band stays this much longer per extra line, up to MERGED_MAX_TIME.
const MERGED_LINE_TIME: float = 1.2
const MERGED_MAX_TIME: float = 6.0
## How far a hovered hand card rises.
const LIFT: float = 56.0
## At rest the cards you can play now stand this much higher (Marko 2026-11-08, from the mockups).
const HAND_STAND: float = 48.0
const HAND_STAND_SPEED: float = 200.0
## Raised with the rest of the hand, faster, so it arrives with it.
const HAND_STAND_SPEED_UP: float = 450.0
## How long the cards take to close up when one leaves, and how long one takes to leave.
const HAND_SLIDE_TIME: float = 0.25
const HAND_LEAVE_TIME: float = 0.35
const HAND_LEAVE_RISE: float = 160.0
## More cards than this gone at once is not a card played (a replay jumping, a new seat).
const HAND_LEAVE_MAX: int = 2
## Log events that get a banner (the rest only go to the log).
const BANNER_EVENTS: Array[String] = ["battle", "battle_locked", "battle_tie_break", "ring_out", "ko", "stage_claimed", "triggered",
	"damage", "deck_damage", "hand_damage", "stage_knocked_off", "combo"]

var engine: RulesEngine
var state: GameState
var db: CardDb
var local_slots: PackedInt32Array = PackedInt32Array()
## Hero highlighted from the table (hover on a ball).
var hover_hero: String = ""
## The stage the mouse is on, on the table: its tile in the panel is lit.
var table_stage: String = ""
## A playable card pressed in the hand: {slot, cid, heroes, from}; a drag once it moved
## (playtest 2026-10-30: drag a card onto a hero).
var _drag: Dictionary = {}
var _dragging: bool = false
const DRAG_START: float = 14.0
## True while the physics runs, so the prompt can say so.
var rolling: bool = false
## Watching a recorded match: no prompts, buttons or end screen, only the table and panels.
var replay: bool = false
## Online: who paused the match ("" when it runs); shown instead of the prompt.
var net_paused: String = ""
var _ping: UiShape
var _ping_text: String = ""
var _drop: Control
## Only watching (a spectator): no prompts, no buttons, "WATCHING" instead.
var spectating: bool = false
## Text of the end screen's first button; "" hides it (an online guest waits for the host).
var rematch_text: String = "Rematch"
## End screen: NEW MATCH back to the Play setup (local matches only).
var new_match: bool = true
## Setup: the stage or core the local player places next (set by the match scene).
var setup_pick: String = ""
## True while the who-starts dice are on screen: the setup tray and prompt wait (playtest 2026-11-06).
var intro_dice: bool = false
## The match summary (MatchRecord.summary) shown on the end screen; set by the match scene.
var end_summary: Dictionary = {}
## The end screen waits while this is set (the table moment, Marko 2026-11-08: "I did not know why I won").
var end_hold: bool = false
## A click or Enter during the pause after the last band: the end screen comes now.
var end_skip: bool = false
## The battle whose bands are being read out by _scan_log: every band made meanwhile carries it.
var _tagging: Dictionary = {}
## The band on the screen.
var _now: Dictionary = {}
var _shown_key: String = ""
## The battle bar as last drawn from the state (turn, index, count, side0/1, total0/1).
var _bar_last: Dictionary = {}
## "turn|index" of the battle the state was on at the last look at the log, "" outside one.
var _live_key: String = ""
## The series line on the end screen ("SERIES 1–0 · GAME 2 NEXT"), set by the match scene.
var series_text: String = ""
## Evil Bochet holds the table (set by the match scene): his claws take a fallen hero's card off the KO
## announcement, and the fallen face off the end screen (KO4, Z1; Marko 2026-11-10).
var bochet: bool = false
## Heroes his claws are taking down now: their KO announcement waits until they are gone.
var _ko_waiting: Dictionary[String, bool] = {}
## The end screen's moment (S1, K2): a click finishes it, a redraw of the screen does not start it again.
var _end_anim_tween: Tween
var _end_anim_done: bool = false
## What the end screen was built from, so that it is not built again for nothing.
var _over_key: String = ""
## For recordings: the mouse where a script puts it, in place of the real one (x under 0: the real one).
var demo_mouse := Vector2(-1, -1)


## Where the cards in hand cover the screen while the hand is up, empty while it is down (Evil Bochet's
## eyes get out from behind them).
func hand_cover() -> Rect2:
	if _hand == null or _hand_drop > 30.0 or not _hand_box.visible:
		return Rect2()
	var out := Rect2()
	for n: Node in _hand.get_children():
		var c := n as Control
		if c == null or not c.visible:
			continue
		var r: Rect2 = c.get_global_rect()
		out = r if out.size == Vector2.ZERO else out.merge(r)
	return out

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
## The last hand built was the starting hand: laid out differently, so nothing slides from it.
var _hand_was_mulligan: bool = false
## Behind the starting hand: dims the table and takes the mouse (Marko 2026-11-08).
var _mulligan_dim: ColorRect
var _menu_button: Control
## The two cards in the combo window, and where they stood when COMBO was pressed.
var _combo_pics: Array[Control] = []
var _combo_from: Array[Rect2] = []
## The pause menu is up: nothing behind it reacts to the mouse (Marko 2026-11-08).
var menu_open: bool = false
## Which card of the hand the player just played, by position: of two copies the right one leaves.
var hand_leaving: int = -1
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
## Energy that just went into a stage (Marko 2026-11-02: with one stage it went in without a
## word): stage id -> {"amount", "player", "until" (msec)}; its tile shows "+N" until then.
var _energy_flash: Dictionary = {}
const ENERGY_FLASH_MS: int = 3500
var _banner_layer: Control
var _banners: Array[Dictionary] = []
var _banner_busy: bool = false
## Bands of one moment are gathered first, then merged (`_push_group`).
var _grouping: bool = false
var _group: Array[Dictionary] = []
var _band: Panel
var _band_tween: Tween
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
## Where that card sits in the hand: two copies of one card are told apart by it (Marko
## 2026-11-02: the other copy lit up and the aim line came from it).
var target_index: int = -1
var target_heroes: PackedStringArray = PackedStringArray()
## A card effect asking a local player for a hero (heal, swap…): the heroes it may take and the
## seat that picks. Lit on the table and in the rosters, the rest fade; no dialog (Marko 2026-11-01).
var choice_heroes: PackedStringArray = PackedStringArray()
var choice_slot: int = -1
## The same for a core on the field (Reveal / Activate a Core…): lit on its hex.
var choice_cores: PackedStringArray = PackedStringArray()
## A card from the hand (Discard, Play a card for free): lit in the hand, the rest dimmed.
var choice_cards: PackedStringArray = PackedStringArray()
## The heroes a lost battle's DMG may go to: lit on the table while the dialog asks.
var damage_heroes: PackedStringArray = PackedStringArray()
## The hero picked to take it ("" until picked, or the only one) and the hand cards picked to take
## 1 DMG each, as positions in the hand (the same card may be there twice). CONFIRM sends them.
var damage_target: String = ""
## How many hits the battle in `_hit_key` started with: "HIT 1 OF 2" when more than one winner strikes.
var _hit_key: String = ""
var _hit_total: int = 0
var damage_cards: PackedInt32Array = PackedInt32Array()
## Which hit the picks belong to (slot, hitter, targets): a new hit starts with nothing picked,
## a band passing over the same hit keeps them.
var _damage_key: String = ""
## The energy claim variant: the split being set in the End phase box (stage id -> energy), and
## the decision it belongs to.
var energy_split: Dictionary = {}
## The energy window was closed by a click outside it: the split is made on the table (_energy_table).
var energy_on_table: bool = false
## Where a stage is on the screen, for the steps that stand by it: set by the match (stage id -> Vector2).
var stage_anchor: Callable
var _energy_rows: Dictionary[String, Control] = {}
var _energy_key: String = ""
var _target_why: Dictionary = {}
var _last_why_by: Dictionary = {}
var _aim_line: Control
## Under the phase ribbon while a battle is fought: which one and who with what Power.
var _battle_bar: HBoxContainer
var _battle_tug: BattleTug
## Which battle the tug shows ("" = none): a new one starts level.
var _tug_key: String = ""
## Each side's stages and cores in a box under its heroes (_side_board); key G folds them.
## The small STAGES tab beside the strip that hides or shows it.
## The battle camera is on (set by the match): letterbox, only the fighting heroes in the rosters.
var battle_cam: bool = false
var _letterbox: Array[ColorRect] = []
## The big card above the hand (GDD 11): the card under the mouse ("" = none) and the one shown.
var _hover_cid: String = ""
## The hero panel now drawn for each hero id (the panel hover looks them up).
var _slice_of: Dictionary[String, Control] = {}
## The hero panel under the mouse (found each frame in _process, not from enter / exit signals:
## a hovered panel opens, the panels are drawn anew and those signals got lost or came late).
var _panel_hover: String = ""
## Preroll: PASS offered under the clicked ball (offer_ball_pass).
var _ball_pass: Button
var _ball_pass_slot: int = -1
## Behind the damage choice, under the hand: its cards are clicked to take 1 DMG each.
var _damage_dim: ColorRect
var _dialog_sb: StyleBoxFlat
var _dialog_center: CenterContainer
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
		target_index = -1
		target_slot = -1
		target_heroes = PackedStringArray()
		targeting_changed.emit()
	# A new phase is called out in the middle (not on the first look, e.g. a loaded match), after
	# the banners of what led to it (playtest 2026-11-06: "START PHASE" came before the fight's winner).
	var phase_call: bool = false
	if _ribbon_phase(state.phase) != _ribbon_phase(_called_phase) or _called_phase.is_empty():
		# Not while a replay rewinds (its log gets shorter).
		# End is quiet (GDD 11): what it did shows through the log's own banners.
		phase_call = not _called_phase.is_empty() and PHASES.has(state.phase) and state.phase != GameState.PHASE_END and state.log.size() >= _log_seen \
				and GameSettings.banners() == "all"
	_called_phase = state.phase
	_scan_log()
	if phase_call:
		banner("%s PHASE" % _ribbon_phase(state.phase).to_upper(), Palette.PANEL_SOLID, "TURN %d" % state.turn, "", START_BANNER_TIME if state.phase == GameState.PHASE_START else PHASE_BANNER_TIME)
	_refresh_choice()
	_refresh_ribbon()
	_refresh_battle_bar()
	_refresh_energy()
	for slot: int in state.players.size():
		if slot < _rosters.size():
			_fill_roster(_rosters[slot], slot)
	# The hand first: a freshly dealt starting hand says when its buttons may come.
	_refresh_hand()
	_refresh_prompt()
	# Not behind the starting hand: the hand and its two buttons say it all (Marko 2026-11-09).
	_prompt_card.visible = not (_prompt.text.is_empty() and _detail.text.is_empty()) and not board_blocked()
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
	# The battle whose bands still show stays on the bar (shown_battle).
	var held: Dictionary = shown_battle()
	var live: bool = state.phase == GameState.PHASE_BATTLE and state.battle_index >= 0 and state.battle_index < state.battles.size()
	var on: bool = live or not held.is_empty()
	_battle_bar.visible = on
	_battle_tug.visible = on
	for bar: ColorRect in _letterbox:
		bar.visible = on and battle_cam
	if not on:
		_tug_key = ""
		return
	var turn: int = state.turn
	var index: int = state.battle_index
	var count: int = state.battles.size()
	var sides: Array[PackedStringArray] = [PackedStringArray(), PackedStringArray()]
	# The sum decides the battle (Marko 2026-11-08), of the heroes the engine counts: those on the map.
	var totals: Array[int] = [0, 0]
	if live:
		var ids: PackedStringArray = JsonUtil.as_strings(state.battles[state.battle_index].get("heroes", []))
		for hid: String in ids:
			var h: HeroState = state.hero(hid)
			if h != null and h.is_on_map():
				var t: int = clampi(state.team_of(h.owner), 0, 1)
				var pwr: int = engine.stat(state, h, "pwr")
				sides[t].append("%s %d" % [hero_name(h).to_upper(), pwr])
				totals[t] += pwr
		# Remembered also while another battle is held on the bar: it is what its own bands will hold.
		_bar_last = {"turn": turn, "index": index, "count": count, "heroes": ids,
			"side0": sides[0], "side1": sides[1], "total0": totals[0], "total1": totals[1]}
	if not held.is_empty():
		turn = JsonUtil.as_int(held.get("turn", turn))
		index = JsonUtil.as_int(held.get("index", index))
		count = JsonUtil.as_int(held.get("count", count))
		for t: int in 2:
			sides[t] = JsonUtil.as_strings(held.get("side%d" % t, []))
			totals[t] = JsonUtil.as_int(held.get("total%d" % t, 0))
	_battle_bar.add_child(UiShape.chip("BATTLE %d / %d" % [index + 1, count], Palette.ACCENT, Palette.FG, 20, 32.0, 16.0))
	for t: int in 2:
		if t == 1:
			_battle_bar.add_child(UiShape.chip("VS", Palette.PANEL_SOLID, Palette.MUTED, 16, 32.0, 10.0))
		_battle_bar.add_child(UiShape.chip("  +  ".join(sides[t]), Palette.PANEL_SOLID, Palette.team(t).lightened(0.25), 16, 32.0, 14.0))
	var key: String = "%d|%d" % [turn, index]
	if key != _tug_key:
		_tug_key = key
		_battle_tug.start(totals[0], totals[1])
	else:
		_battle_tug.show_totals(totals[0], totals[1])
	# The camera switch: on the battle, or the whole table (key in Settings → Keys).
	var cam_key: String = GameSettings.key_name(GameSettings.key("battle_cam"))
	var sw: UiShape = UiShape.chip(("● BATTLE CAM" if battle_cam else "○ TABLE") + "  ·  " + cam_key,
		Palette.GOLD if battle_cam else Palette.SURFACE_2, Color.BLACK if battle_cam else Palette.FG, 16, 32.0, 14.0)
	sw.mouse_filter = Control.MOUSE_FILTER_STOP
	sw.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sw.tooltip_text = "Battle camera on or off"
	sw.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			battle_cam_pressed.emit())
	_battle_bar.add_child(sw)
	_battle_bar.mouse_filter = Control.MOUSE_FILTER_PASS


## The connection above the other player's name (Marko 2026-11-08): green, gold or red by the round
## trip in ms, -1 hides it. On the left the MENU button is above the name, so it stands beside that.
func set_ping(ms: int, right: bool) -> void:
	if ms < 0:
		if _ping != null:
			_ping.queue_free()
			_ping = null
		_ping_text = ""
		return
	var text: String = "%d MS" % ms
	if text != _ping_text or _ping == null:
		if _ping != null:
			_ping.queue_free()
		_ping_text = text
		var col: Color = Color("23b14d") if ms < 90 else (Palette.GOLD if ms < 200 else Palette.ACCENT)
		_ping = UiShape.chip(text, col, Color.BLACK if ms < 200 else Palette.FG, 13, 22.0, 9.0)
		_ping.tooltip_text = "Connection to the other player"
		_ping.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(_ping)
	_ping.position = Vector2(size.x - 16.0 - _ping.custom_minimum_size.x, 32.0) if right else Vector2(116.0, 26.0)


## Who dropped, over the table (Marko 2026-11-08, from the mockups). The host waits for the guest and
## may go on waiting behind it or leave (the match is saved); a guest without its host can only leave.
func show_drop(who: String, host_side: bool) -> void:
	hide_drop()
	_drop = Control.new()
	_drop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drop.mouse_filter = Control.MOUSE_FILTER_STOP
	_drop.z_index = 80
	add_child(_drop)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drop.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drop.add_child(centre)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size = Vector2(700, 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(box)
	var chip: UiShape = UiShape.chip("CONNECTION LOST", Palette.ACCENT, Palette.FG, 20, 34.0, 14.0)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(chip)
	var title: Label = UiTheme.label("%s DROPPED" % who.to_upper(), 76)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var line: Label = UiTheme.label("Waiting for them to come back  ·  0:00" if host_side else "The match cannot go on without the host", 24, Palette.GOLD, false)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(line)
	var note := Label.new()
	note.text = "The match is saved. They can join again with the same name." if host_side else "The match is saved on their computer. Join again with the same name when they are back."
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Palette.MUTED)
	box.add_child(note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	if host_side:
		var keep := Button.new()
		keep.text = "KEEP WAITING"
		keep.add_theme_font_size_override("font_size", 24)
		keep.pressed.connect(hide_drop)
		row.add_child(keep)
	var leave := Button.new()
	leave.text = "SAVE AND LEAVE" if host_side else "MAIN MENU"
	leave.add_theme_font_size_override("font_size", 24)
	leave.pressed.connect(func() -> void: leave_pressed.emit())
	row.add_child(leave)
	if host_side:
		var since: int = Time.get_ticks_msec()
		var clock: Tween = line.create_tween().set_loops()
		clock.tween_interval(1.0)
		clock.tween_callback(func() -> void:
			var s: int = (Time.get_ticks_msec() - since) / 1000
			line.text = "Waiting for them to come back  ·  %d:%02d" % [s / 60, s % 60])


func hide_drop() -> void:
	if _drop != null:
		_drop.queue_free()
		_drop = null


## A short message under the ribbon on a slanted chip of `color`.
## How wide something centred on the screen can be at height `y` without touching what stands on the
## two sides there (the hero panels and their ability tabs).
func _room_between_rosters(y: float, height: float) -> float:
	var mid: float = size.x * 0.5
	var room: float = mid
	for i: int in mini(_rosters.size(), 2):
		for n: Node in _rosters[i].get_children():
			var row := n as Control
			if row == null or not row.visible:
				continue
			var r: Rect2 = row.get_global_rect()
			if r.position.y > y + height or r.end.y < y:
				continue
			room = minf(room, mid - r.end.x if i == 0 else r.position.x - mid)
	return 2.0 * maxf(room - TOAST_CLEAR, 0.0)


func toast(text: String, color: Color = Palette.GOLD, hold: float = 1.5) -> void:
	for c: Node in _toast_box.get_children():
		c.queue_free()
	var fg: Color = Color.BLACK if color.get_luminance() > 0.5 else Palette.FG
	# Below the battle bar when one shows.
	var base: float = 148.0 if _battle_bar.visible else 70.0
	var caps: String = text.to_upper()
	# As big as fits between the hero panels (Marko 2026-11-08: a long one ran over them).
	var room: float = _room_between_rosters(base, TOAST_H)
	var font_size: int = TOAST_FONT
	var font: Font = UiTheme.display_heavy()
	while font_size > TOAST_FONT_MIN and font.get_string_size(caps, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + TOAST_PAD * 2.0 > room:
		font_size -= 1
	var chip: UiShape = UiShape.chip(caps, color, fg, font_size, TOAST_H, TOAST_PAD)
	chip.position = Vector2(-chip.custom_minimum_size.x * 0.5, 0)
	_toast_box.add_child(chip)
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_box.modulate.a = 1.0
	_toast_box.position.y = base - 6.0
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_box, "position:y", base, 0.12).from(base - 18.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(hold)
	_toast_tween.tween_property(_toast_box, "modulate:a", 0.0, 0.4)


## A slanted band across the screen (BATTLE!, RING-OUT …): in, hold, out. Queued.
## `card` (a combo) shows that card big over the screen instead of the band (_combo_show).
func banner(title: String, color: Color, left: String = "", right: String = "", hold: float = BANNER_TIME, card: String = "", parts: PackedStringArray = PackedStringArray()) -> void:
	# Banners can be cut down to the big moments, or switched off (Settings → Interface).
	if GameSettings.banners() == "off":
		return
	# A phase call-out still waiting is out of date once a newer one comes (fast bots could leave
	# "TURN 3 · PREROLL" showing in turn 5).
	if title.ends_with(" PHASE"):
		_banners = _banners.filter(func(q: Dictionary) -> bool: return not str(q["title"]).ends_with(" PHASE"))
	var b: Dictionary = {"title": title, "color": color, "left": left, "right": right, "hold": hold, "lines": PackedStringArray(), "card": card, "parts": parts}
	if not _tagging.is_empty():
		b["battle"] = _tagging
	if _grouping:
		_group.append(b)
		return
	_banners.append(b)
	if not _banner_busy:
		_next_banner()


## The battle the screen is still on (Marko 2026-11-09: BATTLE! and TIE! came when the bar above
## was already on the next fight): the engine opens the next battle in the same move that decides
## this one, but the bar, the scale, the camera and the rings stay on this one until its bands
## have passed. Empty when the state itself is what shows.
func shown_battle() -> Dictionary:
	if _now.has("battle"):
		return JsonUtil.as_dict(_now["battle"])
	for q: Dictionary in _banners:
		if q.has("battle"):
			return JsonUtil.as_dict(q["battle"])
	return _end_battle()


## The battle a match ended in (the last KO, a surrender while it was fought), kept on the screen
## until the end screen comes: its bar, its panels, its figures and rings stay as they were, and
## no range comes back under the band that says who won (Marko 2026-11-11). Empty when the match
## ended otherwise, or is not over.
func _end_battle() -> Dictionary:
	if state == null or not state.is_over() or not end_hold or _bar_last.is_empty():
		return {}
	for i: int in range(state.log.size() - 1, -1, -1):
		var e: Dictionary = state.log[i]
		if str(e.get("type", "")) != "match_end":
			continue
		if str(e.get("phase", "")) == GameState.PHASE_BATTLE and JsonUtil.as_int(e.get("turn", -1), -1) == JsonUtil.as_int(_bar_last.get("turn", -2), -2):
			return _bar_last
		break
	return {}


func shown_battle_ids() -> PackedStringArray:
	return JsonUtil.as_strings(shown_battle().get("heroes", []))


## New log entries become bands now (the match calls it before it draws the table, so the table
## already knows which battle the bands keep on the screen). refresh() does the same.
func scan_log() -> void:
	if state != null:
		_scan_log()


func _note_shown_battle() -> void:
	var held: Dictionary = shown_battle()
	var key: String = "" if held.is_empty() else "%d|%d" % [JsonUtil.as_int(held.get("turn", 0)), JsonUtil.as_int(held.get("index", 0))]
	if key == _shown_key:
		return
	_shown_key = key
	refresh.call_deferred()
	shown_battle_changed.emit.call_deferred()


## What the bar showed for the battle of log event `e`, with the totals it was decided on.
func _battle_tag(e: Dictionary) -> Dictionary:
	var turn: int = JsonUtil.as_int(e.get("turn", state.turn))
	var index: int = JsonUtil.as_int(e.get("index", 0))
	var ids: PackedStringArray = JsonUtil.as_strings(e.get("heroes", []))
	var tag: Dictionary = {}
	if JsonUtil.as_int(_bar_last.get("turn", -1), -1) == turn and JsonUtil.as_int(_bar_last.get("index", -1), -1) == index:
		tag = _bar_last.duplicate()
	else:
		var sides: Array[PackedStringArray] = [PackedStringArray(), PackedStringArray()]
		var totals: Array[int] = [0, 0]
		for hid: String in ids:
			var x: HeroState = state.hero(hid)
			if x == null:
				continue
			var t: int = clampi(state.team_of(x.owner), 0, 1)
			var pwr: int = engine.stat(state, x, "pwr")
			sides[t].append("%s %d" % [hero_name(x).to_upper(), pwr])
			totals[t] += pwr
		tag = {"turn": turn, "index": index, "count": maxi(state.battles.size(), index + 1),
			"side0": sides[0], "side1": sides[1], "total0": totals[0], "total1": totals[1]}
	tag["heroes"] = ids
	var power: Dictionary = JsonUtil.as_dict(e.get("power", {}))
	for k: Variant in power:
		for t: int in 2:
			if str(k) == str(t):
				tag["total%d" % t] = JsonUtil.as_int(power[k])
	return tag


## True while a band is on the screen or waiting its turn. The match waits for it: bots, clocks,
## auto-pass and the choice dialogs (playtest 2026-11-01: several moments at once piled up over
## each other and over a choice).
func is_announcing() -> bool:
	return _banner_busy


## The bands of one moment, merged: BATTLE! and the ties stand alone (they show both sides);
## the rest become one band, the loudest as its title and the others as lines beside it.
func _push_group() -> void:
	_group = gather_kos(_group)
	var run: Array[Dictionary] = []
	for b: Dictionary in _group:
		if stands_alone(b):
			if not run.is_empty():
				_banners.append(merge_banners(run))
				run = []
			_banners.append(b)
		else:
			run.append(b)
	if not run.is_empty():
		_banners.append(merge_banners(run))
	_group.clear()
	if not _banner_busy and not _banners.is_empty():
		_next_banner()


## Heroes knocked out in the same moment fall in one announcement, side by side (KO6), after the moment's
## other bands (the blows that did it).
static func gather_kos(group: Array[Dictionary]) -> Array[Dictionary]:
	var first_ko: Dictionary = {}
	var kept: Array[Dictionary] = []
	for b: Dictionary in group:
		if not b.has("ko"):
			kept.append(b)
		elif first_ko.is_empty():
			first_ko = b
		else:
			var ids: PackedStringArray = JsonUtil.as_strings(first_ko["ko"])
			ids.append_array(JsonUtil.as_strings(b["ko"]))
			first_ko["ko"] = ids
	if not first_ko.is_empty():
		kept.append(first_ko)
	return kept


static func stands_alone(b: Dictionary) -> bool:
	var title: String = str(b.get("title", ""))
	return title == "BATTLE!" or title.begins_with("TIE") or title.ends_with(" PHASE") or not str(b.get("card", "")).is_empty() \
			or b.has("ko")


## How loud a band is: the winner names the moment, a KO or a ring-out comes next, then the
## blows, then a claim; an ability that fired is the quietest.
static func loudness(b: Dictionary) -> int:
	var title: String = str(b.get("title", ""))
	if title.ends_with("THE FIGHT!"):
		return 5
	if title == "KO" or title == "RING-OUT":
		return 4
	if title.contains(" TAKES ") or title.contains(" DECKS "):
		return 2
	if title == "STAGE CLAIMED":
		return 1
	return 0


## One band out of several: the loudest keeps its title, colour and sides; the others turn into
## lines ("KO · SHANKS", "STAGE CLAIMED · MARKO · DRESSROSA"), at most three, the rest counted.
static func merge_banners(run: Array[Dictionary]) -> Dictionary:
	if run.size() == 1:
		return run[0]
	var best: int = 0
	for i: int in run.size():
		if loudness(run[i]) > loudness(run[best]):
			best = i
	var top: Dictionary = run[best].duplicate()
	for one: Dictionary in run:
		if not top.has("battle") and one.has("battle"):
			top["battle"] = one["battle"]
	var lines := PackedStringArray()
	var hold: float = 0.0
	for i: int in run.size():
		hold = maxf(hold, JsonUtil.as_float(run[i].get("hold", BANNER_TIME), BANNER_TIME))
		if i != best:
			lines.append(line_of(run[i]))
	if lines.size() > 3:
		var more: int = lines.size() - 2
		lines = lines.slice(0, 2)
		lines.append("+%d MORE" % more)
	top["lines"] = lines
	# Time to read every line (Marko 2026-11-01: a merged band went before it could be read); a
	# click or Enter still takes it away sooner.
	top["hold"] = minf(MERGED_MAX_TIME, hold + MERGED_LINE_TIME * lines.size())
	return top


static func line_of(b: Dictionary) -> String:
	var parts := PackedStringArray()
	for key: String in ["title", "left", "right"]:
		var s: String = str(b.get(key, "")).replace("\n", " ").strip_edges()
		if not s.is_empty():
			parts.append(s)
	return " · ".join(parts)


## The band on the screen goes out now (a click or Enter: the player has seen enough).
func skip_banner() -> void:
	if not _banner_busy or _band == null or not is_instance_valid(_band):
		return
	if _band_tween != null and _band_tween.is_valid():
		_band_tween.kill()
	var band: Panel = _band
	_band = null
	var t: Tween = band.create_tween()
	if band.has_meta("show"):
		# The combo card fades out where it is.
		t.tween_property(band, "modulate:a", 0.0, 0.12)
	else:
		t.tween_property(band, "position:x", size.x + 100.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		band.queue_free()
		_next_banner())


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
	_menu_button = menu
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
	_prompt_card.gui_input.connect(func(e: InputEvent) -> void:
		if energy_on_table and e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			energy_on_table = false
			refresh())
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
	# Room for a picked or hovered tile to grow without lying over its neighbours (Marko 2026-11-02).
	_tray.add_theme_constant_override("separation", 26)
	add_child(_tray)

	# The deck and the graveyard of the player whose hand shows: the graveyard left of the hand,
	# the deck right of it (Marko 2026-10-26).
	_piles = VBoxContainer.new()
	# Small, one above the other beside the energy, clear of the hand (Marko 2026-11-08, from the mockups).
	_piles.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_piles.position = Vector2(PILES_X, DECK_PILE_Y)
	_piles.scale = Vector2.ONE * PILE_SCALE
	_piles.add_theme_constant_override("separation", 18)
	_piles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_piles)
	_grave_spot = Control.new()
	_grave_spot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_grave_spot.position = Vector2(PILES_X, GRAVE_PILE_Y)
	_grave_spot.scale = Vector2.ONE * PILE_SCALE
	_grave_spot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_grave_spot)
	# The hand: a fan of cards at the bottom; it slides down when the mouse is over the table.
	_damage_dim = ColorRect.new()
	_damage_dim.color = Color(0, 0, 0, 0.38)
	_damage_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_dim.visible = false
	add_child(_damage_dim)
	_mulligan_dim = ColorRect.new()
	_mulligan_dim.color = Color(0, 0, 0, MULLIGAN_DIM)
	_mulligan_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mulligan_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_mulligan_dim.visible = false
	add_child(_mulligan_dim)
	# The menu stays within reach above it.
	move_child(_menu_button, _mulligan_dim.get_index())
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

	_dialog_center = CenterContainer.new()
	_dialog_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dialog_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dialog_center)
	_dialog = PanelContainer.new()
	_dialog.visible = false
	var dsb: StyleBoxFlat = UiTheme.box(Color(0.03, 0.03, 0.03, 0.96), 0, Color(0, 0, 0, 0), 28, 22)
	dsb.border_color = Palette.GOLD
	dsb.border_width_top = 4
	_dialog.add_theme_stylebox_override("panel", dsb)
	_dialog_sb = dsb
	_dialog_center.add_child(_dialog)
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
	_battle_tug = BattleTug.new()
	_battle_tug.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_battle_tug.position = Vector2(-BattleTug.WIDTH * 0.5, TUG_Y)
	_battle_tug.visible = false
	add_child(_battle_tug)

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
	# The end screen takes every click (Marko 2026-11-08: the table under it still took them).
	_over.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_over)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.84)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_over.add_child(dim)
	var over_center := CenterContainer.new()
	over_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.add_child(over_center)
	_over_box = VBoxContainer.new()
	_over_box.custom_minimum_size = Vector2(760, 0)
	_over_box.add_theme_constant_override("separation", 16)
	_over_box.alignment = BoxContainer.ALIGNMENT_CENTER
	over_center.add_child(_over_box)

	_toast_box = Control.new()
	_toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.modulate.a = 0.0
	add_child(_toast_box)


# --- phase ribbon ----------------------------------------------------------------

func _refresh_ribbon() -> void:
	_clear(_ribbon)
	# The turn and phase of the battle whose bands still show (shown_battle).
	var held: Dictionary = shown_battle()
	var turn_n: int = state.turn if held.is_empty() else JsonUtil.as_int(held.get("turn", state.turn))
	var phase_now: String = state.phase if held.is_empty() else GameState.PHASE_BATTLE
	var turn_text: String = "TURN %d" % turn_n if turn_n > 0 else ("MULLIGAN" if state.phase == GameState.PHASE_MULLIGAN else "SETUP")
	var turn: UiShape = UiShape.chip(turn_text, Palette.ACCENT, Palette.FG, 28, 40.0, 22.0)
	if turn_n > 0:
		turn.tooltip_text = "Initiative this turn: %s" % player_name(state.initiative)
		turn.mouse_filter = Control.MOUSE_FILTER_PASS
	_ribbon.add_child(turn)
	if turn_n > 0:
		var first: UiShape = UiShape.chip("▸ " + player_name(state.initiative).to_upper(),
			Palette.team(state.team_of(state.initiative)), Palette.FG, 14, 26.0, 12.0)
		first.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		first.tooltip_text = "Goes first this turn"
		first.mouse_filter = Control.MOUSE_FILTER_PASS
		_ribbon.add_child(first)
		var now: int = RIBBON_PHASES.find(_ribbon_phase(phase_now))
		for i: int in RIBBON_PHASES.size():
			# Only the current phase in its colour, as the phase chips on the cards (Marko 2026-11-06: the
			# others in colour drew the eye away from it); the ones to come plain grey, the ones gone darker.
			var label: String = RIBBON_PHASES[i].to_upper()
			var pc: Color = Palette.PHASE_COLORS.get(RIBBON_PHASES[i], Palette.FG)
			var ink: Color = Color.BLACK if pc.get_luminance() > 0.45 else Palette.FG
			var fill: Color = pc if i == now else Palette.SURFACE_2 if i > now else Palette.SURFACE_2.darkened(0.35)
			var fg: Color = ink if i == now else Palette.MUTED if i > now else Palette.DIM
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
	if state.turn > 0 and not state.is_over() and not battle_cam:
		col.add_child(_side_board(slot, right))
		if not p.assists.is_empty():
			col.add_child(_assist_board(p, slot, right))
	# Your own deck and graveyard stand as piles by the hand (_refresh_piles); the counts here
	# are for the other side (and for two players at one screen).
	if local_slots.size() == 1 and local_slots[0] == slot:
		return
	# Not during setup (Marko 2026-11-06), as the piles by the hand.
	if intro_dice or state.phase == GameState.PHASE_SETUP_STAGES or state.phase == GameState.PHASE_SETUP_CORES:
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
	_slice_of[h.id] = s
	s.set_mirrored(right)
	s.art = db.thumb(card.id) if db != null and card != null else null
	s.art_region = HeroSlice.region_for(s.art)
	s.art_fallback = hero_color.darkened(0.3)
	s.bg = Color("222222") if h.id == hover_hero else Palette.PANEL_SOLID
	s.color_edge = hero_color
	if ko:
		s.art_tint = Color(0.35, 0.35, 0.35)
		# The panel fades, its KNOCKED OUT stamp stays bright.
		s.self_modulate.a = 0.6
		s.content.modulate.a = 0.6
	if active:
		# Every panel is full width now (playtest 2026-10-30); the activated one stands out by a
		# thick gold edge and a warm ground instead of sticking out.
		s.outline = Palette.GOLD
		s.outline_width = 4.0
		s.bg = Color("2b2416") if h.id != hover_hero else Color("3a3020")
	elif pickable:
		var chosen_pick: bool = picks.get(h.owner, "") == h.id
		s.outline = Color("ffd36a") if chosen_pick else Color(Palette.GOLD, 0.55)
		s.outline_width = 3.5 if chosen_pick else 2.0
	if in_battle:
		s.stripe = Palette.ACCENT
	s.custom_minimum_size = Vector2(ROSTER_WIDTH, SLICE_HEIGHT + (28.0 if expanded else 0.0))
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
		_hovered(shown_id))
	s.mouse_exited.connect(func() -> void:
		if _hover_cid == shown_id:
			_hover_cid = "")
	if card != null:
		s.tooltip_text = _card_tip("%s\n%s" % [card.name, card.text])
	var slice_h: float = s.custom_minimum_size.y
	if ko:
		# KO (item 28, K3, Marko 2026-11-09): a slanted red KNOCKED OUT stamp over the middle of the panel.
		_panel_stamp(s, "KNOCKED OUT", 24, -7.0, Vector2(ROSTER_WIDTH * 0.5, slice_h * 0.5))
	elif h.statuses.has("no_claim"):
		# Can't claim (Marko 2026-11-09, C3 big, no turns): NO CLAIM over the portrait, a little past it.
		var px: float = (HeroSlice.ART_W + HeroSlice.CUT) * 0.5
		_panel_stamp(s, "NO CLAIM", 21, -12.0, Vector2(ROSTER_WIDTH - px if right else px, slice_h * 0.5))

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
	# Evolved: its level by the name (playtest 2026-10-30).
	if not h.evolutions.is_empty() and not ko:
		var evo: UiShape = UiShape.chip("EVO %d" % h.evolutions.size(), hero_color, Color.BLACK if hero_color.get_luminance() > 0.5 else Palette.FG, 12, 20.0, 8.0)
		evo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		evo.tooltip_text = "Evolved %d time%s" % [h.evolutions.size(), "" if h.evolutions.size() == 1 else "s"]
		top.add_child(evo)
	var tag: UiShape = _hero_tag(h, active, pickable, in_battle)
	# A card effect asks for a hero (heal, swap…): the ones it may take are lit, the rest fade.
	if not choice_heroes.is_empty() and not ko:
		if choice_heroes.has(h.id):
			var chosen: bool = h.id == hover_hero
			tag = UiShape.chip("CHOSEN" if chosen else "PICK", Palette.GOLD if chosen else Color(Palette.GOLD, 0.25),
				Color.BLACK if chosen else Palette.GOLD, 12, 20.0, 8.0)
			s.outline = Color("ffd36a") if chosen else Color(Palette.GOLD, 0.8)
			s.outline_width = 3.0
		else:
			s.modulate.a = 0.45
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
	# Statuses show as chips under the panel (_effect_chips); a KO is the stamp over the panel.
	if not ko and not h.equipment.is_empty():
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
		stats.text = _stats_bbcode(h, right)
		col.add_child(stats)
	var wrap := MarginContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The panel keeps its own height (playtest 2026-11-06: an evolved hero's two ability tabs stretched
	# it and left a gap under the stats).
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrap.add_child(s)
	# The hero's ability as a tab beside the panel's outer end (not over its colour edge), lasting
	# effects as chips under it.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
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


## PWR DMG RNG KB as they stand now, each in the colour of what moved it (item 25, B3b, Marko
## 2026-11-09): up or down, and for how long; white when nothing did.
func _stats_bbcode(h: HeroState, right: bool) -> String:
	var parts := PackedStringArray()
	for key: String in ["pwr", "dmg", "rng", "kb"]:
		var value: int = engine.stat(state, h, key)
		var text: String = "%s %d" % [key.to_upper(), value]
		var phase: int = JsonUtil.as_int(h.phase_bonus.get(key, 0))
		var turn: int = JsonUtil.as_int(h.turn_bonus.get(key, 0))
		var lasting: int = value - engine.base_stat(state, h, key) - phase - turn
		var tint: Color = stat_tint(phase, turn, lasting)
		if tint.a > 0.0:
			text = "[color=#%s]%s[/color]" % [tint.to_html(false), text]
		parts.append(text)
	return ("[right]%s[/right]" if right else "%s") % "   ".join(parts)


## The colour of a stat moved by a bonus for this phase, this turn, or for good (B3b): the shortest one
## says it (phase, then turn, then lasting), its sign whether up or down. Clear when nothing moved it.
static func stat_tint(phase: int, turn: int, lasting: int) -> Color:
	if phase != 0:
		return BONUS_PHASE_UP if phase > 0 else BONUS_PHASE_DOWN
	if turn != 0:
		return BONUS_TURN_UP if turn > 0 else BONUS_TURN_DOWN
	if lasting != 0:
		return BONUS_LASTING_UP if lasting > 0 else BONUS_LASTING_DOWN
	return Color(0, 0, 0, 0)


## A slanted stamp over a hero's panel (KNOCKED OUT, NO CLAIM): red, white words, a black rim, centred on `at`.
func _panel_stamp(s: Control, text: String, font_size: int, degrees: float, at: Vector2) -> void:
	var stamp: UiShape = UiShape.chip(text, Palette.ACCENT, Palette.FG, font_size, font_size * 1.6, font_size * 0.5)
	# The other side's panels are laid out right to left, which would mirror where it stands.
	stamp.layout_direction = Control.LAYOUT_DIRECTION_LTR
	stamp.outline = Color.BLACK
	stamp.outline_width = 3.0
	stamp.size = stamp.custom_minimum_size
	stamp.pivot_offset = stamp.size * 0.5
	stamp.rotation_degrees = degrees
	stamp.position = at - stamp.size * 0.5
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(stamp)


## A hero panel under the mouse opens with its stats, as hovering its ball does (Marko 2026-11-06).
## Which panel is under the mouse is looked up every frame from the panels' rectangles.
func _track_panel_hover() -> void:
	var mouse: Vector2 = get_global_mouse_position()
	var now: String = ""
	for id: String in _slice_of if not menu_open and not board_blocked() else {}:
		var c: Control = _slice_of[id]
		if c != null and is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(mouse):
			now = id
			break
	if now != _panel_hover:
		_panel_hover = now
		hero_hovered.emit(now)


## Preroll: a click on your activated ball offers PASS under it (Marko 2026-11-06), the same as
## the PASS button; it goes on the next click, or when the move is no longer yours.
func can_pass(slot: int) -> bool:
	return state != null and _in_card_round() and state.to_act == slot and state.pending.is_empty() and local_slots.has(slot)


func offer_ball_pass(slot: int, at: Vector2) -> void:
	if not can_pass(slot):
		return
	if _ball_pass == null:
		_ball_pass = Button.new()
		_ball_pass.text = "PASS  ·  ON TO ROLL"
		_ball_pass.theme_type_variation = &"Primary"
		_ball_pass.focus_mode = Control.FOCUS_NONE
		_ball_pass.add_theme_font_size_override("font_size", 17)
		_ball_pass.pressed.connect(func() -> void:
			var who: int = _ball_pass_slot
			hide_ball_pass()
			if can_pass(who):
				pass_pressed.emit(who))
		add_child(_ball_pass)
		# Under the bands (Marko 2026-11-08: ROLL stood over a phase call-out).
		move_child(_ball_pass, _banner_layer.get_index())
	_ball_pass_slot = slot
	_ball_pass.text = "PASS  ·  ON TO ROLL" if state.phase == GameState.PHASE_PREROLL else "PASS"
	_ball_pass.reset_size()
	_ball_pass.position = at - Vector2(_ball_pass.size.x * 0.5, 0.0)
	_ball_pass.visible = true


func ball_pass_shown() -> bool:
	return _ball_pass != null and _ball_pass.visible


## The PASS under a ball, kept under it: `at` is where the ball's foot is on the screen now.
func move_ball_pass(at: Vector2) -> void:
	if _ball_pass != null:
		_ball_pass.position = at - Vector2(_ball_pass.size.x * 0.5, 0.0)


func hide_ball_pass() -> void:
	if _ball_pass != null:
		_ball_pass.visible = false
	_ball_pass_slot = -1


## The abilities on a hero's own card and its evolutions: [{card, index, effect, n}] (n: which
## ability of that card, for its name).
func _hero_abilities(h: HeroState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# Only the card the hero is now: an evolution replaces the ability of the card under it (GDD 10;
	# Marko 2026-11-09: an evolved Luffy still showed the base card's ability, which the engine
	# never offers).
	var card: CardDef = engine.stat_card(h)
	if card == null:
		return out
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
	# Nor for a hero that is out (Marko 2026-11-09: the bolt hung by a KO hero).
	if list.is_empty() or h.is_ko():
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
	# Two or more (a hero with an evolution): each tab two lines, so the column is no taller than the panel.
	var compact: bool = list.size() > 1
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
		if not compact:
			v.add_child(UiTheme.label(head, 11, fg if can else Palette.MUTED, false))
		elif e.once and not used:
			status += "  ·  ONCE PER TURN"
		# The whole name, in smaller letters when it must (Marko 2026-11-09: "GOMU GOMU NO G…"); only a
		# name too long even then is cut.
		var title: String = _ability_title(a).to_upper()
		var name_size: int = 16 if compact else 18
		while name_size > ABILITY_NAME_MIN and UiTheme.display_heavy().get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > ABILITY_NAME_W:
			name_size -= 1
		var name_l: Label = UiTheme.label(title, name_size, fg)
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
	# Copies of a card are one offer (Marko 2026-11-08): the button plays one of them.
	var offered := PackedStringArray()
	for cid: String in cards:
		if offered.has(cid):
			continue
		offered.append(cid)
		var card: CardDef = engine.catalog.get_card(cid)
		var cost: int = engine.card_cost(state, state.player(who), card) if card != null else 0
		_action("PLAY %s  ·  %d" % [(card.name if card != null else cid).to_upper(), cost],
			func() -> void: card_pressed.emit(who, cid, ""), &"Gold")
	# The card is not thrown up big by itself: the button says it, hover or right click shows it
	# (Marko 2026-11-02).
	_action("GO ON", func() -> void: pass_pressed.emit(who), &"Primary")


## The ability's name from the card (Card Engine, underlined), else what kind it is.
func _ability_title(a: Dictionary) -> String:
	var card: CardDef = a["card"]
	var e: FxEffect = a["effect"]
	var name: String = card.ability_name(JsonUtil.as_int(a["n"]))
	return name if not name.is_empty() else "%s ability" % e.when.capitalize()


## What lasts on a hero now, as chips under its panel: statuses with their turns. Null when nothing
## does. Bonuses for the phase or the turn are the colour of the stat instead (item 25, B3b), and
## "can't claim" is the NO CLAIM stamp on the portrait.
func _effect_chips(h: HeroState, right: bool) -> Control:
	var items: Array[Array] = []
	var names: Dictionary = {"immune_kb": "IMMUNE TO KB", "stun": "STUNNED", "hold_hit": "NO HIT, DOUBLE KB"}
	for k: String in h.statuses:
		if k == "no_claim":
			continue
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
## `small`: the box under the heroes, where six stand in one row.
func _core_slot(core_id: String, hero_color: Color, small: bool = false) -> Control:
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
		Palette.HP if v > 0 else Palette.ACCENT, 10 if small else 11, 15.0 if small else 16.0, 3.0 if small else 6.0)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.tooltip_text = "%s core: %s" % [card.kind, card.name]
	return chip


func _hero_tag(h: HeroState, active: bool, pickable: bool, in_battle: bool) -> UiShape:
	# A KO is the stamp over the panel (item 28): no tag beside the HP.
	if h.is_ko():
		return null
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
	var held: Dictionary = shown_battle()
	if not held.is_empty():
		return JsonUtil.as_strings(held.get("heroes", [])).has(h.id)
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
	if _ball_pass_slot >= 0 and not can_pass(_ball_pass_slot):
		hide_ball_pass()
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
		# The who-starts dice come first: no tray under them (its picked tile drew over their dim).
		if not intro_dice:
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
		elif str(d.get("type", "")) == FxRuntime.DECISION_CHOOSE and str(d.get("kind", "")) == "hero":
			_prompt.text = str(d.get("prompt", "Choose a hero"))
			_detail.text = "%s: click a lit hero on the table, or its panel." % player_name(who)
		elif str(d.get("type", "")) == FxRuntime.DECISION_CHOOSE and str(d.get("kind", "")) == "core" and not choice_cores.is_empty():
			_prompt.text = str(d.get("prompt", "Choose a core"))
			_detail.text = "%s: click a lit core on the table." % player_name(who)
		elif str(d.get("type", "")) == FxRuntime.DECISION_CHOOSE and str(d.get("kind", "")) == "card" and not choice_cards.is_empty():
			_prompt.text = str(d.get("prompt", "Choose a card"))
			_detail.text = "%s: click a lit card in your hand." % player_name(who)
		elif str(d.get("type", "")) == RulesEngine.DECISION_ROLL_OFFER:
			_roll_offer_prompt(d, who)
		elif str(d.get("type", "")) == RulesEngine.DECISION_COMBO:
			# The window says it all, as for a hit.
			pass
		elif str(d.get("type", "")) == RulesEngine.DECISION_STAGE_ENERGY:
			# The window says it all, as for a hit; with the split on the table the card and CONFIRM do.
			if not _energy_decision().is_empty():
				_energy_prepare(d, who)
			if energy_on_table and not _energy_decision().is_empty():
				var e_left: int = _energy_left(d)
				_kicker.text = "END PHASE"
				_prompt.text = "%d energy into your stages" % JsonUtil.as_int(d.get("energy", 0))
				_detail.text = "Split it with − and + by each stage. Click here for the window."
				var ok: Button = _action("CONFIRM" if e_left == 0 else "CONFIRM  %d LEFT" % e_left, func() -> void: _energy_confirm(d, who), &"Primary")
				ok.disabled = e_left != 0
		elif str(d.get("type", "")) == RulesEngine.DECISION_DAMAGE:
			# The box in the middle says it all (Marko 2026-11-08).
			pass
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
		# Your own ones stay in the tray, darker and not to be picked, while the other places (online
		# playtest 2026-11-07: they vanished every time it was the other player's turn). Darker only:
		# see-through ones over the table were hard to read (Marko 2026-11-09).
		if not local_slots.is_empty():
			# None of them picked or bigger while waiting: all the same size.
			var pick: String = setup_pick
			setup_pick = ""
			_setup_tray(local_slots[0], stages)
			setup_pick = pick
			for c: Node in _tray.get_children():
				(c as CanvasItem).modulate = TRAY_WAITING
				_no_mouse(c)
		return
	_prompt.text = "Place a stage" if stages else "Place a core"
	_detail.text = ("In the middle third of the map." if stages else "In the opponent's half.") + "  Pick one below, then click a highlighted hex."
	if local_slots.size() > 1:
		_detail.text = "%s: " % player_name(who) + _detail.text
	_setup_tray(who, stages)


static func _no_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c: Node in n.get_children():
		_no_mouse(c)


## The tray: the stages (or cores) `who` still has to place, as cards where there is a picture.
func _setup_tray(who: int, stages: bool) -> void:
	for id: String in setup_items(state, who):
		# Stages come as their cards, so the effect is there to read (playtest 2026-10-30).
		if stages and state.stage(id) != null and db != null and db.thumb(state.stage(id).card_id) != null:
			_tray.add_child(_setup_card(id, state.stage(id).card_id))
			continue
		if not stages and state.core(id) != null and db != null and db.thumb(state.core(id).card_id) != null:
			_tray.add_child(_setup_core(id, state.core(id).card_id))
			continue
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


## A stage to place as its card (Marko 2026-11-01): it grows under the mouse, the picked one stays
## bigger with a gold edge and PICKED; a click picks it, a right click or the card-zoom key shows it big.
func _setup_card(id: String, card_id: String) -> Control:
	var art := TextureRect.new()
	art.texture = db.thumb(card_id)
	art.custom_minimum_size = Vector2(120, 168)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return _setup_tile(id, card_id, art)


## A core to place as its hex picture with the value under it (Marko 2026-11-01: not "Core · Buff").
func _setup_core(id: String, card_id: String) -> Control:
	var card: CardDef = engine.catalog.get_card(card_id)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(96, 128)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(78, 82)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Only the hex token in the middle of the core card, the white card around it gone.
	pic.texture = db.core_token(card_id)
	col.add_child(pic)
	var family: String = card.core_family() if card != null else ""
	var tint: Color = PlayerCard.CORE_FAMILY_COLORS[family] if PlayerCard.CORE_FAMILY_COLORS.has(family) else Palette.FG
	var value: Label = UiTheme.label(card.name.split(" ")[0] if card != null else "?", 22, tint)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(value)
	var sub: Label = UiTheme.label(card.kind.to_upper() if card != null else "", 11, Palette.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	return _setup_tile(id, card_id, col)


func _setup_tile(id: String, card_id: String, content: Control) -> Control:
	var picked: bool = id == setup_pick
	var tile := PanelContainer.new()
	var sb: StyleBoxFlat = UiTheme.box(Color(0.05, 0.05, 0.05, 0.9) if content is VBoxContainer else Color(0, 0, 0, 0), 6, Color(0, 0, 0, 0), 4, 4)
	sb.set_border_width_all(4)
	sb.border_color = Palette.GOLD if picked else Color(0, 0, 0, 0)
	tile.add_theme_stylebox_override("panel", sb)
	tile.add_child(content)
	# A container puts its children's scale back to 1, so the tray holds a plain box and the
	# panel inside it grows (from its bottom middle).
	var holder := Control.new()
	holder.custom_minimum_size = content.get_combined_minimum_size() + Vector2(8, 8)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(tile)
	tile.size = holder.custom_minimum_size
	tile.pivot_offset = Vector2(tile.size.x * 0.5, tile.size.y)
	var rest: float = 1.18 if picked else 1.0
	tile.scale = Vector2.ONE * rest
	holder.z_index = 2 if picked else 0
	if picked:
		# On the card's top left corner, half over its edge (Marko 2026-11-02: not inside the card).
		var chip: UiShape = UiShape.chip("PICKED", Palette.GOLD, Color.BLACK, 12, 20.0, 8.0)
		chip.position = Vector2(tile.size.x * (1.0 - rest) * 0.5 + 2.0, tile.size.y * (1.0 - rest) - 10.0)
		chip.z_index = 1
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(chip)
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var tip: String = _setup_tip(id)
	tile.tooltip_text = _card_tip((tip + "\n" if not tip.is_empty() else "") + "Click to pick, right click to see it big")
	tile.mouse_entered.connect(func() -> void:
		_hovered(card_id)
		holder.z_index = 3
		if not picked:
			sb.border_color = Color(Palette.GOLD, 0.55)
		tile.create_tween().tween_property(tile, "scale", Vector2.ONE * maxf(rest, 1.14), 0.1))
	tile.mouse_exited.connect(func() -> void:
		if _hover_cid == card_id:
			_hover_cid = ""
		holder.z_index = 2 if picked else 0
		sb.border_color = Palette.GOLD if picked else Color(0, 0, 0, 0)
		tile.create_tween().tween_property(tile, "scale", Vector2.ONE * rest, 0.1))
	tile.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			# Accept first (playtest 2026-11-06): the pick redraws the tray and takes this tile out of
			# the tree, so a later accept_event() did nothing and the click placed the stage under it.
			tile.accept_event()
			if (e as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
				_toggle_big(card_id)
			else:
				setup_item_pressed.emit(id))
	return holder


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
	var names: Dictionary = {"immune_kb": "Immune to KB", "stun": "Stunned", "hold_hit": "No hit, double KB", "no_claim": "Can't claim"}
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
	_track_panel_hover()
	if _hand_box == null or state == null:
		return
	_place_energy_rows()
	_fit_tug()
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
	# card, or a card effect asks for a card from it), else only the tops of the cards show.
	var mouse_at: Vector2 = demo_mouse if demo_mouse.x >= 0.0 else get_local_mouse_position()
	var up: bool = (not menu_open and mouse_at.y > size.y - HAND_HEIGHT - 40.0 and state.phase != GameState.PHASE_START) or is_targeting() or (not choice_cards.is_empty() and choice_slot == hand_slot()) or damage_picking(hand_slot())
	if _aim_line != null and (is_targeting() or _aim_line.get_meta("drawn", false)):
		_aim_line.set_meta("drawn", is_targeting())
		_aim_line.queue_redraw()
	var target: float = 0.0 if up else HAND_HEIGHT - 110.0
	_hand_drop = move_toward(_hand_drop, target, delta * 900.0)
	_hand_box.position.y = size.y - HAND_HEIGHT + 30.0 + _hand_drop
	_stand_cards(delta, up)


# --- hand ------------------------------------------------------------------------

## The balance bar sits under the strip, in from its two ends by the same amount: both lean, so that is
## measured where they meet, the strip's bottom corners and the bar's top ones (Marko 2026-11-08). It
## narrows for what stands at its height on the two sides: an ability tab is as wide as its name.
func _fit_tug() -> void:
	if _battle_tug == null or not _battle_tug.visible or _rosters.size() < 2 or _battle_bar.get_child_count() == 0:
		return
	var strip: Rect2 = _battle_bar.get_global_rect()
	var last := _battle_bar.get_child(_battle_bar.get_child_count() - 1) as UiShape
	var left: float = strip.position.x + TUG_INSET - BattleTug.CUT
	var right: float = strip.end.x - (last.cut if last != null else 0.0) - TUG_INSET
	var mid: float = (left + right) * 0.5
	var room: float = (right - left) * 0.5
	# What stands beside it, as far as the bar may go: the same gap on both sides, at the bar's slant.
	var free_left: float = -INF
	var free_right: float = INF
	for i: int in 2:
		for n: Node in _rosters[i].get_children():
			var row := n as Control
			if row == null or not row.visible:
				continue
			var r: Rect2 = row.get_global_rect()
			if r.position.y > TUG_Y + BattleTug.HEIGHT or r.end.y < TUG_Y:
				continue
			if i == 0:
				free_left = maxf(free_left, r.end.x + TUG_CLEAR - BattleTug.CUT * 0.5)
			else:
				free_right = minf(free_right, r.position.x - TUG_CLEAR + BattleTug.CUT * 0.5)
	if free_left > left and free_right < right:
		# Tight on both sides: halfway between them (Marko 2026-11-08).
		mid = (free_left + free_right) * 0.5
		room = (free_right - free_left) * 0.5
	elif free_left > left:
		room -= free_left - left
	elif free_right < right:
		room -= right - free_right
	_battle_tug.set_bar_width(2.0 * room)
	_battle_tug.position.x = mid - _battle_tug.bar_width * 0.5


## A card's name in the hand from one rebuild to the next: its seat, its id and which copy it is.
static func hand_keys(slot: int, hand: PackedStringArray) -> PackedStringArray:
	var seen: Dictionary[String, int] = {}
	var out := PackedStringArray()
	for cid: String in hand:
		var copy: int = seen.get(cid, 0)
		seen[cid] = copy + 1
		out.append("%d|%s#%d" % [slot, cid, copy])
	return out


## Of several copies the keys cannot tell which one went: the last key is the one that goes missing.
## So the copy played (`key`) changes places with the ones after it in `before`.
static func played_copy_last(before: Dictionary[String, Dictionary], key: String) -> void:
	var at: int = key.rfind("#")
	var stem: String = key.substr(0, at + 1)
	var copy: int = key.substr(at + 1).to_int()
	var played: Dictionary = before[key]
	while before.has(stem + str(copy + 1)):
		before[stem + str(copy)] = before[stem + str(copy + 1)]
		copy += 1
	before[stem + str(copy)] = played


## Where each card of the hand is now, by `hand_keys`: the next build carries on from there.
func _hand_snapshot() -> Dictionary[String, Dictionary]:
	var out: Dictionary[String, Dictionary] = {}
	if _hand_was_mulligan:
		return out
	for n: Node in _hand.get_children():
		var c := n as Control
		if c != null and c.has_meta("hand_key"):
			out[str(c.get_meta("hand_key"))] = {"index": JsonUtil.as_int(c.get_meta("index", -1), -1), "x": c.position.x, "turn": c.rotation_degrees, "mod": c.modulate,
				"stand": JsonUtil.as_float(c.get_meta("base_y")) - JsonUtil.as_float(c.get_meta("rest_y"))}
	return out


## A card that is still in the hand goes from where it was to its new place.
func _hand_slide(card: Control, was: Dictionary) -> void:
	var x: float = card.position.x
	var turn: float = card.rotation_degrees
	var mod: Color = card.modulate
	var from_mod: Color = was["mod"]
	var from_x: float = JsonUtil.as_float(was["x"])
	var from_turn: float = JsonUtil.as_float(was["turn"])
	if is_equal_approx(x, from_x) and is_equal_approx(turn, from_turn) and mod.is_equal_approx(from_mod):
		return
	card.position.x = from_x
	card.rotation_degrees = from_turn
	card.modulate = from_mod
	var t: Tween = card.create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(card, "position:x", x, HAND_SLIDE_TIME)
	t.tween_property(card, "rotation_degrees", turn, HAND_SLIDE_TIME)
	t.tween_property(card, "modulate", mod, HAND_SLIDE_TIME)


## A card that just left the hand rises and fades from where it stood.
func _hand_leave(slot: int, key: String, was: Dictionary) -> void:
	var cid: String = key.substr(key.find("|") + 1)
	cid = cid.substr(0, cid.rfind("#"))
	var ghost: Control = _hand_card(slot, cid, false, false)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.modulate = Color.WHITE
	ghost.position = _hand.position + Vector2(JsonUtil.as_float(was["x"]), 16.0 - JsonUtil.as_float(was["stand"]))
	ghost.rotation_degrees = JsonUtil.as_float(was["turn"])
	_hand_box.add_child(ghost)
	var t: Tween = ghost.create_tween().set_parallel(true)
	t.tween_property(ghost, "position:y", ghost.position.y - HAND_LEAVE_RISE, HAND_LEAVE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(ghost, "modulate:a", 0.0, HAND_LEAVE_TIME)
	t.chain().tween_callback(ghost.queue_free)


## At rest the cards you can play stand higher; with the hand up they are all level. A card that
## is lifted under the mouse is left alone: it moves on its own (`_lift`).
func _stand_cards(delta: float, up: bool) -> void:
	for n: Node in _hand.get_children():
		var card := n as Control
		if card == null or not card.has_meta("base_y") or card.z_index > 0:
			continue
		var lift: Tween = card.get_meta("lift") if card.has_meta("lift") else null
		if lift != null and lift.is_valid():
			continue
		var base: float = JsonUtil.as_float(card.get_meta("base_y"))
		var goal: float = base - (HAND_STAND if JsonUtil.as_bool(card.get_meta("stand", false)) and not up else 0.0)
		var y: float = move_toward(JsonUtil.as_float(card.get_meta("rest_y")), goal, delta * (HAND_STAND_SPEED_UP if up else HAND_STAND_SPEED))
		card.set_meta("rest_y", y)
		card.position.y = y


## The starting hand is up for a player here: the table is dark and out of reach behind it.
func board_blocked() -> bool:
	return _mulligan_dim != null and _mulligan_dim.visible


func _refresh_mulligan_dim() -> void:
	var slot: int = hand_slot()
	var on: bool = state.phase == GameState.PHASE_MULLIGAN and slot >= 0 and _needs_input(slot)
	if on == _mulligan_dim.visible:
		return
	_mulligan_dim.visible = on
	# MULLIGAN · YOUR MOVE stays in front of the dim, like YOUR STARTING HAND (Marko 2026-11-09).
	_ribbon.z_index = 1 if on else 0
	if on:
		_mulligan_dim.modulate.a = 0.0
		_mulligan_dim.create_tween().tween_property(_mulligan_dim, "modulate:a", 1.0, MULLIGAN_DIM_TIME * GameSettings.anim_scale())
		# Whatever was lit under the mouse goes out (deferred: this runs inside a refresh).
		hero_hovered.emit.call_deferred("")


func _refresh_hand() -> void:
	_refresh_mulligan_dim()
	# A new starting hand (mulligan taken) flies in again.
	if state.phase == GameState.PHASE_MULLIGAN and hand_slot() >= 0 and _hand_sig != ",".join(state.player(hand_slot()).hand):
		_hand_sig = ",".join(state.player(hand_slot()).hand)
		_hand_dealt = false
	# A refresh while the starting hand is still flying in would rebuild it in place and cut
	# the deal short (playtest 2026-10-30: the deal was gone); the same cards stay as they are.
	if state.phase == GameState.PHASE_MULLIGAN and _hand_dealt and _hand.get_child_count() > 0 \
			and Time.get_ticks_msec() < _mulligan_ready_at:
		return
	var before: Dictionary[String, Dictionary] = _hand_snapshot()
	_clear(_hand)
	var mulligan: bool = state.phase == GameState.PHASE_MULLIGAN
	_hand_was_mulligan = mulligan
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
	var step: float = minf(176.0 if mulligan else 104.0, (HAND_WIDTH - 40.0) / maxf(float(n), 1.0))
	var keys: PackedStringArray = hand_keys(slot, p.hand)
	if hand_leaving >= 0 and n < before.size():
		for key: String in before:
			if JsonUtil.as_int(before[key].get("index", -1), -1) == hand_leaving:
				played_copy_last(before, key)
				break
		hand_leaving = -1
	for i: int in n:
		var cid: String = p.hand[i]
		var check: Dictionary = _play_check(slot, cid) if my_round else {}
		var playable: bool = my_round and check.get("ok", false) == true
		var card: Control = _hand_card(slot, cid, playable, my_round, str(check.get("why", "")),
			JsonUtil.as_strings(check.get("heroes", [])), i)
		var t: float = i - (n - 1) * 0.5
		card.position = Vector2(_hand.size.x * 0.5 + t * step - CARD_SIZE.x * 0.5, 16.0 + (0.0 if mulligan else t * t * 2.0))
		card.rotation_degrees = 0.0 if mulligan else t * 3.0
		var was: Dictionary = before.get(keys[i], {})
		card.set_meta("hand_key", keys[i])
		card.set_meta("stand", playable and not mulligan)
		card.set_meta("base_y", card.position.y)
		# Carries on from the height it had: a rebuild must not make the hand jump.
		if not was.is_empty():
			card.position.y -= JsonUtil.as_float(was["stand"])
		if mulligan:
			card.scale = Vector2.ONE * 1.25
		card.set_meta("rest_y", card.position.y)
		_hand.add_child(card)
		if not was.is_empty():
			_hand_slide(card, was)
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
		if cid == target_cid and slot == target_slot and (target_index < 0 or target_index == i):
			_lift(card, true, true)
	if mulligan and not _hand_dealt:
		_mulligan_ready_at = Time.get_ticks_msec() + int((0.12 * maxf(float(n) - 1.0, 0.0) + 0.45 + 0.15) * 1000.0)
	if mulligan:
		_hand_dealt = true
	else:
		_hand_dealt = false
		var prefix: String = "%d|" % slot
		var gone: Array[String] = []
		for key: String in before:
			if key.begins_with(prefix) and not keys.has(key):
				gone.append(key)
		if gone.size() <= HAND_LEAVE_MAX:
			for key: String in gone:
				_hand_leave(slot, key, before[key])


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
func _card_chosen(slot: int, cid: String, heroes: PackedStringArray, index: int = -1) -> void:
	if heroes.size() <= 1:
		cancel_targeting()
		hand_leaving = index
		card_pressed.emit(slot, cid, heroes[0] if heroes.size() == 1 else "")
		return
	if cid == target_cid and index == target_index:
		cancel_targeting()
		return
	target_slot = slot
	target_cid = cid
	target_index = index
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
	target_index = -1
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
	var index: int = target_index
	cancel_targeting()
	hand_leaving = index
	card_pressed.emit(slot, cid, hero_id)
	return true


## The dashed line from the card being targeted to the mouse.
func _draw_aim_line() -> void:
	if target_cid.is_empty():
		return
	var from := Vector2.ZERO
	var found: bool = false
	for c: Node in _hand.get_children():
		if c is Control and str(c.get_meta("cid", "")) == target_cid \
				and (target_index < 0 or JsonUtil.as_int(c.get_meta("index", -1)) == target_index):
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
		heroes: PackedStringArray = PackedStringArray(), index: int = -1) -> Control:
	var c: CardDef = engine.catalog.get_card(cid)
	# A lost battle's hit: every card may take 1 DMG (up to the spare part); picked ones are marked.
	var hurting: bool = damage_picking(slot)
	var hurt_it: bool = hurting and damage_cards.has(index)
	var picking: bool = hurting or (not choice_cards.is_empty() and choice_slot == slot)
	var picks_it: bool = hurt_it or (not hurting and picking and choice_cards.has(cid))
	var root := Control.new()
	root.custom_minimum_size = CARD_SIZE
	root.size = CARD_SIZE
	root.pivot_offset = Vector2(CARD_SIZE.x * 0.5, CARD_SIZE.y)
	root.set_meta("cid", cid)
	root.set_meta("index", index)
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
	# A landscape card (an evolution) is turned upright to fill the slot like every other card
	# (playtest 2026-10-30: it lay across the top, smaller); the big card shows it as printed.
	var turned: bool = tex != null and tex.get_width() > tex.get_height()
	var pic: Rect2 = Rect2(Vector2.ZERO, CARD_SIZE) if turned else _card_rect(tex)
	root.set_meta("pic", pic)
	if tex != null:
		var img := TextureRect.new()
		img.texture = tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_SCALE
		img.position = pic.position
		img.size = pic.size
		if turned:
			# Turned a quarter clockwise about its top left corner, then moved back into the slot.
			img.size = Vector2(CARD_SIZE.y, CARD_SIZE.x)
			img.rotation = PI * 0.5
			img.position = Vector2(CARD_SIZE.x, 0)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img.material = round_corners(img.size.x / img.size.y)
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
		# The price now (a discount, or a colorless card's bonus for the hero it would go to): green when
		# it is under the printed cost, red when the player cannot pay it.
		var price: int = engine.card_cost(state, state.player(slot), c) if state != null else c.cost
		var poor: bool = my_round and price > state.player(slot).energy
		var cheaper: bool = price < c.cost
		var cost: UiShape = UiShape.make(UiShape.Kind.DIAMOND, Palette.ACCENT if poor else (Palette.HEAL if cheaper else Palette.GOLD), Vector2(36, 36),
			str(price), 21, Palette.FG if poor else Color.BLACK)
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
		if hurting:
			# Picked cards and the ones that may still be picked stay in colour.
			root.modulate = Color.WHITE if hurt_it or damage_cards.size() < damage_spare() else Color(0.35, 0.35, 0.35)
		elif picking:
			root.modulate = Color.WHITE if picks_it else Color(0.35, 0.35, 0.35)
		elif my_round and not playable:
			# Why it is grey shows above the card on hover; the text block keeps the card's text.
			root.modulate = Color(0.45, 0.45, 0.45)
		elif not my_round and state.phase != GameState.PHASE_MULLIGAN:
			# Nothing can be played now (Start, the other side's turn): grey, so no card looks
			# playable (Marko 2026-11-01: in Start every card was in colour).
			root.modulate = Color(0.5, 0.5, 0.5)
	if picks_it:
		var ring := ReferenceRect.new()
		ring.border_color = Palette.GOLD
		ring.border_width = 4.0
		ring.editor_only = false
		ring.position = pic.position - Vector2(2, 2)
		ring.size = pic.size + Vector2(4, 4)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.add_child(ring)
		# The ring runs round the cost diamond (Marko 2026-11-01): a gold diamond a little bigger
		# behind it, the cost on top.
		if face.has_node("Cost"):
			var cost_node: UiShape = face.get_node("Cost")
			var halo: UiShape = UiShape.make(UiShape.Kind.DIAMOND, Palette.GOLD, Vector2(48, 48), "", 1, Palette.GOLD)
			halo.position = cost_node.position - Vector2(6, 6)
			halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
			face.add_child(halo)
			face.move_child(cost_node, -1)
		# Above the card: the bottom of the hand is off the screen.
		var chip: UiShape = UiShape.chip("1 DMG" if hurt_it else "PICK", Palette.ACCENT if hurt_it else Palette.GOLD, Palette.FG if hurt_it else Color.BLACK, 14, 24.0, 8.0)
		chip.position = Vector2(CARD_SIZE.x * 0.5 - chip.custom_minimum_size.x * 0.5, pic.position.y - 30.0)
		face.add_child(chip)
	root.mouse_entered.connect(func() -> void:
		_hovered(cid)
		_lift(root, true, playable or picks_it))
	root.mouse_exited.connect(func() -> void:
		if _hover_cid == cid:
			_hover_cid = ""
		_lift(root, false, playable or picks_it))
	root.gui_input.connect(func(e: InputEvent) -> void:
		if _card_click(e, cid):
			return
		# A lost battle's hit: a click puts 1 DMG on this card, another takes it off.
		if hurting and e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			toggle_damage_card(index)
			return
		# A card effect asks for a card from this hand: a lit one answers it.
		if picks_it and e is InputEventMouseButton and (e as InputEventMouseButton).pressed \
				and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			choose_pressed.emit(slot, cid)
			return
		if playable and e is InputEventMouseButton:
			var mb := e as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				# A click (let go where pressed) plays as before; a drag carries it to a hero (_input).
				_drag = {"slot": slot, "cid": cid, "index": index, "heroes": heroes, "from": get_global_mouse_position()}
				_dragging = false)
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
				accept_event()
				_show_big(""))
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
## The pause menu opened or closed: a card held in the hand is put back, a big card goes away.
func set_menu_open(on: bool) -> void:
	menu_open = on
	if not on:
		return
	if not _drag.is_empty():
		_drag = {}
		_dragging = false
		cancel_targeting()
	_show_big("")


func _input(event: InputEvent) -> void:
	if menu_open:
		return
	if not _drag.is_empty() and _drag_input(event):
		return
	# A click outside the energy window closes it: the split goes on on the table (item 20).
	if _dialog.visible and not energy_on_table and not _energy_decision().is_empty() and event is InputEventMouseButton:
		var emb := event as InputEventMouseButton
		if emb.pressed and emb.button_index == MOUSE_BUTTON_LEFT and not _dialog.get_global_rect().has_point(emb.position) and not _menu_button.get_global_rect().has_point(emb.position):
			energy_on_table = true
			refresh()
			get_viewport().set_input_as_handled()
			return
	var go_on: bool = (event is InputEventMouseButton and (event as InputEventMouseButton).pressed
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
			or (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo
			and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER])
	if _banner_busy and go_on:
		skip_banner()
	elif end_hold and go_on:
		end_skip = true
	elif go_on and _over != null and _over.visible:
		# The end screen's moment, at once.
		finish_end_anim()
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


## A card held from the hand: past DRAG_START pixels it is dragged, the heroes it can go on
## light up (the targeting of a click); let go on one of them plays it there, elsewhere puts it
## back. Let go without moving is a click. True when the event was used.
func _drag_input(event: InputEvent) -> bool:
	var heroes: PackedStringArray = _drag["heroes"]
	if event is InputEventMouseMotion and not _dragging:
		var from: Vector2 = _drag["from"]
		if get_global_mouse_position().distance_to(from) < DRAG_START:
			return false
		_dragging = true
		if not heroes.is_empty():
			target_slot = JsonUtil.as_int(_drag["slot"])
			target_cid = str(_drag["cid"])
			target_index = JsonUtil.as_int(_drag.get("index", -1), -1)
			target_heroes = heroes
			_target_why = _last_why_by.get(target_cid, {})
			targeting_changed.emit()
			refresh()
		return false
	if not (event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and not (event as InputEventMouseButton).pressed):
		return false
	var d: Dictionary = _drag
	_drag = {}
	if not _dragging:
		_card_chosen(JsonUtil.as_int(d["slot"]), str(d["cid"]), heroes, JsonUtil.as_int(d.get("index", -1), -1))
		return false
	_dragging = false
	get_viewport().set_input_as_handled()
	if heroes.is_empty():
		# Nothing to aim at (an assist): let go above the hand plays it.
		if get_global_mouse_position().y < size.y - HAND_HEIGHT:
			hand_leaving = JsonUtil.as_int(d.get("index", -1), -1)
			card_pressed.emit(JsonUtil.as_int(d["slot"]), str(d["cid"]), "")
		return true
	if not play_target(hover_hero):
		cancel_targeting()
	return true


## The mouse is on card `cid`; with the zoom key held, the big card follows it.
func _hovered(cid: String) -> void:
	_hover_cid = cid
	if GameSettings.zoom_mode() == "hold" and Input.is_key_pressed(GameSettings.key("card_zoom")):
		_show_big(cid)


## Right click shows the card big; any other click puts it away.
func _card_click(e: InputEvent, cid: String) -> bool:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		if (e as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
			accept_event()
			_toggle_big(cid)
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
	_clear_energy_rows()
	if _energy_decision().is_empty():
		energy_on_table = false
	# The card bottom right opens the energy window again while the split is on the table.
	_prompt_card.mouse_filter = Control.MOUSE_FILTER_STOP if energy_on_table else Control.MOUSE_FILTER_IGNORE
	_prompt_card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if energy_on_table else Control.CURSOR_ARROW
	_damage_dim.visible = false
	_dialog_sb.border_color = Palette.GOLD
	_set_dialog_pad(28, 22)
	_dialog_center.offset_bottom = 0.0
	# Not over a band: the choice comes once the bands are through (`_next_banner` asks again).
	if state.pending.is_empty() or _banner_busy:
		return
	var d: Dictionary = state.pending[0]
	var who: int = JsonUtil.as_int(d.get("player", -1), -1)
	if not local_slots.has(who):
		return
	if str(d.get("type", "")) == FxRuntime.DECISION_CHOOSE:
		_choose_dialog(d, who)
		return
	if str(d.get("type", "")) == RulesEngine.DECISION_STAGE_ENERGY:
		_energy_dialog(d, who)
		return
	if str(d.get("type", "")) == RulesEngine.DECISION_COMBO:
		_combo_dialog(d, who)
		return
	if str(d.get("type", "")) != RulesEngine.DECISION_DAMAGE:
		return
	_damage_dialog(d, who)


## The small window above the hand (Marko 2026-11-08, from the mockups): the board dims under the
## hand, the line on top says what kind it is, red for a hit, straw for a choice.
func _small_dialog(top: Color) -> void:
	_dialog.visible = true
	_damage_dim.visible = true
	_dialog_sb.border_color = top
	_set_dialog_pad(16, 16)
	# Centred on the room above the hand.
	_dialog_center.offset_bottom = -110.0


func _set_dialog_pad(x: float, y: float) -> void:
	_dialog_sb.content_margin_left = x
	_dialog_sb.content_margin_right = x
	_dialog_sb.content_margin_top = y
	_dialog_sb.content_margin_bottom = y


## A lost battle's hit (GDD 10, 2026-11-02; Marko 2026-11-08, from the mockups): at least half of it
## (rounded up) lands on a hero, the rest the loser may put on cards from the hand, 1 DMG each, picked
## by clicking them in the hand. The heroes in reach stand on the left, each with its life right under
## its picture; one is picked here or on the table, CONFIRM sends it. A ring-out's cost looks the same.
func _damage_dialog(d: Dictionary, who: int) -> void:
	_small_dialog(Palette.ACCENT)
	var amount: int = JsonUtil.as_int(d.get("amount", 0))
	var min_hero: int = JsonUtil.as_int(d.get("min_hero", RulesEngine.hero_share(amount)))
	var winner: HeroState = state.hero(str(d.get("winner", "")))
	var targets: PackedStringArray = JsonUtil.as_strings(d.get("targets", []))
	var p: PlayerState = state.player(who)
	var on_hero: int = amount - damage_cards.size()
	var ring: bool = JsonUtil.as_bool(d.get("ring_out", false))
	var target: String = damage_target if not damage_target.is_empty() else (targets[0] if targets.size() == 1 else "")
	var hero: HeroState = state.hero(target)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_dialog_box.add_child(row)
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 6)
	row.add_child(tiles)
	for id: String in targets:
		var h: HeroState = state.hero(id)
		if h != null:
			tiles.add_child(_damage_hero(h, targets.size(), id == target, on_hero))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size.x = 300
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var kicker: String = "RING-OUT" if ring else _battle_lost_line()
	if local_slots.size() > 1:
		kicker += "  ·  %s" % player_name(who).to_upper()
	col.add_child(UiTheme.label(kicker, 13, Palette.GOLD))
	if ring:
		var fallen: HeroState = state.hero(targets[0]) if not targets.is_empty() else null
		col.add_child(UiTheme.label("%s TAKES %d DMG" % [hero_name(fallen).to_upper() if fallen != null else "?", amount], 28))
	else:
		col.add_child(UiTheme.label("%d DMG FROM %s" % [amount, hero_name(winner).to_upper() if winner != null else "?"], 28))
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 3)
	col.add_child(split)
	for i: int in amount:
		var pip: UiShape = UiShape.make(UiShape.Kind.SLANT, Palette.ACCENT if i < on_hero else Palette.GOLD, Vector2(30, 14))
		pip.cut = 6.0
		split.add_child(pip)
	if hero == null:
		col.add_child(_damage_note("Click who takes it, here or on the table.", 16, Palette.FG))
	col.add_child(_damage_note(_damage_rule(amount, min_hero, ring, p), 13, Palette.MUTED))
	var confirm: Button = _option_button("CONFIRM" if hero != null else "PICK A HERO", func() -> void:
		var cards: Array = []
		for i: int in damage_cards:
			if i >= 0 and i < p.hand.size():
				cards.append(p.hand[i])
		damage_pressed.emit(who, target, cards))
	_dialog_box.remove_child(confirm)
	col.add_child(confirm)
	confirm.theme_type_variation = &"Primary"
	confirm.alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm.custom_minimum_size = Vector2(0, 48)
	confirm.add_theme_font_size_override("font_size", 24)
	confirm.disabled = hero == null


## "BATTLE LOST", and which hit this is when more than one winner strikes in the battle.
func _battle_lost_line() -> String:
	var left: int = 0
	for q: Dictionary in state.pending:
		if str(q.get("type", "")) == RulesEngine.DECISION_DAMAGE and not JsonUtil.as_bool(q.get("ring_out", false)):
			left += 1
	var key: String = "%d|%d" % [state.turn, state.battle_index]
	# The first hit shown sets the count; going back in a replay can only show more left.
	if key != _hit_key or left > _hit_total:
		_hit_key = key
		_hit_total = left
	return "BATTLE LOST" if _hit_total <= 1 else "BATTLE LOST  ·  HIT %d OF %d" % [_hit_total - left + 1, _hit_total]


func _damage_rule(amount: int, min_hero: int, ring: bool, p: PlayerState) -> String:
	var spare: int = damage_spare()
	if ring:
		return "Or discard a card from your hand instead: click it." if spare > 0 else "No card in your hand to discard instead."
	if min_hero >= amount and not p.hand.is_empty():
		return "All %d land on the hero: this hit cannot go on hand cards." % amount
	if spare <= 0:
		return "All %d land on the hero: no cards in your hand." % amount
	return "Up to %d can go on hand cards: click them." % spare


func _damage_note(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## A hero that can take the hit: its picture, and right under it its life, as wide as the picture's
## slanted bottom edge. Picked, the life shows what falls.
func _damage_hero(h: HeroState, among: int, picked: bool, on_hero: int) -> VBoxContainer:
	var card: CardDef = engine.stat_card(h)
	var cid: String = card.id if card != null else h.card_id
	var tile := Vector2(DAMAGE_HERO_W if among == 1 else DAMAGE_HERO_W_MANY, DAMAGE_HERO_H)
	var hit: int = mini(on_hero, h.hp) if picked else 0
	var max_hp: int = engine.max_hp(state, h)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.custom_minimum_size.x = tile.x
	var s := HeroSlice.new()
	s.custom_minimum_size = tile
	s.art_w = PlayerCard.ALL_PICTURE
	s.set_mirrored(false)
	s.art = db.thumb(cid) if db != null else null
	s.art_region = HeroSlice.region_for(s.art)
	s.art_fallback = Palette.hero(card.color if card != null else "").darkened(0.3)
	s.color_edge = Palette.hero(card.color if card != null else "")
	if picked:
		s.outline = Palette.GOLD
	elif among > 1 and not damage_target.is_empty():
		s.art_tint = Color(0.55, 0.55, 0.55)
	# Off the slant and the colour edge, so a long name breaks in two instead of running over.
	s.content.add_theme_constant_override("margin_left", 10)
	s.content.add_theme_constant_override("margin_right", int(HeroSlice.CUT + HeroSlice.EDGE_W) + 5)
	col.add_child(s)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_END
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.content.add_child(names)
	var name_l: Label = UiTheme.label(hero_name(h), 16)
	name_l.add_theme_color_override("font_outline_color", Color.BLACK)
	name_l.add_theme_constant_override("outline_size", 6)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD
	names.add_child(name_l)
	if among > 1:
		s.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		s.mouse_entered.connect(func() -> void:
			s.outline = Palette.GOLD
			s.queue_redraw())
		s.mouse_exited.connect(func() -> void:
			s.outline = Palette.GOLD if picked else Color(0, 0, 0, 0)
			s.queue_redraw())
	s.gui_input.connect(func(e: InputEvent) -> void:
		if _card_click(e, cid) or among <= 1:
			return
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			pick_damage_hero(h.id))
	var under := VBoxContainer.new()
	under.add_theme_constant_override("separation", 3)
	under.custom_minimum_size.x = tile.x - HeroSlice.CUT
	under.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(under)
	var segs := UiSegments.new()
	segs.max_value = max_hp
	segs.value = h.hp
	segs.ghost = hit
	segs.color = Palette.hp(float(h.hp) / maxf(float(max_hp), 1.0))
	segs.lean = 1.5
	segs.custom_minimum_size = Vector2(0, 10)
	segs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	under.add_child(segs)
	var numbers: Label = UiTheme.label("%d  →  %d" % [h.hp, h.hp - hit] if hit > 0 else "%d" % h.hp, 26, Palette.ACCENT if hit > 0 else Palette.MUTED)
	numbers.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	under.add_child(numbers)
	return col


## The End phase's energy (Marko 2026-11-02; the window and the table as chosen 2026-11-10, item 20, H2):
## the energy left goes into the stages the player's heroes stand on. With more than one, the player
## shares it out, all of it, with − and + per stage (+ with nothing left takes one from another stage),
## and CONFIRMs: in the window, or, after a click outside it, on the table itself (energy_on_table: the
## steps stand by each stage, CONFIRM is bottom right, and a click on the card above it opens the window
## again). The split starts by filling the stage with the most energy in it up to the goal, then the next.
func _energy_prepare(d: Dictionary, who: int) -> void:
	var energy: int = JsonUtil.as_int(d.get("energy", 0))
	var goal: int = JsonUtil.as_int(d.get("goal", state.settings.stage_goal))
	var ids: PackedStringArray = JsonUtil.as_strings(d.get("stages", []))
	var key: String = "%d|%d|%d|%s" % [who, state.turn, energy, ",".join(ids)]
	if key == _energy_key:
		return
	_energy_key = key
	energy_on_table = false
	energy_split = {}
	var order: Array = Array(ids)
	order.sort_custom(func(a: String, b: String) -> bool: return state.stage(a).progress_of(who) > state.stage(b).progress_of(who))
	var rest: int = energy
	for id: String in order:
		var n: int = mini(rest, maxi(goal - state.stage(id).progress_of(who), 0))
		if n > 0:
			energy_split[id] = n
			rest -= n
	if rest > 0 and not order.is_empty():
		energy_split[order[0]] = JsonUtil.as_int(energy_split.get(order[0], 0)) + rest


## The energy decision a player at this screen is to make now, or nothing (bands first, as for any choice).
func _energy_decision() -> Dictionary:
	if state == null or state.pending.is_empty() or _banner_busy or replay:
		return {}
	var d: Dictionary = state.pending[0]
	if str(d.get("type", "")) != RulesEngine.DECISION_STAGE_ENERGY or not local_slots.has(JsonUtil.as_int(d.get("player", -1), -1)):
		return {}
	return d


## How much of the decision's energy is not shared out yet.
func _energy_left(d: Dictionary) -> int:
	var left: int = JsonUtil.as_int(d.get("energy", 0))
	for id: String in JsonUtil.as_strings(d.get("stages", [])):
		left -= JsonUtil.as_int(energy_split.get(id, 0))
	return left


func _energy_confirm(d: Dictionary, who: int) -> void:
	var split: Dictionary = {}
	for id: String in JsonUtil.as_strings(d.get("stages", [])):
		if JsonUtil.as_int(energy_split.get(id, 0)) > 0:
			split[id] = JsonUtil.as_int(energy_split[id])
	energy_pressed.emit(who, split)


## What the table shows of the split while it is being made (the match draws it on the stages' edges):
## {who, split: stage id -> energy} or nothing.
func energy_preview() -> Dictionary:
	var d: Dictionary = _energy_decision()
	if d.is_empty():
		return {}
	return {"who": JsonUtil.as_int(d.get("player", 0)), "split": energy_split, "stages": JsonUtil.as_strings(d.get("stages", []))}


func _energy_dialog(d: Dictionary, who: int) -> void:
	_energy_prepare(d, who)
	if energy_on_table:
		_energy_table(d, who)
		return
	_dialog.visible = true
	var energy: int = JsonUtil.as_int(d.get("energy", 0))
	var goal: int = JsonUtil.as_int(d.get("goal", state.settings.stage_goal))
	var ids: PackedStringArray = JsonUtil.as_strings(d.get("stages", []))
	var left: int = _energy_left(d)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size.x = 700
	_dialog_box.add_child(col)
	col.add_child(UiTheme.label("END PHASE" + ("  ·  %s" % player_name(who).to_upper() if local_slots.size() > 1 else ""), 13, Palette.GOLD))
	var title: Label = UiTheme.label("%d ENERGY INTO YOUR STAGES" % energy, 34)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	for id: String in ids:
		var st: StageState = state.stage(id)
		if st != null:
			col.add_child(_energy_row(st, who, goal, energy, left, ids))
	var low := HBoxContainer.new()
	low.add_theme_constant_override("separation", 12)
	col.add_child(low)
	var note: Label = _damage_note("All of it goes in. %d in one stage claims it. Click outside to share it out on the table." % goal, 13, Palette.MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	low.add_child(note)
	var confirm: Button = _option_button("CONFIRM" if left == 0 else "CONFIRM   %d LEFT" % left, func() -> void: _energy_confirm(d, who))
	_dialog_box.remove_child(confirm)
	low.add_child(confirm)
	confirm.theme_type_variation = &"Primary"
	confirm.alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm.custom_minimum_size = Vector2(190, 48)
	confirm.add_theme_font_size_override("font_size", 24)
	confirm.disabled = left != 0


## What `n` energy of `who` would do in a stage: {have, theirs, fill, take, after, over, other}. The shared
## ring fills the empty places, then takes the other side's, and what is left over is lost; with a ring
## of one's own it fills up to the goal.
func energy_effect(st: StageState, who: int, n: int, goal: int) -> Dictionary:
	var have: int = st.progress_of(who)
	var theirs: int = 0
	var other: String = ""
	if state.settings.shared_ring():
		for p: PlayerState in state.players:
			if state.team_of(p.slot) != state.team_of(who):
				theirs += st.progress_of(p.slot)
				other = player_name(p.slot)
	var out: Dictionary = split_effect(have, theirs, n, goal)
	out["other"] = other
	return out


## `n` energy into a ring of `goal` places where the player has `have` and the other side `theirs`: it
## fills the empty places first, then takes the other side's, and the rest is lost.
static func split_effect(have: int, theirs: int, n: int, goal: int) -> Dictionary:
	var fill: int = mini(n, maxi(goal - have - theirs, 0))
	var take: int = mini(n - fill, theirs)
	return {"have": have, "theirs": theirs, "fill": fill, "take": take, "after": have + fill + take, "over": n - fill - take}


## One stage of the energy window: its picture, the ring with what would go in, the numbers, the heroes of
## the player standing on it, and − and +.
func _energy_row(st: StageState, who: int, goal: int, energy: int, left: int, ids: PackedStringArray) -> HBoxContainer:
	var id: String = st.id
	var n: int = JsonUtil.as_int(energy_split.get(id, 0))
	var fx: Dictionary = energy_effect(st, who, n, goal)
	var have: int = fx["have"]
	var theirs: int = fx["theirs"]
	var take: int = fx["take"]
	var after: int = fx["after"]
	var over: int = fx["over"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var pic := HeroSlice.new()
	pic.custom_minimum_size = Vector2(210, 92)
	pic.art_w = PlayerCard.ALL_PICTURE
	pic.set_mirrored(false)
	pic.art = db.thumb(st.card_id) if db != null else null
	pic.art_region = Rect2(0.115, 0.125, 0.77, 0.37)
	pic.color_edge = Palette.team(state.team_of(who))
	pic.content.add_theme_constant_override("margin_left", 12)
	pic.content.add_theme_constant_override("margin_right", int(HeroSlice.CUT + HeroSlice.EDGE_W) + 5)
	pic.gui_input.connect(func(e: InputEvent) -> void: _card_click(e, st.card_id))
	row.add_child(pic)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_END
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.content.add_child(names)
	var name_l: Label = UiTheme.label(_card_name(st.card_id), 19)
	name_l.add_theme_color_override("font_outline_color", Color.BLACK)
	name_l.add_theme_constant_override("outline_size", 6)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD
	names.add_child(name_l)
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 5)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mid)
	if state.settings.shared_ring():
		mid.add_child(_ring_bar(have, theirs, JsonUtil.as_int(fx["fill"]), take, goal, state.team_of(who)))
	else:
		var bar := UiSegments.new()
		bar.max_value = goal
		bar.value = after
		bar.ghost = after - have
		bar.color = Palette.team(state.team_of(who))
		bar.lean = 1.5
		bar.custom_minimum_size = Vector2(0, 22)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mid.add_child(bar)
	var words := HBoxContainer.new()
	words.add_theme_constant_override("separation", 10)
	mid.add_child(words)
	var line: String = "%d  →  %d  /  %d" % [have, after, goal]
	if after >= goal:
		line += "   CLAIMS IT"
	if over > 0:
		line += "  (%d LOST)" % over
	var mine_l: Label = UiTheme.label(line, 24, Palette.GOLD if n > 0 else Palette.MUTED)
	mine_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(mine_l)
	if theirs > 0:
		var red: Color = Palette.team(1 - clampi(state.team_of(who), 0, 1)).lightened(0.35)
		var other: String = str(fx["other"]).to_upper()
		var their_l: Label = UiTheme.label(("%s  %d  →  %d" % [other, theirs, theirs - take]) if take > 0 else "%s  %d" % [other, theirs], 16, red)
		their_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		words.add_child(their_l)
	# The player's heroes standing on it, with their names; three and more are faces only (name on hover).
	var who_row := HBoxContainer.new()
	who_row.add_theme_constant_override("separation", 8)
	mid.add_child(who_row)
	var faces := HBoxContainer.new()
	faces.add_theme_constant_override("separation", 2)
	who_row.add_child(faces)
	var hero_names := PackedStringArray()
	for x: HeroState in state.heroes_on_stage(st):
		if x.owner != who:
			continue
		var f: HeroSlice = _energy_face(x)
		faces.add_child(f)
		hero_names.append(hero_name(x).get_slice(",", 0).to_upper())
	if hero_names.size() <= 2:
		var names_l: Label = UiTheme.label(" + ".join(hero_names), 14, Palette.MUTED)
		names_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		who_row.add_child(names_l)
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 6)
	steps.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(steps)
	var minus: Button = _step_button("−", func() -> void: _energy_step(id, -1, ids, who))
	minus.disabled = n <= 0
	steps.add_child(minus)
	var num: Label = UiTheme.label("+%d" % n, 28, Palette.GOLD if n > 0 else Palette.MUTED)
	num.custom_minimum_size.x = 48
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	steps.add_child(num)
	var plus: Button = _step_button("+", func() -> void: _energy_step(id, 1, ids, who))
	plus.disabled = left <= 0 and n >= energy
	steps.add_child(plus)
	return row


## A hero's face, small and slanted, for the energy window.
func _energy_face(hero: HeroState) -> HeroSlice:
	var f := HeroSlice.new()
	var tex: Texture2D = db.thumb(engine.stat_card(hero).id) if db != null else null
	f.art = tex
	f.art_region = HeroSlice.region_for(tex)
	f.art_w = 66.0 - HeroSlice.CUT
	f.bg = Color(0, 0, 0, 0)
	f.outline = Color.BLACK
	f.outline_width = 2.0
	f.custom_minimum_size = Vector2(66, 38)
	f.tooltip_text = hero_name(hero)
	f.mouse_filter = Control.MOUSE_FILTER_PASS
	return f


## The shared ring as a row of places: the player's from the left, the other side's from the right, the
## places that would be filled lighter, and those taken from the other side lighter with their rim.
func _ring_bar(mine: int, theirs: int, fill: int, take: int, goal: int, team: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 22)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var own: Color = Palette.team(clampi(team, 0, 1))
	var other: Color = Palette.team(1 - clampi(team, 0, 1))
	c.draw.connect(func() -> void:
		var lean: float = 5.0
		var gap: float = 2.0
		var sw: float = (c.size.x - gap * (goal - 1) - lean) / maxf(goal, 1)
		var hh: float = c.size.y
		for i: int in goal:
			var x: float = i * (sw + gap)
			var col: Color = Color(0.2, 0.2, 0.2)
			var edge := Color(0, 0, 0, 0)
			if i < mine:
				col = own
			elif i < mine + fill:
				col = own.lightened(0.5)
			elif i >= goal - theirs and i < goal - theirs + take:
				col = own.lightened(0.5)
				edge = other
			elif i >= goal - theirs:
				col = other
			var poly := PackedVector2Array([Vector2(x + lean, 0), Vector2(x + lean + sw, 0), Vector2(x + sw, hh), Vector2(x, hh)])
			c.draw_colored_polygon(poly, col)
			if edge.a > 0.0:
				poly.append(poly[0])
				c.draw_polyline(poly, edge, 2.0, true))
	return c


## The split on the table (the window closed by a click outside it): − n + by each stage, placed where the
## match says the stage is on the screen (stage_anchor), every frame.
func _energy_table(d: Dictionary, who: int) -> void:
	var ids: PackedStringArray = JsonUtil.as_strings(d.get("stages", []))
	var energy: int = JsonUtil.as_int(d.get("energy", 0))
	var left: int = _energy_left(d)
	for id: String in ids:
		var n: int = JsonUtil.as_int(energy_split.get(id, 0))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var minus: Button = _step_button("−", func() -> void: _energy_step(id, -1, ids, who))
		minus.custom_minimum_size = Vector2(34, 34)
		minus.disabled = n <= 0
		row.add_child(minus)
		row.add_child(UiShape.chip("+%d" % n, Palette.GOLD if n > 0 else Palette.SURFACE_2, Color.BLACK if n > 0 else Palette.MUTED, 20, 34.0, 12.0))
		var plus: Button = _step_button("+", func() -> void: _energy_step(id, 1, ids, who))
		plus.custom_minimum_size = Vector2(34, 34)
		plus.disabled = left <= 0 and n >= energy
		row.add_child(plus)
		add_child(row)
		# Under the bands, like the other things that stand on the table.
		move_child(row, _banner_layer.get_index())
		row.reset_size()
		_energy_rows[id] = row
	_place_energy_rows()


func _place_energy_rows() -> void:
	for id: String in _energy_rows:
		var row: Control = _energy_rows[id]
		if not is_instance_valid(row):
			continue
		var at := Vector2(-4000, -4000)
		if stage_anchor.is_valid():
			at = stage_anchor.call(id)
		row.position = at - Vector2(row.size.x * 0.5, 0)


func _clear_energy_rows() -> void:
	for id: String in _energy_rows:
		if is_instance_valid(_energy_rows[id]):
			_energy_rows[id].queue_free()
	_energy_rows.clear()


func _step_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = Vector2(46, 46)
	b.pressed.connect(cb)
	return b


## One energy more (or less) for stage `id`; a plus with nothing left takes it from the stage
## that has the most.
func _energy_step(id: String, by: int, ids: PackedStringArray, who: int) -> void:
	var d: Dictionary = state.pending[0] if not state.pending.is_empty() else {}
	var energy: int = JsonUtil.as_int(d.get("energy", 0))
	var n: int = JsonUtil.as_int(energy_split.get(id, 0))
	if by < 0:
		energy_split[id] = maxi(n - 1, 0)
	else:
		var used: int = 0
		for k: String in ids:
			used += JsonUtil.as_int(energy_split.get(k, 0))
		if used >= energy:
			var from: String = ""
			for k: String in ids:
				if k != id and JsonUtil.as_int(energy_split.get(k, 0)) > JsonUtil.as_int(energy_split.get(from, 0)):
					from = k
			if from.is_empty():
				return
			energy_split[from] = JsonUtil.as_int(energy_split[from]) - 1
		energy_split[id] = n + 1
	refresh()


## Whether `slot` is picking hand cards for a lost battle's hit now.
func damage_picking(slot: int) -> bool:
	return slot >= 0 and slot == choice_slot and not damage_heroes.is_empty() and damage_spare() > 0


## How many DMG of the pending hit may go on hand cards (the part above the hero's share).
func damage_spare() -> int:
	if state == null or state.pending.is_empty():
		return 0
	var d: Dictionary = state.pending[0]
	if str(d.get("type", "")) != RulesEngine.DECISION_DAMAGE:
		return 0
	var amount: int = JsonUtil.as_int(d.get("amount", 0))
	var p: PlayerState = state.player(JsonUtil.as_int(d.get("player", -1), -1))
	if p == null:
		return 0
	return mini(amount - JsonUtil.as_int(d.get("min_hero", RulesEngine.hero_share(amount))), p.hand.size())


## The hero that takes the pending hit was picked (dialog button or a lit ball on the table).
func pick_damage_hero(id: String) -> void:
	var d: Dictionary = state.pending[0] if state != null and not state.pending.is_empty() else {}
	if str(d.get("type", "")) != RulesEngine.DECISION_DAMAGE or not JsonUtil.as_strings(d.get("targets", [])).has(id):
		return
	damage_target = id
	refresh()


## A hand card (by position) takes 1 DMG of the pending hit, or stops taking it.
func toggle_damage_card(index: int) -> void:
	var at: int = damage_cards.find(index)
	if at >= 0:
		damage_cards.remove_at(at)
	elif damage_cards.size() < damage_spare():
		damage_cards.append(index)
	else:
		return
	refresh()


## The hero choice waiting on a local player, if any; `targeting_changed` tells the table.
func _refresh_choice() -> void:
	var heroes := PackedStringArray()
	var cores := PackedStringArray()
	var cards := PackedStringArray()
	var hurt := PackedStringArray()
	var slot: int = -1
	if not state.pending.is_empty() and not _banner_busy:
		var d: Dictionary = state.pending[0]
		var who: int = JsonUtil.as_int(d.get("player", -1), -1)
		var kind: String = str(d.get("kind", ""))
		var options: PackedStringArray = JsonUtil.as_strings(d.get("options", []))
		if local_slots.has(who) and str(d.get("type", "")) == FxRuntime.DECISION_CHOOSE:
			if kind == "hero":
				heroes = options
			elif kind == "core" and _all_on_field(options):
				cores = options
			# The hand is away while the balls are aimed; the dialog asks then.
			elif kind == "card" and not (state.phase == GameState.PHASE_ROLL and not state.rolled):
				cards = options
			slot = who
		elif local_slots.has(who) and str(d.get("type", "")) == RulesEngine.DECISION_DAMAGE:
			hurt = JsonUtil.as_strings(d.get("targets", []))
			slot = who
	var key: String = ""
	if not state.pending.is_empty() and str(state.pending[0].get("type", "")) == RulesEngine.DECISION_DAMAGE:
		var d0: Dictionary = state.pending[0]
		key = "%s|%s|%s" % [str(d0.get("player", "")), str(d0.get("winner", "")), ",".join(JsonUtil.as_strings(d0.get("targets", [])))]
	if key != _damage_key:
		# A new hit: nothing picked yet (the only hero in reach picks itself).
		_damage_key = key
		var targets: PackedStringArray = JsonUtil.as_strings(state.pending[0].get("targets", [])) if not key.is_empty() else PackedStringArray()
		damage_target = targets[0] if targets.size() == 1 else ""
		damage_cards = PackedInt32Array()
	if heroes != choice_heroes or cores != choice_cores or cards != choice_cards or hurt != damage_heroes or slot != choice_slot:
		choice_heroes = heroes
		choice_cores = cores
		choice_cards = cards
		damage_heroes = hurt
		choice_slot = slot
		targeting_changed.emit()


## Cores held by a hero have no hex of their own to click: those are asked in the dialog.
func _all_on_field(ids: PackedStringArray) -> bool:
	for id: String in ids:
		var c: CoreState = state.core(id)
		if c == null or c.place != CoreState.ON_FIELD:
			return false
	return not ids.is_empty()


## A card effect asks for a hero, core, card or branch (hexes are clicked on the table).
func _choose_dialog(d: Dictionary, who: int) -> void:
	var kind: String = str(d.get("kind", ""))
	# Hexes and heroes are picked on the table (`_refresh_choice`).
	if kind == "hex" or kind == "hero" or (kind == "core" and not choice_cores.is_empty()) or (kind == "card" and not choice_cards.is_empty()):
		return
	_small_dialog(Palette.GOLD)
	var ctx: Dictionary = JsonUtil.as_dict(JsonUtil.as_dict(d.get("resume", {})).get("ctx", {}))
	var source: String = str(ctx.get("card", ""))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_dialog_box.add_child(row)
	var tex: Texture2D = db.thumb(source) if db != null and not source.is_empty() else null
	if tex != null:
		# The card first (Marko 2026-11-08, from the mockups): what the choice is about is on it.
		var a: float = float(tex.get_width()) / tex.get_height()
		var pic := TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		var h: float = CHOICE_CARD_H if a < 1.0 else CHOICE_CARD_H_WIDE
		pic.custom_minimum_size = Vector2(h * a, h)
		pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pic.material = round_corners(a)
		pic.mouse_filter = Control.MOUSE_FILTER_STOP
		pic.gui_input.connect(func(e: InputEvent) -> void: _card_click(e, source))
		row.add_child(pic)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size.x = 340
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	col.add_child(UiTheme.label(_card_name(source).to_upper() + ("  ·  %s" % player_name(who).to_upper() if local_slots.size() > 1 else ""), 13, Palette.GOLD))
	var title: Label = UiTheme.label(str(d.get("prompt", "Choose")).to_upper(), 28)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var options: Array = JsonUtil.as_array(d.get("options", []))
	for i: int in options.size():
		var o: Variant = options[i]
		var text: String = str(o)
		match kind:
			"hero":
				var h_opt: HeroState = state.hero(str(o))
				text = "%s   HP %d" % [hero_name(h_opt).to_upper(), h_opt.hp] if h_opt != null else str(o)
			"core":
				var c: CoreState = state.core(str(o))
				text = "%s CORE AT %s" % ["FACE-UP" if c != null and c.face_up else "FACE-DOWN", str(c.hex) if c != null else "?"]
			"card":
				text = _card_name(str(o)).to_upper()
		var value: Variant = i if kind == "option" else o
		var b: Button = _option_button(text, func() -> void: choose_pressed.emit(who, value))
		_dialog_box.remove_child(b)
		col.add_child(b)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 18)
		b.custom_minimum_size = Vector2(0, 66)


## Combo offer (2026-11-07; Marko 2026-11-08, from the mockups): the second card of a pair was played.
## The two cards, one over the other, equal the combo, its name and extra energy beside them; with more
## than one combo on offer the first one shows and each has its button. COMBO sends the two cards off
## from where they stand here (_combo_merge).
func _combo_dialog(d: Dictionary, who: int) -> void:
	_small_dialog(Palette.GOLD)
	_combo_from = []
	var cid: String = str(d.get("card", ""))
	var offers: Array = JsonUtil.as_array(d.get("combos", []))
	var first: Dictionary = JsonUtil.as_dict(offers[0]) if not offers.is_empty() else {}
	var first_id: String = str(first.get("id", ""))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_dialog_box.add_child(row)
	var parts := HBoxContainer.new()
	parts.add_theme_constant_override("separation", COMBO_PARTS_OVERLAP)
	parts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(parts)
	_combo_pics = []
	for id: String in [str(first.get("with", "")), cid]:
		var pic: Control = _combo_pic(id)
		if pic != null:
			parts.add_child(pic)
			_combo_pics.append(pic)
	var equals: Label = UiTheme.label("=", 36, Palette.ACCENT)
	equals.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(equals)
	var combo_pic: Control = _combo_pic(first_id)
	if combo_pic != null:
		row.add_child(combo_pic)
	# The buttons lean towards the card: a little more room than between the cards.
	var gap := Control.new()
	gap.custom_minimum_size.x = 6
	row.add_child(gap)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.custom_minimum_size.x = 276
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	col.add_child(UiTheme.label("COMBO" + ("  ·  %s" % player_name(who).to_upper() if local_slots.size() > 1 else ""), 13, Palette.GOLD))
	var title: Label = UiTheme.label(_card_name(first_id).to_upper() if offers.size() == 1 else "WHICH COMBO?", 26)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	for o: Variant in offers:
		var c: Dictionary = JsonUtil.as_dict(o)
		var id: String = str(c.get("id", ""))
		var text: String = "+%d ENERGY" % JsonUtil.as_int(c.get("extra", 0))
		if offers.size() > 1:
			text = "%s  ·  %s" % [_card_name(id).to_upper(), text]
		var b: Button = _option_button(text, func() -> void:
			combo_take_off()
			choose_pressed.emit(who, id))
		_dialog_box.remove_child(b)
		col.add_child(b)
		b.theme_type_variation = &"Gold"
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(0, 48)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var no: Button = _option_button("PLAY %s AS IT IS" % _card_name(cid).to_upper(), func() -> void: choose_pressed.emit(who, ""))
	_dialog_box.remove_child(no)
	# Slanted buttons: these margins make its top corners meet the bottom corners of the one above alike.
	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_left", -4)
	inset.add_theme_constant_override("margin_right", 12)
	col.add_child(inset)
	inset.add_child(no)
	no.alignment = HORIZONTAL_ALIGNMENT_CENTER
	no.add_theme_font_size_override("font_size", 16)
	no.custom_minimum_size = Vector2(0, 36)


func _combo_texture(id: String) -> Texture2D:
	if db == null or id.is_empty():
		return null
	return db.large(id) if db.large(id) != null else db.thumb(id)


## A card in the combo window, COMBO_CARD_H tall; a right click shows it big.
func _combo_pic(id: String) -> Control:
	var tex: Texture2D = _combo_texture(id)
	if tex == null:
		return null
	var a: float = float(tex.get_width()) / tex.get_height()
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.custom_minimum_size = Vector2(COMBO_CARD_H * a, COMBO_CARD_H)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pic.material = round_corners(a)
	pic.mouse_filter = Control.MOUSE_FILTER_STOP
	pic.gui_input.connect(func(e: InputEvent) -> void: _card_click(e, id))
	return pic


## Where the two cards stand in the window: the merge starts from there.
func combo_take_off() -> void:
	_combo_from = []
	if _combo_pics.size() != 2:
		return
	for pic: Control in _combo_pics:
		if is_instance_valid(pic):
			_combo_from.append(pic.get_global_rect())


## The two cards fly to the middle, side by side, dash into each other and flash; the combo card comes
## out of the flash (Marko 2026-11-08, from the mockups). They start where they stood in the window for
## the player who chose it, and at the middle for everyone else.
func _combo_merge(show: Panel, parts: PackedStringArray, meet: Vector2, dim: ColorRect, t: Tween) -> void:
	var from: Array[Rect2] = _combo_from
	_combo_from = []
	if parts.size() != 2 or _combo_texture(parts[0]) == null or _combo_texture(parts[1]) == null:
		return
	var s: float = GameSettings.anim_scale()
	var flyers: Array[TextureRect] = []
	for i: int in 2:
		var tex: Texture2D = _combo_texture(parts[i])
		var a: float = float(tex.get_width()) / tex.get_height()
		var sz := Vector2(COMBO_CARD_H * a, COMBO_CARD_H)
		var rect := Rect2(meet - sz * 0.5 + Vector2(sz.x * COMBO_SPREAD * (-1.0 if i == 0 else 1.0), 0.0), sz)
		var f := TextureRect.new()
		f.texture = tex
		f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		f.stretch_mode = TextureRect.STRETCH_SCALE
		f.material = round_corners(a)
		f.position = from[i].position if from.size() == 2 else rect.position
		f.size = from[i].size if from.size() == 2 else sz
		f.pivot_offset = f.size * 0.5
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		f.modulate.a = 1.0 if from.size() == 2 else 0.0
		show.add_child(f)
		flyers.append(f)
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.75)
	flash.size = size
	flash.modulate.a = 0.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	show.add_child(flash)
	t.tween_property(dim, "modulate:a", 0.5, 0.14 * s)
	for i: int in 2:
		var f: TextureRect = flyers[i]
		var side: float = -1.0 if i == 0 else 1.0
		t.parallel().tween_property(f, "position", meet - f.size * 0.5 + Vector2(f.size.x * COMBO_SIDE * side, 0.0), COMBO_FLY_TIME * s).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(f, "scale", Vector2.ONE * COMBO_FLY_SCALE, COMBO_FLY_TIME * s).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(f, "rotation_degrees", 8.0 * side, COMBO_FLY_TIME * s).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(f, "modulate:a", 1.0, 0.1 * s)
	t.tween_interval(0.08 * s)
	# A new step: the ones below run together.
	t.tween_interval(0.0)
	for f: TextureRect in flyers:
		t.parallel().tween_property(f, "position", meet - f.size * 0.5, COMBO_DASH_TIME * s).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(f, "rotation_degrees", 0.0, COMBO_DASH_TIME * s).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(f, "modulate", Color(4, 4, 4), COMBO_DASH_TIME * s)
	t.tween_callback(func() -> void:
		flash.modulate.a = 1.0
		flash.create_tween().tween_property(flash, "modulate:a", 0.0, 0.22 * s)
		for f: TextureRect in flyers:
			f.create_tween().tween_property(f, "modulate:a", 0.0, 0.08 * s))


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
	var was: String = _live_key
	_live_key = "%d|%d" % [state.turn, state.battle_index] if state.phase == GameState.PHASE_BATTLE \
			and state.battle_index >= 0 and state.battle_index < state.battles.size() else ""
	var n: int = state.log.size()
	if _log_seen < 0 or n < _log_seen:
		_log_seen = n
		return
	var fresh: Array[Dictionary] = []
	var banked: Array[Dictionary] = []
	for i: int in range(_log_seen, n):
		var e: Dictionary = state.log[i]
		var t: String = str(e.get("type", ""))
		if t == "stage_energy":
			banked.append(e)
		if (t == "equipped" or t == "evolved" or t == "action") and not str(e.get("hero", "")).is_empty():
			card_played.emit(str(e.get("card", "")), str(e.get("hero", "")))
		if t == "equipped" or t == "assist":
			_announce_card(e)
		if (t == "triggered" or t == "ability") and not str(e.get("hero", "")).is_empty():
			ability_fired.emit(str(e.get("hero", "")), str(e.get("card", "")))
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
	# The moment's bands together, merged (a replay jumping ahead shows only the last few).
	_grouping = true
	# What a move made during a battle brought belongs to that battle, also when the move closed it
	# (the hits come after the damage choice, and the same move opens the next battle).
	if not was.is_empty() and was != _live_key \
			and was == "%d|%d" % [JsonUtil.as_int(_bar_last.get("turn", -1), -1), JsonUtil.as_int(_bar_last.get("index", -1), -1)]:
		_tagging = _bar_last.duplicate()
	for e: Dictionary in fresh.slice(maxi(0, fresh.size() - 8)):
		if str(e.get("type", "")) == "battle":
			_tagging = _battle_tag(e)
		_banner_for(e)
	# The energy of the End phase is no longer the battle's.
	_tagging = {}
	if not banked.is_empty():
		_energy_note(banked)
	_grouping = false
	_push_group()
	_note_shown_battle()


func _banner_for(e: Dictionary) -> void:
	match str(e.get("type", "")):
		"combo":
			# The combo card over the screen (_combo_show); a plain band when it has no picture.
			var combo_id: String = str(e.get("combo", ""))
			banner("COMBO!", Palette.GOLD, player_name(JsonUtil.as_int(e.get("player", 0))).to_upper(), _card_name(combo_id).to_upper(), COMBO_SHOW_TIME, combo_id, JsonUtil.as_strings(e.get("cards", [])))
		"battle":
			# Power is per team: each side's heroes in that battle and their total.
			var power: Dictionary = JsonUtil.as_dict(e.get("power", {}))
			var index: int = JsonUtil.as_int(e.get("index", state.battle_index))
			# The heroes come with the event (playtest 2026-11-06: a battle with no hit ends the turn at
			# once, the battle list is already empty and the banner said " WINS THE FIGHT!").
			var ids: PackedStringArray = JsonUtil.as_strings(e.get("heroes", []))
			if ids.is_empty() and index >= 0 and index < state.battles.size():
				ids = JsonUtil.as_strings(state.battles[index].get("heroes", []))
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
			# Replays from before 2026-11-02 only.
			if str(e.get("phase", "")) == GameState.PHASE_BATTLE:
				var p: PlayerState = state.player(JsonUtil.as_int(e.get("player", 0)))
				banner("%s DECKS %d!" % [player_name(p.slot).to_upper(), JsonUtil.as_int(e.get("amount", 0))], Palette.ACCENT_DEEP, "", "%d LEFT IN THE DECK" % p.deck.size(), 1.6)
		"hand_damage":
			var n: int = JsonUtil.as_int(e.get("amount", 0))
			banner("%s DISCARDS %d CARD%s" % [player_name(JsonUtil.as_int(e.get("player", 0))).to_upper(), n, "" if n == 1 else "S"], Palette.ACCENT_DEEP, "",
				", ".join(_card_names(JsonUtil.as_strings(e.get("cards", [])))).to_upper(), 1.6)
		"ring_out":
			banner("RING-OUT", Palette.GOLD, "", _hero_label(str(e.get("hero", ""))).to_upper())
		"ko":
			# The KO that ends the match is told by the end of it (Marko 2026-11-10/11: Z1, Y2).
			if state.is_over() and state.result == "ko" and JsonUtil.as_int(e.get("turn", -1), -1) == state.turn:
				return
			_ko_banner(str(e.get("hero", "")))
		"stage_claimed":
			var st: StageState = state.stage(str(e.get("stage", "")))
			banner("STAGE CLAIMED", Palette.GOLD, player_name(JsonUtil.as_int(e.get("player", 0))).to_upper(),
				_card_name(st.card_id if st != null else "").to_upper())
		"stage_knocked_off":
			# The energy claim variant: knocked off by the other side, half the energy in it goes.
			var lost: int = JsonUtil.as_int(e.get("lost", 0))
			if lost > 0:
				var sk: StageState = state.stage(str(e.get("stage", "")))
				banner("KNOCKED OFF", Palette.ACCENT_DEEP, _hero_label(str(e.get("hero", ""))).to_upper(),
					"-%d ENERGY · %s %d/%d" % [lost, _card_name(sk.card_id if sk != null else "").to_upper(),
					JsonUtil.as_int(e.get("progress", 0)), JsonUtil.as_int(e.get("goal", 0))], 1.6)
		"triggered":
			var name: String = _triggered_name(e)
			if not name.is_empty():
				banner(name.to_upper(), Palette.GOLD, _hero_label(str(e.get("hero", ""))).to_upper(), "")
		"battle_locked":
			# A tie (GDD 10): nobody is hurt, the heroes stay locked and fight again next turn.
			# The band says it all (Marko 2026-11-09: the straw line above said the same a second early).
			banner("TIE!", Palette.GOLD, _heroes_line(e).to_upper(), "SAME POWER · FIGHT AGAIN NEXT TURN", BATTLE_BANNER_TIME)
		"battle_tie_break":
			banner("TIE AGAIN!", Palette.ACCENT, _heroes_line(e).to_upper(), "BOTH KNOCKED BACK", BATTLE_BANNER_TIME)


func _next_banner() -> void:
	if _banners.is_empty():
		_now = {}
		_note_shown_battle()
		if _banner_busy:
			_banner_busy = false
			announcing_changed.emit(false)
			# A choice that waited behind the bands shows now.
			if state != null:
				refresh()
		return
	if not _banner_busy:
		_banner_busy = true
		announcing_changed.emit(true)
	var b: Dictionary = _banners.pop_front()
	_now = b
	_note_shown_battle()
	if JsonUtil.as_bool(b.get("pop", false)) and _pop_show(b):
		return
	if not str(b.get("card", "")).is_empty() and not JsonUtil.as_bool(b.get("pop", false)) and _combo_show(b):
		return
	if b.has("ko") and _ko_show(b):
		return
	var lines: PackedStringArray = b.get("lines", PackedStringArray())
	var color: Color = b["color"]
	var fg: Color = Color.BLACK if color.get_luminance() > 0.5 else Palette.FG
	var w: float = size.x + 200.0
	var band := Panel.new()
	var sb: StyleBoxFlat = UiTheme.box(color, 0)
	sb.border_color = Color.BLACK
	sb.set_border_width_all(6)
	band.add_theme_stylebox_override("panel", sb)
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
	var right: String = str(b["right"])
	if not lines.is_empty():
		right = "\n".join(([right] if not right.is_empty() else []) + Array(lines))
	var side_r: Label = _banner_side(right, fg, false)
	if not lines.is_empty():
		side_r.add_theme_font_size_override("font_size", 22)
	row.add_child(side_r)
	# Everything stays on the screen, clear of its sides (Marko 2026-11-02: a long right side ran
	# off it; 2026-11-09: it still stood against the edge): the sides wrap first, then the title
	# gets smaller until the row fits.
	var side_l := row.get_child(0) as Label
	var room: float = size.x - BAND_MARGIN * 2.0
	if row.get_combined_minimum_size().x > room:
		for side: Label in [side_r, side_l]:
			if side.get_minimum_size().x > BAND_SIDE_W:
				side.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				side.custom_minimum_size.x = BAND_SIDE_W
				side.add_theme_font_size_override("font_size", 22)
	var title_size: int = 84
	while row.get_combined_minimum_size().x > room and title_size > 40:
		title_size -= 6
		title.add_theme_font_size_override("font_size", title_size)
	# As tall as its longest side needs (five discarded cards wrap to as many lines).
	var h: float = 100.0
	for side: Label in [side_l, side_r]:
		if side.text.is_empty():
			continue
		var wrap: float = side.custom_minimum_size.x if side.autowrap_mode != TextServer.AUTOWRAP_OFF else -1.0
		h = maxf(h, side.get_theme_font("font").get_multiline_string_size(side.text, HORIZONTAL_ALIGNMENT_LEFT, wrap,
			side.get_theme_font_size("font_size")).y + BAND_PAD_Y)
	band.size = Vector2(w, h)
	band.pivot_offset = band.size * 0.5
	band.position = Vector2(-100.0 - w, size.y * 0.5 - h * 0.5)
	_band = band
	var t: Tween = band.create_tween()
	_band_tween = t
	t.tween_property(band, "position:x", -100.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(JsonUtil.as_float(b.get("hold", BANNER_TIME), BANNER_TIME) * GameSettings.anim_scale())
	t.tween_property(band, "position:x", size.x + 100.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		band.queue_free()
		_next_banner())


## A hero knocked out: its card over the screen (_ko_show), queued like a band, standing alone.
func _ko_banner(hero_id: String) -> void:
	if GameSettings.banners() == "off":
		return
	var b: Dictionary = {"title": "KO", "color": Palette.ACCENT_DEEP, "left": "", "right": _hero_label(hero_id).to_upper(),
		"hold": KO_SHOW_TIME, "lines": PackedStringArray(), "card": "", "parts": PackedStringArray(), "ko": PackedStringArray([hero_id])}
	if not _tagging.is_empty():
		b["battle"] = _tagging
	if _grouping:
		_group.append(b)
		return
	_banners.append(b)
	if not _banner_busy:
		_next_banner()


## Evil Bochet's claws are taking this hero down (a hole, or a hand into the dark): its announcement waits.
func ko_wait(hero_id: String) -> void:
	_ko_waiting[hero_id] = true


## ...and it is gone now.
func ko_done(hero_id: String) -> void:
	_ko_waiting.erase(hero_id)


func _ko_waits(ids: PackedStringArray) -> bool:
	for id: String in ids:
		if _ko_waiting.has(id):
			return true
	return false


## The KO announcement (item 26, E2 + E4, Marko 2026-11-09/10): the screen goes red, the fallen hero's
## card lands in the middle with a rim and glow in its team's colour, KNOCKED OUT stamps onto it with a
## jolt, and the line "<PLAYER> · N HEROES LEFT" comes under it; then it fades. Two at once side by side
## (KO6). With Evil Bochet (KO4) it waits until his claws have taken the ball down, and at the end the
## line goes first and a hand of his comes up from under the screen, hooks each card and drags it down,
## the right one KO_DRAG_GAP after the left. A click or Enter skips it.
func _ko_show(b: Dictionary) -> bool:
	var ids: PackedStringArray = JsonUtil.as_strings(b.get("ko", []))
	var fallen: Array[HeroState] = []
	for id: String in ids:
		var h: HeroState = state.hero(id)
		if h != null and db != null and engine.stat_card(h) != null:
			fallen.append(h)
	if fallen.is_empty():
		return false
	var show := Panel.new()
	show.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	show.set_meta("show", true)
	show.z_index = 90
	show.size = size
	show.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_layer.add_child(show)
	_band = show
	_band_tween = null
	# Evil Bochet's claws take them down now, the bands before this one gone (the match opens the holes).
	ko_due.emit(ids)
	_ko_run(show, fallen, ids)
	return true


func _ko_run(show: Panel, fallen: Array[HeroState], ids: PackedStringArray) -> void:
	var waited: float = 0.0
	while _ko_waits(ids) and waited < KO_WAIT_MOST:
		await get_tree().process_frame
		if not is_instance_valid(show) or _band != show:
			return
		waited += get_process_delta_time()
	if waited > 0.0:
		await get_tree().create_timer(0.15).timeout
		if not is_instance_valid(show) or _band != show:
			return
	_band_tween = _ko_build(show, fallen, bochet)


func _ko_build(show: Panel, fallen: Array[HeroState], drag: bool) -> Tween:
	var n: int = fallen.size()
	var mid := Vector2(size.x * 0.5, size.y * 0.5 - 10.0)
	var dim := ColorRect.new()
	dim.color = Color(0.22, 0.0, 0.0, 0.7)
	dim.position = Vector2(-40, -40)
	dim.size = size + Vector2(80, 80)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.modulate.a = 0.0
	show.add_child(dim)
	var held := Control.new()
	held.mouse_filter = Control.MOUSE_FILTER_IGNORE
	show.add_child(held)
	var hh: float = 350.0 if n == 1 else 290.0
	var grip_y: float = mid.y + hh * 0.5 + 125.0
	var cards: Array[Control] = []
	var hands: Array[Node2D] = []
	var stamps: Array[UiShape] = []
	var lines: Array[Label] = []
	var xs: Array[float] = []
	var gap: float = 0.0
	for i: int in n:
		var hero: HeroState = fallen[i]
		var team: Color = Palette.team(state.team_of(hero.owner))
		var card_id: String = engine.stat_card(hero).id
		var big: Texture2D = db.large(card_id) if db.large(card_id) != null else db.thumb(card_id)
		var ww: float = hh * 0.716
		if big != null:
			ww = hh * float(big.get_width()) / maxf(float(big.get_height()), 1.0)
		gap = ww + 70.0
		var cx: float = mid.x + (i - (n - 1) * 0.5) * gap
		xs.append(cx)
		var card := Control.new()
		card.position = Vector2(cx, mid.y)
		card.rotation_degrees = -3.0 if i % 2 == 0 else 3.0
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.modulate.a = 0.0
		card.scale = Vector2.ONE * 1.3
		held.add_child(card)
		var frame := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(team, 0.25)
		sb.border_color = team.lightened(0.15)
		sb.set_border_width_all(7)
		sb.set_corner_radius_all(22)
		sb.shadow_color = Color(team, 0.55)
		sb.shadow_size = 26
		frame.add_theme_stylebox_override("panel", sb)
		frame.size = Vector2(ww + 22.0, hh + 22.0)
		frame.position = -frame.size * 0.5
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(frame)
		var pic := TextureRect.new()
		pic.texture = big
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.size = Vector2(ww, hh)
		pic.position = -pic.size * 0.5
		pic.modulate = Color(1.0, 0.82, 0.82)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(pic)
		cards.append(card)
	if drag:
		for i: int in n:
			var hand := Node2D.new()
			hand.position = Vector2(xs[i], grip_y + 560.0)
			hand.scale = Vector2.ONE * (1.0 if n == 1 else 0.86)
			held.add_child(hand)
			_claws_2d(hand)
			hands.append(hand)
	for i: int in n:
		var stamp: UiShape = UiShape.chip("KNOCKED OUT", Palette.ACCENT, Palette.FG, 70 if n == 1 else 52, 96.0 if n == 1 else 72.0, 30.0 if n == 1 else 24.0)
		stamp.outline = Color.BLACK
		stamp.outline_width = 4.0
		stamp.pivot_offset = stamp.custom_minimum_size * 0.5
		stamp.rotation_degrees = -8.0 if i % 2 == 0 else 6.0
		stamp.position = Vector2(xs[i], mid.y) - stamp.custom_minimum_size * 0.5
		stamp.modulate.a = 0.0
		stamp.scale = Vector2.ONE * 2.6
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		held.add_child(stamp)
		stamps.append(stamp)
		var hero: HeroState = fallen[i]
		var left: int = 0
		for x: HeroState in state.heroes_of(hero.owner):
			if not x.is_ko():
				left += 1
		var line: Label = UiTheme.label("%s  ·  %d HERO%s LEFT" % [player_name(hero.owner).to_upper(), left, "" if left == 1 else "ES"], 30 if n == 1 else 24, Color(Palette.FG, 0.9))
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var lw: float = size.x if n == 1 else gap
		line.position = Vector2(xs[i] - lw * 0.5, mid.y + hh * 0.5 + 40.0)
		line.size = Vector2(lw, 40)
		line.modulate.a = 0.0
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		show.add_child(line)
		lines.append(line)
	var t: Tween = show.create_tween()
	t.tween_property(dim, "modulate:a", 1.0, 0.15)
	for card: Control in cards:
		t.parallel().tween_property(card, "modulate:a", 1.0, 0.12)
		t.parallel().tween_property(card, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.22)
	for i: int in n:
		t.tween_property(stamps[i], "modulate:a", 1.0, 0.04)
		t.parallel().tween_property(stamps[i], "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		for off: Vector2 in [Vector2(9, -7), Vector2(-7, 6), Vector2(5, -3), Vector2(-2, 2), Vector2.ZERO]:
			t.tween_property(show, "position", off, 0.035)
		t.parallel().tween_property(cards[i], "scale", Vector2.ONE * 0.97, 0.05)
		t.tween_property(cards[i], "scale", Vector2.ONE, 0.08)
	t.tween_interval(0.02)
	for line: Label in lines:
		t.parallel().tween_property(line, "modulate:a", 1.0, 0.2)
	if drag:
		t.tween_interval(0.7)
		# The line goes first: nothing is written over the hand.
		t.tween_interval(0.01)
		for line: Label in lines:
			t.parallel().tween_property(line, "modulate:a", 0.0, 0.12)
		t.tween_interval(0.01)
		for i: int in n:
			t.parallel().tween_callback(_ko_drag_one.bind(show, cards[i], hands[i], stamps[i], grip_y, KO_DRAG_GAP * i, 2.5 if i % 2 == 0 else -2.5))
		t.tween_interval(0.17 + 0.06 + 0.3 + 0.36 + KO_DRAG_GAP * (n - 1))
		t.tween_interval(0.3)
	else:
		t.tween_interval(1.5 * GameSettings.anim_scale())
	t.tween_property(show, "modulate:a", 0.0, 0.25)
	t.tween_callback(func() -> void:
		show.queue_free()
		if _band == show:
			_band = null
		_next_banner())
	return t


## One fallen hero's card taken by Evil Bochet's hand: up onto the card, a tug, and down with it and its stamp.
func _ko_drag_one(show: Control, card: Control, hand: Node2D, stamp: Control, grip_y: float, wait: float, tilt: float) -> void:
	if not is_instance_valid(show):
		return
	var drop: float = size.y + 260.0
	var cy: float = card.position.y
	var sy: float = stamp.position.y
	var t: Tween = show.create_tween()
	t.tween_interval(wait + 0.001)
	t.tween_property(hand, "position:y", grip_y, 0.17).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(card, "position:y", cy + 14.0, 0.06)
	t.parallel().tween_property(stamp, "position:y", sy + 14.0, 0.06)
	t.parallel().tween_property(hand, "position:y", grip_y + 14.0, 0.06)
	t.parallel().tween_property(card, "rotation_degrees", tilt, 0.06)
	t.tween_interval(0.3)
	t.tween_property(card, "position:y", cy + drop, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(stamp, "position:y", sy + drop, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(hand, "position:y", grip_y + drop, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(card, "rotation_degrees", tilt * 3.2, 0.36)


## Evil Bochet's hand drawn flat on the screen, coming up from under it: the back of the hand and four
## fingers, each with two plates and a claw.
func _claws_2d(hand: Node2D) -> void:
	var skin := Color("241640")
	var edge := Color("5a37a8")
	var plate := Color("36215f")
	var nail := Color("e9dcbd")
	var nail_dark := Color("9a7b55")
	_poly_2d(hand, PackedVector2Array([Vector2(-134, 150), Vector2(134, 150), Vector2(156, 700), Vector2(-156, 700)]), skin)
	for i: int in 4:
		var x: float = (i - 1.5) * 62.0
		var top: float = -200.0 + absf(i - 1.5) * 20.0
		_poly_2d(hand, PackedVector2Array([Vector2(x - 29, 300), Vector2(x - 29, top + 24), Vector2(x - 18, top), Vector2(x + 18, top), Vector2(x + 29, top + 24), Vector2(x + 29, 300)]), skin)
		_poly_2d(hand, PackedVector2Array([Vector2(x - 29, 300), Vector2(x - 29, top + 24), Vector2(x - 18, top), Vector2(x - 10, top), Vector2(x - 20, top + 26), Vector2(x - 20, 300)]), edge)
		_poly_2d(hand, PackedVector2Array([Vector2(x - 17, top + 62), Vector2(x + 21, top + 62), Vector2(x + 17, top + 108), Vector2(x - 13, top + 108)]), plate)
		_poly_2d(hand, PackedVector2Array([Vector2(x - 15, top + 128), Vector2(x + 19, top + 128), Vector2(x + 15, top + 170), Vector2(x - 11, top + 170)]), plate)
		var lean: float = -(i - 1.5) * 7.0
		_poly_2d(hand, PackedVector2Array([Vector2(x - 20, top + 8), Vector2(x + 20, top + 8), Vector2(x + 15 + lean * 0.4, top - 38), Vector2(x + 6 + lean * 0.8, top - 78), Vector2(x + lean * 1.3, top - 104), Vector2(x - 8 + lean * 0.8, top - 70), Vector2(x - 16 + lean * 0.4, top - 34)]), nail)
		_poly_2d(hand, PackedVector2Array([Vector2(x - 20, top + 8), Vector2(x + 20, top + 8), Vector2(x + 18, top - 12), Vector2(x - 18, top - 12)]), nail_dark)


static func _poly_2d(parent: Node, pts: PackedVector2Array, col: Color) -> void:
	var pg := Polygon2D.new()
	pg.polygon = pts
	pg.color = col
	parent.add_child(pg)


## The other side put down an Equipment or an Assist (Marko 2026-11-07: it went by unseen): its card
## shows for a moment on their side with what happened, then flies to the hero (or to their name).
func _announce_card(e: Dictionary) -> void:
	if GameSettings.banners() == "off":
		return
	var t: String = str(e.get("type", ""))
	var cid: String = str(e.get("card", ""))
	var h: HeroState = state.hero(str(e.get("hero", ""))) if t == "equipped" else null
	var who: int = h.owner if h != null else JsonUtil.as_int(e.get("player", -1), -1)
	if who < 0 or local_slots.has(who):
		return
	var text: String = ("%s EQUIPS %s ON %s" % [player_name(who), _card_name(cid), hero_name(h)]) if h != null \
			else ("%s PLAYS %s AS AN ASSIST" % [player_name(who), _card_name(cid)])
	var b: Dictionary = {"title": text.to_upper(), "color": Palette.team(state.team_of(who)), "left": "", "right": "", "hold": POP_TIME,
		"lines": PackedStringArray(), "card": cid, "pop": true, "hero": h.id if h != null else "", "slot": who}
	if _grouping:
		_group.append(b)
		return
	_banners.append(b)
	if not _banner_busy:
		_next_banner()


## The card of _announce_card: in from the side of the player who put it down, held with the line
## under it, then small into the hero's panel (or the top of that player's column). Skips like a band.
func _pop_show(b: Dictionary) -> bool:
	var cid: String = str(b.get("card", ""))
	var tex: Texture2D = null
	if db != null:
		tex = db.large(cid) if db.large(cid) != null else db.thumb(cid)
	if tex == null:
		return false
	var slot: int = JsonUtil.as_int(b.get("slot", 0))
	var right: bool = _rosters.size() > 1 and _rosters[1] != null and state.team_of(slot) == 1
	var show := Panel.new()
	show.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	show.set_meta("show", true)
	show.z_index = 90
	show.size = size
	show.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_layer.add_child(show)
	var aspect: float = float(tex.get_width()) / tex.get_height()
	var w: float = 250.0
	var card_size := Vector2(w, w / aspect)
	var holder := Control.new()
	holder.size = card_size
	holder.pivot_offset = card_size * 0.5
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	show.add_child(holder)
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.size = card_size
	pic.material = round_corners(aspect)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pic)
	var color: Color = b.get("color", Palette.GOLD)
	var chip: UiShape = UiShape.chip(str(b.get("title", "")), color, Palette.FG, 20, 34.0, 14.0)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	show.add_child(chip)
	# Beside that player's column, a little above the middle.
	var rest := Vector2(size.x - ROSTER_WIDTH - 60.0 - w if right else ROSTER_WIDTH + 60.0, size.y * 0.42 - card_size.y * 0.5)
	var from := Vector2(size.x + 40.0 if right else -w - 40.0, rest.y)
	holder.position = from
	chip.position = Vector2(clampf(rest.x + w * 0.5 - chip.custom_minimum_size.x * 0.5, 16.0, size.x - chip.custom_minimum_size.x - 16.0), rest.y + card_size.y + 14.0)
	chip.modulate.a = 0.0
	# Where it goes: the hero's panel, else the top of the column.
	var to := Vector2(size.x - 200.0 if right else 200.0, 90.0)
	var hid: String = str(b.get("hero", ""))
	if _slice_of.has(hid) and is_instance_valid(_slice_of[hid]):
		to = _slice_of[hid].get_global_rect().get_center() - global_position
	var hold: float = JsonUtil.as_float(b.get("hold", POP_TIME), POP_TIME) * GameSettings.anim_scale()
	var t: Tween = show.create_tween()
	t.tween_property(holder, "position", rest, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(chip, "modulate:a", 1.0, 0.2).set_delay(0.12)
	t.tween_interval(hold)
	t.tween_property(chip, "modulate:a", 0.0, 0.15)
	t.parallel().tween_property(holder, "position", to - card_size * 0.5, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(holder, "scale", Vector2(0.12, 0.12), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(holder, "modulate:a", 0.2, 0.35)
	t.tween_callback(func() -> void:
		show.queue_free()
		_next_banner())
	_band = show
	_band_tween = t
	return true


## The combo card over the screen (2026-11-07, combo plan step 5): the table dims, the card turns in big
## and flashes, its rim glows gold and pulses while "COMBO!" and who played it show, then it shrinks
## away. A click or Enter skips it (skip_banner). False when the card has no picture: the band shows.
func _combo_show(b: Dictionary) -> bool:
	var cid: String = str(b.get("card", ""))
	var tex: Texture2D = null
	if db != null:
		tex = db.large(cid) if db.large(cid) != null else db.thumb(cid)
	if tex == null:
		return false
	var show := Panel.new()
	show.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	show.set_meta("show", true)
	# Over everything of the HUD, the raised hand cards and the hero panels too.
	show.z_index = 90
	show.size = size
	show.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner_layer.add_child(show)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.size = size
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	show.add_child(dim)
	var aspect: float = float(tex.get_width()) / tex.get_height()
	var w: float = minf(size.x * 0.62, (size.y - 280.0) * aspect)
	var card_size := Vector2(w, w / aspect)
	var holder := Control.new()
	holder.size = card_size
	holder.pivot_offset = card_size * 0.5
	holder.position = (size - card_size) * 0.5 + Vector2(0, 10)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	show.add_child(holder)
	# The rim: a gold line and glow just outside the card's own rim.
	var glow := Panel.new()
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color(0, 0, 0, 0)
	gs.set_corner_radius_all(int(w * 0.03))
	gs.border_color = Palette.GOLD
	gs.set_border_width_all(5)
	gs.set_expand_margin_all(5)
	gs.shadow_color = Color(Palette.GOLD, 0.75)
	gs.shadow_size = 36
	glow.add_theme_stylebox_override("panel", gs)
	glow.size = card_size
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glow)
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.size = card_size
	pic.material = round_corners(aspect)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pic)
	var title: Label = UiTheme.label(str(b.get("title", "COMBO!")), 76, Palette.GOLD)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(size.x, 96)
	title.position = Vector2(0, holder.position.y - 112.0)
	title.pivot_offset = title.size * 0.5
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	show.add_child(title)
	var bits := PackedStringArray()
	for key: String in ["left", "right"]:
		if not str(b.get(key, "")).is_empty():
			bits.append(str(b[key]))
	var sub: Label = UiTheme.label("  ·  ".join(bits), 28, Palette.FG)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size = Vector2(size.x, 40)
	sub.position = Vector2(0, holder.position.y + card_size.y + 22.0)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	show.add_child(sub)

	dim.modulate.a = 0.0
	holder.modulate.a = 0.0
	holder.scale = Vector2(0.25, 0.25)
	holder.rotation_degrees = -12.0
	glow.modulate.a = 0.0
	title.modulate.a = 0.0
	sub.modulate.a = 0.0
	pic.self_modulate = Color(2.4, 2.4, 2.4)
	var hold: float = maxf(0.6, JsonUtil.as_float(b.get("hold", COMBO_SHOW_TIME), COMBO_SHOW_TIME) * GameSettings.anim_scale() - 0.6)
	var t: Tween = show.create_tween()
	_combo_merge(show, JsonUtil.as_strings(b.get("parts", [])), holder.position + card_size * 0.5, dim, t)
	t.tween_property(dim, "modulate:a", 1.0, 0.15)
	t.parallel().tween_property(holder, "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(holder, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(holder, "rotation_degrees", 0.0, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(pic, "self_modulate", Color.WHITE, 0.3)
	t.parallel().tween_property(glow, "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(title, "modulate:a", 1.0, 0.15)
	t.parallel().tween_property(title, "scale", Vector2.ONE, 0.25).from(Vector2(1.6, 1.6)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(sub, "modulate:a", 1.0, 0.25)
	t.tween_property(glow, "modulate:a", 0.35, hold * 0.5).set_trans(Tween.TRANS_SINE)
	t.tween_property(glow, "modulate:a", 1.0, hold * 0.5).set_trans(Tween.TRANS_SINE)
	t.tween_property(holder, "scale", Vector2(0.3, 0.3), 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(show, "modulate:a", 0.0, 0.25)
	t.tween_callback(func() -> void:
		show.queue_free()
		_next_banner())
	_band = show
	_band_tween = t
	return true


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
		"hand_damage":
			return "%s discards %d for the hit" % [player_name(JsonUtil.as_int(e.get("player", 0))), JsonUtil.as_int(e.get("amount", 0))]
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
		"stage_energy":
			var se: StageState = state.stage(str(e.get("stage", "")))
			return "%s puts %d energy into %s (%d/%d)" % [player_name(JsonUtil.as_int(e.get("player", 0))), JsonUtil.as_int(e.get("amount", 0)),
				_card_name(se.card_id if se != null else ""), JsonUtil.as_int(e.get("progress", 0)), JsonUtil.as_int(e.get("goal", 0))]
		"stage_knocked_off":
			var so: StageState = state.stage(str(e.get("stage", "")))
			return "%s knocked off %s: -%d energy (%d/%d)" % [hero_l, _card_name(so.card_id if so != null else ""), JsonUtil.as_int(e.get("lost", 0)),
				JsonUtil.as_int(e.get("progress", 0)), JsonUtil.as_int(e.get("goal", 0))]
		"stage_contested":
			var sct: StageState = state.stage(str(e.get("stage", "")))
			return "%s is contested: no energy goes in" % _card_name(sct.card_id if sct != null else "")
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


## The match log for the pause menu as BBCode (Marko 2026-11-01: who hit whom and much more was
## missing): a heading per turn, the phase before its first line, names in their team's colour,
## and for every line who did what to whom.
func log_bbcode() -> String:
	var out := PackedStringArray()
	var turn_at: int = -1
	var phase_at: String = ""
	var ctx: Dictionary = {}
	for e: Dictionary in state.log:
		var line: String = _log_line(e, ctx)
		if line.is_empty():
			continue
		var turn: int = JsonUtil.as_int(e.get("turn", 0))
		# The draw opens a turn (it is logged before the phase moves on).
		var phase: String = "start" if str(e.get("type", "")) == "draw" else _ribbon_phase(str(e.get("phase", "")))
		if turn != turn_at:
			turn_at = turn
			phase_at = ""
			out.append("")
			out.append("[font_size=22][color=#%s]%s[/color][/font_size]" % [Palette.GOLD.to_html(false), ("TURN %d" % turn) if turn > 0 else "SETUP"])
		if phase != phase_at and turn > 0 and str(e.get("type", "")) != "turn_end":
			phase_at = phase
			out.append("[font_size=13][color=#%s]%s[/color][/font_size]" % [Palette.MUTED.to_html(false), phase.to_upper()])
		out.append(line)
	return "\n".join(out).strip_edges()


func _who(slot: int) -> String:
	var p: PlayerState = state.player(slot)
	if p == null:
		return "?"
	return "[color=#%s]%s[/color]" % [Palette.team(state.team_of(slot)).lightened(0.35).to_html(false), _esc(player_name(slot))]


func _hero_b(id: String) -> String:
	var h: HeroState = state.hero(id)
	if h == null:
		return _esc(id)
	return "[b][color=#%s]%s[/color][/b]" % [Palette.team(state.team_of(h.owner)).lightened(0.35).to_html(false), _esc(hero_name(h))]


func _card_b(cid: String) -> String:
	# A colour, not italics: the UI font has no italic face.
	return "[color=#e9d8a6]%s[/color]" % _esc(_card_name(cid)) if not cid.is_empty() else ""


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _core_b(core_id: String) -> String:
	var c: CoreState = state.core(core_id)
	var card: CardDef = engine.catalog.get_card(c.card_id) if c != null else null
	return "a core (%s)" % _esc(card.name) if card != null else "a core"


## One log line; `ctx` carries what earlier lines said (the activated heroes for Roll / Stay).
func _log_line(e: Dictionary, ctx: Dictionary) -> String:
	var t: String = str(e.get("type", ""))
	var hero: String = str(e.get("hero", ""))
	var slot: int = JsonUtil.as_int(e.get("player", -1), -1)
	var dot: String = "[color=#%s]•[/color] " % Palette.DIM.to_html(false)
	match t:
		"match_start":
			return dot + "Match starts. %s goes first." % _who(JsonUtil.as_int(e.get("initiative", 0)))
		"stage_placed":
			var st: StageState = state.stage(str(e.get("stage", "")))
			return dot + "%s places a stage." % _who(st.owner) if st != null else ""
		"core_placed":
			var cp: CoreState = state.core(str(e.get("core", "")))
			return dot + "%s places a core." % _who(cp.owner) if cp != null else ""
		"mulligan":
			return dot + "%s takes a new hand." % _who(slot)
		"activated":
			var act: Dictionary = JsonUtil.as_dict(e.get("heroes", {}))
			ctx["active"] = act
			return ""
		"choices":
			var act2: Dictionary = JsonUtil.as_dict(ctx.get("active", {}))
			var parts := PackedStringArray()
			var roll: Dictionary = JsonUtil.as_dict(e.get("roll", {}))
			for k: Variant in act2:
				var rolls: bool = JsonUtil.as_bool(roll.get(k, roll.get(str(k), true)))
				parts.append("%s activates %s, who %s" % [_who(str(k).to_int()), _hero_b(str(act2[k])), "rolls" if rolls else "stays"])
			return dot + ". ".join(parts) + "." if not parts.is_empty() else ""
		"draw":
			return dot + "Everyone draws a card and gets energy."
		"rolled":
			var moved := PackedStringArray()
			for id: String in JsonUtil.as_strings(e.get("moved", [])):
				moved.append(_hero_b(id))
			return dot + "The balls stop. Moved: %s." % ", ".join(moved) if not moved.is_empty() else dot + "The balls stop."
		"roll_retry":
			return dot + "%s did not leave the start strip and throws again." % _hero_b(hero)
		"roll_again":
			return dot + "%s rolls again." % _hero_b(hero)
		"reverse_roll":
			return dot + "%s goes back to where it stood." % _hero_b(hero)
		"moved":
			return dot + "%s moves." % _hero_b(hero)
		"swapped":
			return dot + "%s and %s swap places." % [_hero_b(hero), _hero_b(str(e.get("with", "")))]
		"knockback":
			var steps: int = JsonUtil.as_int(e.get("steps", 0))
			return dot + "%s is knocked back %d hex%s." % [_hero_b(hero), steps, "" if steps == 1 else "es"] if steps > 0 else ""
		"ring_out":
			return dot + "[color=#%s]RING-OUT[/color]: %s leaves the arena." % [Palette.GOLD.to_html(false), _hero_b(hero)]
		"stage_revealed":
			var sr: StageState = state.stage(str(e.get("stage", "")))
			var card: CardDef = engine.catalog.get_card(sr.card_id) if sr != null else null
			var terrain: String = Terrain.name_of(card.terrain) if card != null and card.terrain != Terrain.Type.NONE else ""
			var by: String = str(e.get("by", ""))
			return dot + "%s turns %s face up%s." % [_hero_b(by) if not by.is_empty() else "A hero", _card_b(sr.card_id if sr != null else ""), (" (%s)" % terrain) if not terrain.is_empty() else ""]
		"stage_buff":
			return dot + _esc(_describe(e)) + "."
		"stage_stay":
			var ss: StageState = state.stage(str(e.get("stage", "")))
			return dot + "%s stays on %s." % [_hero_b(hero), _card_b(ss.card_id if ss != null else "")]
		"stage_claimed":
			var sc: StageState = state.stage(str(e.get("stage", "")))
			return dot + "[color=#%s]STAGE CLAIMED[/color]: %s takes %s." % [Palette.GOLD.to_html(false), _who(slot), _card_b(sc.card_id if sc != null else "")]
		"claim_blocked":
			var sb2: StageState = state.stage(str(e.get("stage", "")))
			return dot + "%s cannot claim %s this turn." % [_who(slot), _card_b(sb2.card_id if sb2 != null else "")]
		"stage_energy":
			var se2: StageState = state.stage(str(e.get("stage", "")))
			var wasted: int = JsonUtil.as_int(e.get("wasted", 0))
			return dot + "%s puts %d energy into %s: %d of %d%s." % [_who(slot), JsonUtil.as_int(e.get("amount", 0)),
				_card_b(se2.card_id if se2 != null else ""), JsonUtil.as_int(e.get("progress", 0)), JsonUtil.as_int(e.get("goal", 0)),
				(" (%d over the goal is lost)" % wasted) if wasted > 0 else ""]
		"stage_knocked_off":
			var so2: StageState = state.stage(str(e.get("stage", "")))
			var lost2: int = JsonUtil.as_int(e.get("lost", 0))
			if lost2 <= 0:
				return dot + "%s is knocked off %s." % [_hero_b(hero), _card_b(so2.card_id if so2 != null else "")]
			return dot + "%s is knocked off %s: %s loses [color=#%s]%d energy[/color] there, %d of %d left." % [_hero_b(hero),
				_card_b(so2.card_id if so2 != null else ""), _who(slot), Palette.ACCENT.to_html(false), lost2,
				JsonUtil.as_int(e.get("progress", 0)), JsonUtil.as_int(e.get("goal", 0))]
		"stage_contested":
			var sct2: StageState = state.stage(str(e.get("stage", "")))
			return dot + "%s is contested: heroes of both sides stand on it, so no energy goes in." % _card_b(sct2.card_id if sct2 != null else "")
		"core_activated":
			return dot + "%s picks up %s." % [_hero_b(hero), _core_b(str(e.get("core", "")))]
		"core_deactivated", "core_to_inventory":
			return dot + "%s puts down %s." % [_hero_b(hero), _core_b(str(e.get("core", "")))]
		"core_returned", "core_moved", "core_scattered":
			return dot + "%s goes back on the field." % _core_b(str(e.get("core", ""))).capitalize() if t == "core_returned" else ""
		"core_revealed":
			return dot + "%s is turned face up." % _core_b(str(e.get("core", ""))).capitalize()
		"core_trap":
			return dot + "%s walks into a core trap." % _hero_b(hero)
		"equipped", "evolved", "action":
			var h: HeroState = state.hero(hero)
			var verb: String = {"equipped": "equips", "evolved": "evolves", "action": "plays"}[t]
			if t == "action":
				return dot + "%s plays %s on %s." % [_who(h.owner) if h != null else "?", _card_b(str(e.get("card", ""))), _hero_b(hero)]
			if t == "evolved":
				return dot + "%s evolves into %s." % [_hero_b(hero), _card_b(str(e.get("card", "")))]
			return dot + "%s %s %s." % [_hero_b(hero), verb, _card_b(str(e.get("card", "")))]
		"assist":
			return dot + "Assist: %s." % _card_b(str(e.get("card", "")))
		"equipment_removed", "evolution_removed":
			return dot + "%s loses %s." % [_hero_b(hero), _card_b(str(e.get("card", "")))]
		"equipment_unfit":
			return dot + "%s drops %s (%s)." % [_hero_b(hero), _card_b(str(e.get("card", ""))), _esc(str(e.get("why", "")))]
		"ability":
			var an: String = _triggered_name(e)
			return dot + "%s uses %s." % [_hero_b(hero), ("[color=#e9d8a6]%s[/color]" % _esc(an)) if not an.is_empty() else _card_b(str(e.get("card", "")))]
		"triggered":
			var tn: String = _triggered_name(e)
			return dot + "%s: %s." % [_hero_b(hero), ("[color=#e9d8a6]%s[/color]" % _esc(tn)) if not tn.is_empty() else _card_b(str(e.get("card", "")))]
		"fx_buff":
			return ""
		"heal":
			return dot + "%s heals %d (HP %d)." % [_hero_b(hero), JsonUtil.as_int(e.get("amount", 0)), JsonUtil.as_int(e.get("hp", 0))]
		"energy":
			var n: int = JsonUtil.as_int(e.get("amount", 0))
			return dot + "%s %s %d energy (now %d)." % [_who(slot), "charges" if n >= 0 else "discharges", absi(n), JsonUtil.as_int(e.get("energy", 0))]
		"discard":
			return dot + "%s discards %s." % [_who(slot), _card_b(str(e.get("card", "")))]
		"recycled":
			return dot + "%s puts %s back into the deck." % [_who(slot), _card_b(str(e.get("card", "")))]
		"top_card":
			return dot + "%s shows %s (cost %d)." % [_who(slot), _card_b(str(e.get("card", ""))), JsonUtil.as_int(e.get("cost", 0))]
		"wall":
			return dot + "A wall goes up."
		"battle":
			var ids: PackedStringArray = JsonUtil.as_strings(e.get("heroes", []))
			if ids.is_empty():
				var bi: int = JsonUtil.as_int(e.get("index", -1), -1)
				if bi >= 0 and bi < state.battles.size():
					ids = JsonUtil.as_strings(state.battles[bi].get("heroes", []))
			var power: Dictionary = JsonUtil.as_dict(e.get("power", {}))
			var sides := PackedStringArray()
			var pw := [0, 0]
			for team: int in 2:
				var names := PackedStringArray()
				for id: String in ids:
					var bh: HeroState = state.hero(id)
					if bh != null and state.team_of(bh.owner) == team:
						names.append(_hero_b(id))
				for k: Variant in power:
					if str(k) == str(team):
						pw[team] = JsonUtil.as_int(power[k])
				sides.append("%s (%d)" % [" + ".join(names), pw[team]])
			var result: String = "tie" if pw[0] == pw[1] else ("%s wins" % ("left" if pw[0] > pw[1] else "right"))
			if pw[0] != pw[1]:
				result = "[color=#%s]%s side wins[/color]" % [Palette.team(0 if pw[0] > pw[1] else 1).lightened(0.35).to_html(false), Palette.TEAM_NAMES[0 if pw[0] > pw[1] else 1]]
			return "[color=#%s]⚔ BATTLE[/color]: %s vs %s, %s." % [Palette.ACCENT.lightened(0.2).to_html(false), sides[0], sides[1], result]
		"battle_locked":
			return dot + "Tie: %s stay locked and fight again next turn." % _esc(_heroes_line(e))
		"battle_tie_break":
			return dot + "Second tie: %s are both knocked back." % _esc(_heroes_line(e))
		"hit_wasted":
			var down := PackedStringArray()
			for id: String in JsonUtil.as_strings(e.get("targets", [])):
				down.append(_hero_b(id))
			return dot + "%s's hit finds %s already down." % [_hero_b(hero), " and ".join(down)]
		"out_of_reach":
			var far := PackedStringArray()
			for id: String in JsonUtil.as_strings(e.get("losers", [])):
				far.append(_hero_b(id))
			return dot + "%s can't reach %s: no hit." % [_hero_b(hero), " or ".join(far)]
		"combo":
			var names := PackedStringArray()
			for c: String in JsonUtil.as_strings(e.get("cards", [])):
				names.append(_card_b(c))
			return dot + "%s turns %s into %s (+%d Energy)." % [_who(JsonUtil.as_int(e.get("player", 0))), " and ".join(names), _card_b(str(e.get("combo", ""))), JsonUtil.as_int(e.get("extra", 0))]
		"hit_held", "hold_hit":
			return dot + "%s holds the hit back for double knockback." % _hero_b(hero) if t == "hit_held" else ""
		"damage":
			var amount: int = JsonUtil.as_int(e.get("amount", 0))
			var hp: int = JsonUtil.as_int(e.get("hp", 0))
			var src: String = str(e.get("by", ""))
			var card_id: String = str(e.get("card", ""))
			var red: String = Palette.ACCENT.lightened(0.25).to_html(false)
			if amount <= 0:
				return dot + "%s takes no damage." % _hero_b(hero)
			var dmg: String = "[color=#%s]%d DMG[/color]" % [red, amount]
			if src == "wall":
				# Replays from before 2026-11-07 only: wall damage is gone.
				return dot + "%s hits a wall: %s (HP %d)." % [_hero_b(hero), dmg, hp]
			if src == "ring_out":
				return dot + "%s takes %s for the ring-out (HP %d)." % [_hero_b(hero), dmg, hp]
			if src == "trap":
				return dot + "The trap deals %s to %s (HP %d)." % [dmg, _hero_b(hero), hp]
			if not src.is_empty() and state.hero(src) != null:
				return dot + "%s hits %s for %s%s (HP %d)." % [_hero_b(src), _hero_b(hero), dmg, (" with %s" % _card_b(card_id)) if not card_id.is_empty() else "", hp]
			if not card_id.is_empty():
				return dot + "%s: %s takes %s (HP %d)." % [_card_b(card_id), _hero_b(hero), dmg, hp]
			return dot + "%s takes %s (HP %d)." % [_hero_b(hero), dmg, hp]
		"deck_damage":
			var amt: int = JsonUtil.as_int(e.get("amount", 0))
			var by2: String = str(e.get("by", ""))
			var hand: int = JsonUtil.as_int(e.get("from_hand", 0))
			var left: String = (", %d left" % JsonUtil.as_int(e.get("left", 0))) if e.has("left") else ""
			return dot + "%s takes %s to the deck%s%s%s." % [_who(slot), "[color=#%s]%d[/color]" % [Palette.ACCENT.lightened(0.25).to_html(false), amt],
				(" from %s" % _hero_b(by2)) if not by2.is_empty() and state.hero(by2) != null else "", left, (", %d from the hand" % hand) if hand > 0 else ""]
		"hand_damage":
			var by3: String = str(e.get("by", ""))
			var names := PackedStringArray()
			for cid: String in JsonUtil.as_strings(e.get("cards", [])):
				names.append(_card_b(cid))
			if by3 == "ring_out":
				return dot + "%s discards %s to shake off the ring-out." % [_who(slot), ", ".join(names)]
			return dot + "%s takes %s of %s hit on the hand: %s discarded." % [_who(slot),
				"[color=#%s]%d DMG[/color]" % [Palette.ACCENT.lightened(0.25).to_html(false), JsonUtil.as_int(e.get("amount", 0))],
				("%s's" % _hero_b(by3)) if not by3.is_empty() and state.hero(by3) != null else "the", ", ".join(names)]
		"deck_out":
			return dot + "[color=#%s]DECK-OUT[/color]: %s has no cards left." % [Palette.ACCENT.to_html(false), _who(slot)]
		"ko":
			return dot + "[color=#%s]KO[/color]: %s is knocked out." % [Palette.ACCENT.lightened(0.2).to_html(false), _hero_b(hero)]
		"roll_missed":
			return dot + "%s ran out of time to throw." % _who(slot)
		"surrender":
			return dot + "%s surrenders." % _who(slot)
		"fx_skipped":
			return dot + "%s does nothing: %s." % [_card_b(str(e.get("card", ""))), _esc(str(e.get("why", "")))]
		"turn_end":
			return ""
		"match_end":
			var w: int = JsonUtil.as_int(e.get("winner", -1), -1)
			var reasons: Dictionary = {"ko": "all heroes KO", "stages": "three stages", "stages_energy": "three stages each, more energy in the stages", "deckout": "deck-out", "surrender": "surrender", "draw": "draw"}
			var why: String = str(reasons.get(str(e.get("result", "")), str(e.get("result", ""))))
			return "[color=#%s]MATCH OVER[/color]: %s (%s)." % [Palette.GOLD.to_html(false), ("%s wins" % _who(w)) if w >= 0 else "draw", why]
	return ""


# --- end of the match ----------------------------------------------------------------

func _refresh_over() -> void:
	var was: bool = _over.visible
	_over.visible = state.is_over() and not replay and not end_hold
	if not _over.visible:
		_over_key = ""
		_end_anim_done = false
		return
	# Built once: a redraw with nothing new on it would start its moment again.
	var key: String = "%d|%s|%d|%s|%s|%s|%s|%d" % [state.winner, state.result, state.turn, str(local_slots), rematch_text, series_text,
		str(new_match), end_summary.size()]
	if was and key == _over_key:
		return
	_over_key = key
	_clear(_over_box)
	# A leftover choice under the end screen showed through it (playtest 2026-10-30).
	if _dialog != null:
		_dialog.visible = false
	var won: bool = state.winner >= 0 and local_slots.size() == 1 and local_slots.has(state.winner)
	var lost: bool = state.winner >= 0 and local_slots.size() == 1 and not local_slots.has(state.winner)
	var title: String = "DRAW"
	if won:
		title = "VICTORY"
	elif lost:
		title = "DEFEAT"
	elif state.winner >= 0:
		title = "%s WINS" % player_name(state.winner).to_upper()
	# The end as a story (Marko 2026-11-08, mockup D): the sentence that ended it, both sides at a
	# glance with their stages, how the match went, the buttons.
	var head: Label = UiTheme.label(title, 88, Palette.GOLD if won else (Color("e3473f") if lost else Palette.FG))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_color_override("font_outline_color", Color.BLACK)
	head.add_theme_constant_override("outline_size", 12)
	_over_box.add_child(head)
	# The end told as a moment (item 31): S1 stages and K2 KO (Marko 2026-11-10), E1 more energy, D1 the same
	# energy and W2 a surrender (2026-11-11); a draw of two wins at once stays in words.
	if not end_moment_kind(state.result, state.winner, not _last_event("tie_broken").is_empty()).is_empty():
		_end_anim(was)
	else:
		var story: Label = UiTheme.label(end_sentence(), 24, Palette.FG, false)
		story.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		story.custom_minimum_size.x = 900
		_over_box.add_child(story)
		var turn_l: Label = UiTheme.label("TURN %d" % state.turn, 16, Palette.MUTED)
		turn_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_over_box.add_child(turn_l)
	_over_box.add_child(_end_sides())
	if not JsonUtil.as_array(end_summary.get("curve", [])).is_empty():
		_over_box.add_child(_end_curve())
	if not series_text.is_empty():
		_over_box.add_child(UiTheme.label(series_text, 26, Palette.GOLD))
	if rematch_text.is_empty():
		var wait := Label.new()
		wait.add_theme_color_override("font_color", Palette.MUTED)
		wait.text = "The host can take everyone back to the lobby."
		_over_box.add_child(wait)
	_over_box.add_child(_end_buttons())
	if not was:
		_over_box.modulate.a = 0.0
		_over_box.scale = Vector2(1.08, 1.08)
		var t: Tween = _over_box.create_tween().set_parallel(true)
		t.tween_property(_over_box, "modulate:a", 1.0, 0.25)
		t.tween_property(_over_box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The end as a moment (item 31, Marko 2026-11-10): S1 for stages, K2 for a KO (K1 when the last blow had
## no hero behind it). It plays once: built again (a rematch vote, the series line) it shows how it ended,
## and a click or Enter finishes it.
func _end_anim(redraw: bool) -> void:
	var area := Control.new()
	area.custom_minimum_size = Vector2(900, 150)
	area.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over_box.add_child(area)
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(box)
	var t: Tween = null
	match end_moment_kind(state.result, state.winner, not _last_event("tie_broken").is_empty()):
		"stages":
			t = _end_anim_stages(box, state.winner)
		"ko":
			t = _end_anim_ko(box, state.winner)
		"energy":
			t = _end_anim_energy(box)
		"surrender":
			t = _end_anim_give_up(box, state.winner)
	if t == null:
		return
	_end_anim_tween = t
	t.finished.connect(func() -> void: _end_anim_done = true)
	if redraw or _end_anim_done:
		finish_end_anim()


## Which moment tells the end (item 31), or "" for words: the result, the winner (-1 a draw), and whether
## the energy put into stages decided it (a tie_broken event).
static func end_moment_kind(result: String, winner: int, energy_count: bool) -> String:
	if winner >= 0 and (result == "stages" or result == "ko" or result == "surrender"):
		return result
	if result == "stages_energy" or (result == "draw" and energy_count):
		return "energy"
	return ""


## The end screen's moment, at its end now.
func finish_end_anim() -> void:
	if _end_anim_tween != null and _end_anim_tween.is_valid() and _end_anim_tween.is_running():
		_end_anim_tween.custom_step(60.0)


func _end_face(hero: HeroState, size_: Vector2) -> HeroSlice:
	var f := HeroSlice.new()
	var tex: Texture2D = db.thumb(engine.stat_card(hero).id)
	f.art = tex
	f.art_region = HeroSlice.region_for(tex)
	f.art_w = PlayerCard.ALL_PICTURE
	f.bg = Color(0, 0, 0, 0)
	f.outline = Color.BLACK
	f.outline_width = 2.5
	f.size = size_
	f.pivot_offset = size_ * 0.5
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return f


func _end_stage_pic(st: StageState, size_: Vector2, team: int) -> HeroSlice:
	var pic := HeroSlice.new()
	pic.art = db.thumb(st.card_id)
	pic.art_region = Rect2(0.115, 0.125, 0.77, 0.37)
	pic.art_w = PlayerCard.ALL_PICTURE
	pic.color_edge = Palette.team(team)
	pic.size = size_
	pic.pivot_offset = size_ * 0.5
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pic


func _end_label(parent: Control, text: String, font_size: int, color: Color, y: float, x: float = 0.0, w: float = 900.0) -> Label:
	var l: Label = UiTheme.label(text, font_size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(x, y)
	l.size = Vector2(w, font_size + 10.0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


## The winner's claimed stages, the one that decided it last.
func _end_claimed(winner: int) -> Array[StageState]:
	var out: Array[StageState] = []
	for st: StageState in state.stages:
		if st.is_claimed() and state.team_of(st.claimed_by) == state.team_of(winner):
			out.append(st)
	var last: StageState = state.stage(str(_last_event("stage_claimed").get("stage", "")))
	if last != null and out.has(last):
		out.erase(last)
		out.append(last)
	return out


## A white flash over the moment and a short jolt of it.
func _end_impact(box: Control) -> void:
	var fl := ColorRect.new()
	fl.color = Color(1, 1, 1, 0.85)
	fl.position = Vector2(-60, -10)
	fl.size = Vector2(1020, 170)
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(fl)
	var t: Tween = fl.create_tween()
	t.tween_property(fl, "modulate:a", 0.0, 0.22)
	t.tween_callback(fl.queue_free)
	var s: Tween = box.create_tween()
	var offs: Array[Vector2] = [Vector2(10, -6), Vector2(-8, 5), Vector2(5, -3), Vector2(-2, 2), Vector2.ZERO]
	for off: Vector2 in offs:
		s.tween_property(box, "position", off, 0.035)


## S1: the stage that decided it first, big ("THIRD STAGE CLAIMED · TURN n"); then it takes its place in the
## row of all of them, the others coming in from the left ("3 STAGES CLAIMED · TURN n").
func _end_anim_stages(box: Control, winner: int) -> Tween:
	var team: int = state.team_of(winner)
	var stages: Array[StageState] = _end_claimed(winner)
	var n: int = stages.size()
	if n == 0:
		return null
	var last: StageState = stages[n - 1]
	var nth: String = ["FIRST", "SECOND", "THIRD", "FOURTH", "FIFTH"][clampi(n - 1, 0, 4)]
	var slot := Vector2(220, 74)
	var gap: float = 20.0
	var x0: float = (900.0 - (slot.x * n + gap * (n - 1))) * 0.5
	var y: float = 36.0
	var head: Label = _end_label(box, "%s STAGE CLAIMED  ·  TURN %d" % [nth, state.turn], 17, Palette.GOLD, 2.0)
	head.modulate.a = 0.0
	var big := Vector2(312, 105)
	var pic: HeroSlice = _end_stage_pic(last, big, team)
	pic.position = Vector2(450.0 - big.x * 0.5, y)
	pic.scale = Vector2.ONE * 1.7
	pic.modulate.a = 0.0
	box.add_child(pic)
	var big_name: Label = _end_label(box, _card_name(last.card_id).to_upper(), 30, Palette.FG, y + big.y - 46.0)
	big_name.add_theme_color_override("font_outline_color", Color.BLACK)
	big_name.add_theme_constant_override("outline_size", 9)
	big_name.modulate.a = 0.0
	var others: Array[HeroSlice] = []
	var names: Array[Label] = []
	for i: int in n:
		var at := Vector2(x0 + i * (slot.x + gap), y + 4.0)
		var nm: Label = _end_label(box, _card_name(stages[i].card_id).to_upper(), 15, Palette.FG, at.y + slot.y + 4.0, at.x, slot.x)
		nm.modulate.a = 0.0
		names.append(nm)
		if i < n - 1:
			var p: HeroSlice = _end_stage_pic(stages[i], slot, team)
			p.position = at - Vector2(260, 0)
			p.modulate.a = 0.0
			box.add_child(p)
			others.append(p)
	var t: Tween = box.create_tween()
	t.tween_interval(0.5)
	t.tween_property(pic, "modulate:a", 1.0, 0.06)
	t.parallel().tween_property(pic, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(_end_impact.bind(box))
	t.tween_property(pic, "scale", Vector2.ONE * 1.05, 0.05)
	t.parallel().tween_property(head, "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(big_name, "modulate:a", 1.0, 0.12)
	t.tween_property(pic, "scale", Vector2.ONE, 0.08)
	t.tween_interval(1.3)
	t.tween_property(big_name, "modulate:a", 0.0, 0.12)
	t.tween_callback(func() -> void: head.text = "%d STAGES CLAIMED  ·  TURN %d" % [n, state.turn])
	var end_at := Vector2(x0 + (n - 1) * (slot.x + gap), y + 4.0)
	t.tween_property(pic, "size", slot, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(pic, "position", end_at, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for i: int in others.size():
		t.parallel().tween_property(others[i], "position:x", x0 + i * (slot.x + gap), 0.32).set_delay(0.07 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(others[i], "modulate:a", 1.0, 0.2).set_delay(0.07 * i)
	for nm: Label in names:
		t.parallel().tween_property(nm, "modulate:a", 1.0, 0.2).set_delay(0.3)
	return t


## K1: the two parties face each other, run into each other, and only the winners are left.
func _end_anim_sides(box: Control, winner: int) -> Tween:
	var loser: int = engine.other_slot(state, winner)
	var face := Vector2(124, 76)
	var gap: float = 8.0
	var y: float = 44.0
	var wg := Control.new()
	var lg := Control.new()
	var lose_faces: Array[HeroSlice] = []
	var count: int = 0
	for hero: HeroState in state.heroes_of(winner):
		var f: HeroSlice = _end_face(hero, face)
		f.position = Vector2(count * (face.x + gap), 0)
		wg.add_child(f)
		count += 1
	var gw: float = face.x * count + gap * (count - 1)
	var lcount: int = 0
	for hero: HeroState in state.heroes_of(loser):
		var f: HeroSlice = _end_face(hero, face)
		f.position = Vector2(lcount * (face.x + gap), 0)
		lg.add_child(f)
		lose_faces.append(f)
		lcount += 1
	for g: Control in [wg, lg]:
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(g)
	wg.position = Vector2(-gw - 60.0, y)
	lg.position = Vector2(960.0, y)
	var vs: Label = _end_label(box, "VS", 48, Palette.GOLD, y + 6.0)
	vs.add_theme_color_override("font_outline_color", Color.BLACK)
	vs.add_theme_constant_override("outline_size", 10)
	vs.modulate.a = 0.0
	var head: Label = _end_label(box, "EVERY HERO OF %s IS DOWN  ·  TURN %d" % [player_name(loser).to_upper(), state.turn], 17, Palette.GOLD, 4.0)
	head.modulate.a = 0.0
	var wx: float = 450.0 - 46.0 - gw
	var lx: float = 450.0 + 46.0
	var t: Tween = box.create_tween()
	t.tween_interval(0.5)
	t.tween_property(wg, "position:x", wx, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(lg, "position:x", lx, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(vs, "modulate:a", 1.0, 0.2)
	t.tween_interval(0.95)
	t.tween_property(wg, "position:x", wx - 36.0, 0.16)
	t.parallel().tween_property(lg, "position:x", lx + 36.0, 0.16)
	t.tween_property(wg, "position:x", 450.0 - gw + 8.0, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(lg, "position:x", 450.0 - 8.0, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		vs.visible = false
		_end_impact(box)
		var dy: Array[float] = [90.0, -80.0, 130.0]
		var rot: Array[float] = [0.5, -0.45, 0.8]
		for i: int in lose_faces.size():
			var f: HeroSlice = lose_faces[i]
			var st: Tween = f.create_tween().set_parallel(true)
			st.tween_property(f, "position", f.position + Vector2(240.0 + 70.0 * i, dy[i % 3]), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			st.tween_property(f, "rotation", rot[i % 3], 0.6)
			st.tween_property(f, "modulate", Color(0.45, 0.45, 0.45, 0.0), 0.6))
	t.tween_interval(0.35)
	t.tween_property(wg, "position:x", 450.0 - gw * 0.5, 0.36).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(head, "modulate:a", 1.0, 0.25)
	return t


## K2: the last hit. The hitter and the last hero run into each other ("X HITS Y FOR n"), the loser is
## stamped KNOCKED OUT and drops, and the hitter's own side gathers round it ("EVERY HERO OF <player> IS
## DOWN"). With Evil Bochet his claws come up from under the strip, take the fallen face and pull it down (Z1).
func _end_anim_ko(box: Control, winner: int) -> Tween:
	var loser: int = engine.other_slot(state, winner)
	var ko: Dictionary = _last_event("ko")
	var hero: HeroState = state.hero(str(ko.get("hero", "")))
	var hit: Dictionary = _last_event("damage", str(ko.get("hero", "")))
	var by: HeroState = state.hero(str(hit.get("by", "")))
	if hero == null or by == null:
		return _end_anim_sides(box, winner)
	var big := Vector2(210, 104)
	var y: float = 36.0
	var a: HeroSlice = _end_face(by, big)
	var b: HeroSlice = _end_face(hero, big)
	a.position = Vector2(-280.0, y)
	b.position = Vector2(960.0, y)
	box.add_child(a)
	box.add_child(b)
	var vs: Label = _end_label(box, "VS", 48, Palette.GOLD, y + 22.0)
	vs.add_theme_color_override("font_outline_color", Color.BLACK)
	vs.add_theme_constant_override("outline_size", 10)
	vs.modulate.a = 0.0
	var head: Label = _end_label(box, "%s HITS %s FOR %d  ·  TURN %d" % [hero_name(by).to_upper(), hero_name(hero).to_upper(),
		JsonUtil.as_int(hit.get("amount", 0)), state.turn], 17, Palette.GOLD, 4.0)
	head.modulate.a = 0.0
	var stamp: UiShape = UiShape.chip("KNOCKED OUT", Palette.ACCENT, Palette.FG, 26, 38.0, 12.0)
	stamp.outline = Color.BLACK
	stamp.outline_width = 2.5
	stamp.pivot_offset = stamp.custom_minimum_size * 0.5
	stamp.rotation_degrees = -8.0
	stamp.size = stamp.custom_minimum_size
	var clash_b: float = 450.0 - 8.0
	stamp.position = Vector2(clash_b + big.x * 0.5, y + big.y * 0.5) - stamp.custom_minimum_size * 0.5
	stamp.scale = Vector2.ONE * 2.4
	stamp.modulate.a = 0.0
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stamp)
	# The winners' row the hitter ends in.
	var face := Vector2(124, 76)
	var gap: float = 8.0
	var party: Array[HeroState] = [by]
	for x: HeroState in state.heroes_of(winner):
		if x != by:
			party.append(x)
	var gw: float = face.x * party.size() + gap * (party.size() - 1)
	var rx: float = 450.0 - gw * 0.5
	var ry: float = y + 12.0
	var rest: Array[HeroSlice] = []
	for i: int in range(1, party.size()):
		var f: HeroSlice = _end_face(party[i], face)
		f.position = Vector2(rx + i * (face.x + gap) + 320.0, ry)
		f.modulate.a = 0.0
		box.add_child(f)
		rest.append(f)
	var ax: float = 450.0 - 50.0 - big.x
	var bx: float = 450.0 + 50.0
	var t: Tween = box.create_tween()
	t.tween_interval(0.5)
	t.tween_property(a, "position:x", ax, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(b, "position:x", bx, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(vs, "modulate:a", 1.0, 0.2)
	t.tween_interval(0.85)
	t.tween_property(a, "position:x", ax - 36.0, 0.16)
	t.parallel().tween_property(b, "position:x", bx + 36.0, 0.16)
	t.tween_property(a, "position:x", 450.0 - big.x + 8.0, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(b, "position:x", clash_b, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		vs.visible = false
		_end_impact(box))
	t.tween_property(stamp, "modulate:a", 1.0, 0.04).set_delay(0.12)
	t.parallel().tween_property(stamp, "scale", Vector2.ONE, 0.13).set_delay(0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(b, "modulate", Color(0.5, 0.5, 0.5, 1.0), 0.2).set_delay(0.12)
	t.parallel().tween_property(head, "modulate:a", 1.0, 0.2)
	var hand: Node2D = null
	if bochet:
		# Evil Bochet takes the fallen one: claws up from under the strip, onto the face, and down with it.
		var clipc := Control.new()
		clipc.clip_contents = true
		clipc.position = Vector2(-120, -20)
		clipc.size = Vector2(1140, 196)
		clipc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(clipc)
		hand = Node2D.new()
		hand.scale = Vector2.ONE * 0.44
		var hx: float = clash_b + big.x * 0.5 + 120.0
		var grip_y: float = y + big.y + 44.0 + 20.0
		hand.position = Vector2(hx, grip_y + 190.0)
		clipc.add_child(hand)
		_claws_2d(hand)
		t.tween_interval(0.55)
		t.tween_property(hand, "position:y", grip_y, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(b, "rotation_degrees", 4.0, 0.06)
		t.tween_interval(0.26)
	else:
		t.tween_interval(1.0)
	t.tween_property(b, "position:y", y + 150.0, 0.4 if hand == null else 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if hand != null:
		t.parallel().tween_property(hand, "position:y", hand.position.y + 10.0, 0.36).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(stamp, "position:y", stamp.position.y + 150.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(b, "modulate:a", 0.0, 0.4)
	t.parallel().tween_property(stamp, "modulate:a", 0.0, 0.4)
	t.tween_callback(func() -> void: head.text = "EVERY HERO OF %s IS DOWN  ·  TURN %d" % [player_name(loser).to_upper(), state.turn])
	t.tween_property(a, "size", face, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(a, "position", Vector2(rx, ry), 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for i: int in rest.size():
		t.parallel().tween_property(rest[i], "position:x", rx + (i + 1) * (face.x + gap), 0.32).set_delay(0.07 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(rest[i], "modulate:a", 1.0, 0.2).set_delay(0.07 * i)
	return t


## The two sides of the end screen's moments: the viewer's first.
func _end_side_slot(side: int) -> int:
	var me: int = local_slots[0] if not local_slots.is_empty() else 0
	return me if side == 0 else engine.other_slot(state, me)


## E1 and D1 (Marko 2026-11-11): both sides reached their stages in the same End phase. Their claimed
## stages come in from the sides; under each, the energy it put into stages over the match counts up, both
## at the same pace, so the smaller one stops first; the bigger one strikes gold and the other side goes
## grey ("MORE ENERGY INTO STAGES · 61 TO 54"), or both stop together ("THE SAME ENERGY · NOBODY WINS").
func _end_anim_energy(box: Control) -> Tween:
	var totals: Dictionary = JsonUtil.as_dict(_last_event("tie_broken").get("totals", {}))
	var teams: Array[int] = [state.team_of(_end_side_slot(0)), state.team_of(_end_side_slot(1))]
	var vals: Array[int] = [JsonUtil.as_int(totals.get(str(teams[0]), 0)), JsonUtil.as_int(totals.get(str(teams[1]), 0))]
	var top: int = maxi(vals[0], vals[1])
	var n_claimed: int = 0
	var head: Label = _end_label(box, "", 17, Palette.GOLD, 2.0)
	head.modulate.a = 0.0
	var groups: Array[Control] = []
	var gx: Array[float] = []
	var names: Array[Label] = []
	for side: int in 2:
		var g := Control.new()
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(g)
		var sts: Array[StageState] = []
		for st: StageState in state.stages:
			if st.is_claimed() and state.team_of(st.claimed_by) == teams[side]:
				sts.append(st)
		n_claimed = maxi(n_claimed, sts.size())
		var sz := Vector2(128, 44)
		var w: float = sz.x * sts.size() + 8.0 * maxi(sts.size() - 1, 0)
		for i: int in sts.size():
			var p: HeroSlice = _end_stage_pic(sts[i], sz, teams[side])
			p.position = Vector2(i * (sz.x + 8.0), 0)
			g.add_child(p)
		var cx: float = 225.0 if side == 0 else 675.0
		gx.append(cx - w * 0.5)
		g.position = Vector2(gx[side] + (-560.0 if side == 0 else 560.0), 34.0)
		var who: Label = _end_label(g, player_name(_end_side_slot(side)).to_upper(), 14, Palette.team(clampi(teams[side], 0, 1)).lightened(0.3), -22.0, 0.0, maxf(w, 1.0))
		who.modulate.a = 0.0
		names.append(who)
		groups.append(g)
	head.text = "BOTH SIDES CLAIMED %d STAGES  ·  TURN %d" % [n_claimed, state.turn]
	var nums: Array[Label] = []
	for side: int in 2:
		var l: Label = _end_label(box, "0", 48, Palette.FG, 86.0, 0.0 if side == 0 else 450.0, 450.0)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 9)
		l.pivot_offset = l.size * 0.5
		l.modulate.a = 0.0
		nums.append(l)
	var cap: Label = _end_label(box, "ENERGY PUT INTO STAGES THIS MATCH", 13, Palette.MUTED, 146.0)
	cap.modulate.a = 0.0
	var t: Tween = box.create_tween()
	t.tween_interval(0.4)
	t.tween_property(groups[0], "position:x", gx[0], 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(groups[1], "position:x", gx[1], 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(_end_impact.bind(box))
	t.tween_property(head, "modulate:a", 1.0, 0.15)
	t.parallel().tween_property(names[0], "modulate:a", 1.0, 0.15)
	t.parallel().tween_property(names[1], "modulate:a", 1.0, 0.15)
	t.tween_interval(0.7)
	t.tween_property(nums[0], "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(nums[1], "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(cap, "modulate:a", 1.0, 0.2)
	t.tween_method(func(v: float) -> void:
		for side: int in 2:
			nums[side].text = str(roundi(minf(v, float(vals[side])))), 0.0, float(top), 1.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.3)
	if vals[0] == vals[1]:
		t.tween_callback(func() -> void:
			head.text = "THE SAME ENERGY  ·  %d EACH  ·  NOBODY WINS" % top
			_end_impact(box))
		t.tween_property(nums[0], "scale", Vector2.ONE * 1.25, 0.08)
		t.parallel().tween_property(nums[1], "scale", Vector2.ONE * 1.25, 0.08)
		t.tween_property(nums[0], "scale", Vector2.ONE, 0.14)
		t.parallel().tween_property(nums[1], "scale", Vector2.ONE, 0.14)
		return t
	var wi: int = 0 if vals[0] > vals[1] else 1
	var li: int = 1 - wi
	t.tween_callback(func() -> void:
		head.text = "MORE ENERGY INTO STAGES  ·  %d TO %d" % [vals[wi], vals[li]]
		nums[wi].add_theme_color_override("font_color", Palette.GOLD)
		_end_impact(box))
	t.tween_property(nums[wi], "scale", Vector2.ONE * 1.3, 0.08)
	t.tween_property(nums[wi], "scale", Vector2.ONE, 0.14)
	t.parallel().tween_property(groups[li], "modulate", Color(0.42, 0.42, 0.42, 1.0), 0.3)
	t.parallel().tween_property(nums[li], "modulate", Color(0.5, 0.5, 0.5, 1.0), 0.3)
	return t


## W2 (Marko 2026-11-11): the side that gave up stands in the middle ("<PLAYER> GIVES UP"); its heroes go
## grey one by one and lean, then drop ("<PLAYER> SURRENDERED"), and the winners take their place.
func _end_anim_give_up(box: Control, winner: int) -> Tween:
	var loser: int = engine.other_slot(state, winner)
	var face := Vector2(124, 76)
	var gap: float = 8.0
	var y: float = 44.0
	var grey := Color(0.45, 0.45, 0.45, 1.0)
	var lose_faces: Array[HeroSlice] = []
	var lg := Control.new()
	lg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lg)
	for hero: HeroState in state.heroes_of(loser):
		var f: HeroSlice = _end_face(hero, face)
		f.position = Vector2(lose_faces.size() * (face.x + gap), 0)
		if hero.is_ko():
			f.modulate = grey
		lg.add_child(f)
		lose_faces.append(f)
	var lw: float = face.x * lose_faces.size() + gap * maxi(lose_faces.size() - 1, 0)
	lg.position = Vector2(450.0 - lw * 0.5, y)
	lg.modulate.a = 0.0
	var wg := Control.new()
	wg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(wg)
	var count: int = 0
	for hero: HeroState in state.heroes_of(winner):
		var f: HeroSlice = _end_face(hero, face)
		f.position = Vector2(count * (face.x + gap), 0)
		if hero.is_ko():
			f.modulate = grey
		wg.add_child(f)
		count += 1
	var ww: float = face.x * count + gap * maxi(count - 1, 0)
	wg.position = Vector2(-ww - 80.0, y)
	wg.modulate.a = 0.0
	var head: Label = _end_label(box, "%s GIVES UP  ·  TURN %d" % [player_name(loser).to_upper(), state.turn], 17, Palette.GOLD, 4.0)
	head.modulate.a = 0.0
	var t: Tween = box.create_tween()
	t.tween_interval(0.4)
	t.tween_property(lg, "modulate:a", 1.0, 0.2)
	t.parallel().tween_property(head, "modulate:a", 1.0, 0.2)
	t.tween_interval(0.5)
	for i: int in lose_faces.size():
		var f: HeroSlice = lose_faces[i]
		t.tween_property(f, "modulate", grey, 0.16)
		t.parallel().tween_property(f, "rotation", 0.12 if i % 2 == 0 else -0.1, 0.16)
		t.tween_interval(0.12)
	t.tween_interval(0.35)
	t.tween_callback(func() -> void: head.text = "%s SURRENDERED  ·  TURN %d" % [player_name(loser).to_upper(), state.turn])
	for i: int in lose_faces.size():
		var f: HeroSlice = lose_faces[i]
		t.parallel().tween_property(f, "position:y", 150.0, 0.45).set_delay(0.06 * i).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(f, "modulate:a", 0.0, 0.45).set_delay(0.06 * i)
	t.tween_property(wg, "position:x", 450.0 - ww * 0.5, 0.36).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(wg, "modulate:a", 1.0, 0.2)
	return t


## How it ended, in words, from the last events of the log: the hit that knocked the last hero
## out, the stage claim that made three, a surrender; else the result's name.
func end_sentence() -> String:
	var winner: int = state.winner
	if winner < 0:
		if not _last_event("tie_broken").is_empty():
			return "Both sides reached their stages this turn with the same Energy put into stages over the match. Nobody wins."
		return "Both sides won in the same moment. Nobody wins."
	var w: String = player_name(winner)
	match state.result:
		"ko":
			var ko: Dictionary = _last_event("ko")
			var hero: HeroState = state.hero(str(ko.get("hero", "")))
			var hit: Dictionary = _last_event("damage", str(ko.get("hero", "")))
			var by: HeroState = state.hero(str(hit.get("by", "")))
			var loser: int = hero.owner if hero != null else engine.other_slot(state, winner)
			var how: String = ""
			if hero != null and by != null:
				# "with <card>" only for a card, not the hitter's own ability card.
				var card_id: String = str(hit.get("card", ""))
				var with: String = (" with %s" % _card_name(card_id)) if not card_id.is_empty() and card_id != by.card_id else ""
				how = "%s hits %s for %d%s: %s is KO" % [hero_name(by), hero_name(hero), JsonUtil.as_int(hit.get("amount", 0)), with, hero_name(hero)]
			elif hero != null:
				how = "%s is KO" % hero_name(hero)
			else:
				how = "The last hero falls"
			return "%s, and with that every hero of %s is down. %s wins." % [how, player_name(loser), w]
		"stages", "stages_energy":
			var claim: Dictionary = _last_event("stage_claimed")
			var st: StageState = state.stage(str(claim.get("stage", "")))
			var names := PackedStringArray()
			for s2: StageState in state.stages:
				if s2.is_claimed() and state.team_of(s2.claimed_by) == state.team_of(winner):
					names.append(_card_name(s2.card_id))
			var first: String = ""
			if st != null:
				var energy: int = JsonUtil.as_int(claim.get("energy", 0))
				var who: String = player_name(JsonUtil.as_int(claim.get("player", winner)))
				first = ("%s claims %s with %d Energy" % [who, _card_name(st.card_id), energy]) if energy > 0 else ("%s claims %s" % [who, _card_name(st.card_id)])
				first += ": the %s stage. " % ["first", "second", "third", "fourth", "fifth"][clampi(names.size() - 1, 0, 4)]
			if state.result == "stages_energy":
				return "%sBoth sides reached their stages this turn; %s put more Energy into stages over the match and wins." % [first, w]
			return "%s%s holds %s." % [first, w, " and ".join([", ".join(names.slice(0, names.size() - 1)), names[names.size() - 1]]) if names.size() > 1 else (names[0] if names.size() == 1 else "the stages")]
		"surrender":
			return "%s surrendered. %s wins." % [player_name(engine.other_slot(state, winner)), w]
	return "%s wins." % w


## The last log event of `type` (for `hero`, the last one about that hero), {} when none.
func _last_event(type: String, hero: String = "") -> Dictionary:
	for i: int in range(state.log.size() - 1, -1, -1):
		var e: Dictionary = state.log[i]
		if str(e.get("type", "")) == type and (hero.is_empty() or str(e.get("hero", "")) == hero):
			return e
	return {}


## Both sides, the viewer's first: name, stars for the stages claimed, each hero with its HP
## bar (KO grey); the winner's panel gold edged, the loser's dim.
func _end_sides() -> Control:
	var sides := HBoxContainer.new()
	sides.alignment = BoxContainer.ALIGNMENT_CENTER
	sides.add_theme_constant_override("separation", 24)
	var order: Array[int] = []
	for p: PlayerState in state.players:
		if local_slots.has(p.slot):
			order.append(p.slot)
	for p: PlayerState in state.players:
		if not order.has(p.slot):
			order.append(p.slot)
	for slot: int in order:
		var is_winner: bool = state.winner >= 0 and state.team_of(slot) == state.team_of(state.winner)
		var team_col: Color = Palette.team(state.team_of(slot))
		var panel := PanelContainer.new()
		var sb: StyleBoxFlat = UiTheme.box(Color(0.08, 0.08, 0.09, 0.96), 0, Color(0, 0, 0, 0), 18, 12)
		sb.border_color = Palette.GOLD if is_winner else Color(0.25, 0.25, 0.27)
		sb.set_border_width_all(3 if is_winner else 1)
		panel.add_theme_stylebox_override("panel", sb)
		panel.custom_minimum_size = Vector2(400, 0)
		panel.modulate = Color(1, 1, 1, 1.0 if is_winner or state.winner < 0 else 0.62)
		sides.add_child(panel)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		panel.add_child(col)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		col.add_child(head)
		head.add_child(UiTheme.label(player_name(slot).to_upper(), 24, team_col.lightened(0.2)))
		var stars := HBoxContainer.new()
		stars.add_theme_constant_override("separation", 2)
		stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stars.tooltip_text = "Stages claimed"
		var claimed: int = engine.claimed_count(state, slot)
		for i: int in state.settings.stages_to_win:
			var star: UiShape = UiShape.make(UiShape.Kind.STAR, Palette.GOLD if i < claimed else Color(0, 0, 0, 0), Vector2(18, 18))
			if i >= claimed:
				star.outline = Palette.DIM
				star.outline_width = 1.5
			stars.add_child(star)
		head.add_child(stars)
		for h: HeroState in state.heroes_of(slot):
			var card: CardDef = engine.stat_card(h)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			col.add_child(row)
			var s := HeroSlice.new()
			s.art = db.thumb(card.id) if db != null and card != null else null
			s.art_region = HeroSlice.region_for(s.art)
			s.art_fallback = Palette.hero(card.color if card != null else "")
			s.art_w = 80.0
			s.custom_minimum_size = Vector2(98, 46)
			s.color_edge = Palette.hero(card.color if card != null else "")
			if h.is_ko():
				s.art_tint = Color(0.3, 0.3, 0.3)
			s.tooltip_text = "%s · %s" % [hero_name(h), "KO" if h.is_ko() else "HP %d" % h.hp]
			row.add_child(s)
			var info := VBoxContainer.new()
			info.add_theme_constant_override("separation", 2)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			var nl := HBoxContainer.new()
			nl.add_child(UiTheme.label(hero_name(h), 17))
			var sp := Control.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			nl.add_child(sp)
			var max_hp: int = engine.max_hp(state, h)
			nl.add_child(UiTheme.label("KO" if h.is_ko() else "%d/%d" % [h.hp, max_hp], 13, Palette.ACCENT if h.is_ko() else Palette.MUTED))
			info.add_child(nl)
			var bar := UiSegments.new()
			bar.value = h.hp
			bar.max_value = maxi(max_hp, 1)
			bar.color = Palette.HP if not h.is_ko() else Color(0.35, 0.35, 0.35)
			bar.custom_minimum_size = Vector2(0, 7)
			info.add_child(bar)
	return sides


## How the match went: each team's total HP by turn as a line in its colour, a star on the turn
## it claimed a stage (end_summary.curve, MatchRecord.turn_curve).
func _end_curve() -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiTheme.box(Color(0.08, 0.08, 0.09, 0.96), 0, Color(0.25, 0.25, 0.27), 18, 10))
	box.custom_minimum_size = Vector2(824, 0)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	box.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	head.add_child(UiTheme.label("HOW IT WENT", 12, Palette.GOLD))
	head.add_child(UiTheme.label("TEAM HP BY TURN  ·  ★ STAGE CLAIMED", 11, Palette.MUTED))
	var plot := Control.new()
	plot.custom_minimum_size = Vector2(0, 92)
	var curve: Array = JsonUtil.as_array(end_summary.get("curve", []))
	plot.draw.connect(func() -> void:
		var w: float = plot.size.x
		var h: float = plot.size.y
		var n: int = curve.size()
		if n < 1:
			return
		var top: float = 1.0
		for pv: Variant in curve:
			var hp: Dictionary = JsonUtil.as_dict(JsonUtil.as_dict(pv).get("hp", {}))
			for k: Variant in hp:
				top = maxf(top, JsonUtil.as_float(hp[k]))
		var xs: PackedFloat32Array = PackedFloat32Array()
		for i: int in n:
			xs.append((i * w / (n - 1)) if n > 1 else w * 0.5)
		for t: int in 2:
			var pts := PackedVector2Array()
			for i: int in n:
				var hp: Dictionary = JsonUtil.as_dict(JsonUtil.as_dict(curve[i]).get("hp", {}))
				var v: float = JsonUtil.as_float(hp.get(t, hp.get(str(t), 0)))
				pts.append(Vector2(xs[i], h - 8.0 - (h - 16.0) * v / top))
			if pts.size() > 1:
				plot.draw_polyline(pts, Palette.team(t), 3.0, true)
			for i: int in n:
				for m: Variant in JsonUtil.as_array(JsonUtil.as_dict(curve[i]).get("claimed", [])):
					if JsonUtil.as_int(m) == t:
						var p: Vector2 = pts[i]
						var star := PackedVector2Array()
						for k: int in 10:
							var ang: float = -PI * 0.5 + k * PI / 5.0
							var rr: float = 4.0 if k % 2 == 1 else 9.0
							star.append(p + Vector2(cos(ang), sin(ang)) * rr)
						plot.draw_colored_polygon(star, Palette.GOLD)
		var every: int = maxi(1, ceili(n / 12.0))
		for i: int in n:
			if i % every == 0:
				plot.draw_string(UiTheme.display_heavy(), Vector2(xs[i] - 4.0, h), str(JsonUtil.as_int(JsonUtil.as_dict(curve[i]).get("turn", i + 1))), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.DIM))
	col.add_child(plot)
	return box


func _end_buttons() -> Control:
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	if not rematch_text.is_empty():
		var again := Button.new()
		again.text = rematch_text.to_upper()
		again.theme_type_variation = &"Primary"
		again.add_theme_font_size_override("font_size", 26)
		again.pressed.connect(func() -> void: rematch_pressed.emit())
		buttons.add_child(again)
	if new_match:
		var fresh := Button.new()
		fresh.text = "NEW MATCH"
		fresh.tooltip_text = "Back to the setup: other decks, map or rules"
		fresh.add_theme_font_size_override("font_size", 20)
		fresh.pressed.connect(func() -> void: new_match_pressed.emit())
		buttons.add_child(fresh)
	var watch := Button.new()
	watch.text = "WATCH REPLAY"
	watch.add_theme_font_size_override("font_size", 20)
	watch.pressed.connect(func() -> void: watch_replay_pressed.emit())
	buttons.add_child(watch)
	var back := Button.new()
	back.text = "MENU"
	back.add_theme_font_size_override("font_size", 20)
	back.pressed.connect(func() -> void: menu_pressed.emit())
	buttons.add_child(back)
	var balance: Button = WebApp.link("BALANCE", "balance", "Win rates of heroes and cards from every match played.")
	balance.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buttons.add_child(balance)
	return buttons


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
	else:
		# The side choice is the game's plain grey button, smaller than KEEP (Marko 2026-11-13: it had an edge of its
		# own and was as big as KEEP); a shade lighter than elsewhere so it reads over the dimmed table (2026-11-09).
		b.add_theme_stylebox_override("normal", UiTheme.slant(Palette.BUTTON.lightened(0.1)))
		b.add_theme_font_size_override("font_size", 20)
		b.custom_minimum_size = Vector2(170, 44)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
		move_child(_ball_choice, _banner_layer.get_index())
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
				# The chosen option of the picked hero reads CONFIRM <HERO> and locks it in, as the
				# button bottom right does (Marko 2026-11-01).
				var must: bool = hero.zone == HeroState.ZONE_STRIP
				if str(picks.get(hero.owner, "")) == hero.id and (must or pick_rolls.get(hero.owner, true) == true) == want:
					hide_ball_choice(true)
					pick_confirmed.emit(hero.owner, hero.id, want)
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
	roll_b.theme_type_variation = &"Primary" if picked and rolls else &""
	stay_b.theme_type_variation = &"Primary" if picked and not rolls else &""
	var confirm: String = "CONFIRM %s" % hero_name(h).get_slice(",", 0).to_upper()
	roll_b.text = confirm if picked and rolls else "ROLL"
	stay_b.text = confirm if picked and not rolls else "STAY"
	# In the start zone a hero must roll: STAY is not offered at all.
	stay_b.visible = not must_roll
	_ball_choice.reset_size()
	_ball_choice.position = at - Vector2(_ball_choice.size.x * 0.5, 0)
	_ball_choice.visible = true


## Puts the Roll / Stay under `at` (their ball moved on the screen); nothing else changes.
func move_ball_choice(at: Vector2) -> void:
	if _ball_choice == null or not _ball_choice.visible:
		return
	_ball_choice.position = at - Vector2(_ball_choice.size.x * 0.5, 0)


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
	# Clear of the panel's bottom edge (Marko 2026-11-01: a 30 px card ran out of the panel;
	# 2026-11-02: 22 px still touched it).
	box.custom_minimum_size = Vector2(14, 19)
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
## shows it big), the deck right (a stack), each with its count. Hidden during setup.
func _refresh_piles() -> void:
	if _piles == null or state == null:
		return
	_clear(_piles)
	_clear(_grave_spot)
	var slot: int = hand_slot()
	if slot < 0 and not local_slots.is_empty():
		slot = local_slots[0]
	var p: PlayerState = state.player(slot) if slot >= 0 else null
	# Not while who starts is rolled or stages and cores are placed (Marko 2026-11-06): no cards yet.
	var setup: bool = intro_dice or state.phase == GameState.PHASE_SETUP_STAGES or state.phase == GameState.PHASE_SETUP_CORES
	# Nor behind the starting hand (Marko 2026-11-09): nothing to look at there yet.
	_piles.visible = p != null and not setup and not board_blocked()
	_grave_spot.visible = p != null and not setup and not board_blocked()
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
			# A landscape card (an evolution) stands upright, as in the hand (playtest 2026-11-07: it
			# lay across the pile): a quarter turn about its top left corner, moved back in.
			if tex.get_width() > tex.get_height():
				pic.stretch_mode = TextureRect.STRETCH_SCALE
				pic.size = Vector2(72, 50)
				pic.rotation = PI * 0.5
				pic.position = Vector2(53, 3)
			pic.modulate = Color(1, 1, 1, 0.7)
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(pic)
	var tab: UiShape = UiShape.chip(count, Color("141110"), Palette.FG, 12, 18.0, 6.0)
	tab.position = Vector2(-4, 66)
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tab)
	return box


## Whether the mouse is on the Roll / Stay under a ball.
## The hero whose Roll / Stay shows under its ball, "" when hidden.
func ball_choice_hero() -> String:
	return _choice_hero if _ball_choice != null and _ball_choice.visible else ""


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
			var b: MouseButton = (e as InputEventMouseButton).button_index
			overlay.accept_event()
			# The wheel scrolls the cards (playtest 2026-11-07: it closed the window and zoomed the map).
			if b == MOUSE_BUTTON_LEFT or b == MOUSE_BUTTON_RIGHT:
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
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(160, 224)
		cell.mouse_filter = Control.MOUSE_FILTER_PASS
		if card != null:
			cell.tooltip_text = _card_tip("%s\n%s" % [card.name, card.text])
		var pic := TextureRect.new()
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture = tex
		pic.size = Vector2(160, 224)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if tex != null and tex.get_width() > tex.get_height():
			# Upright, as in the hand.
			pic.stretch_mode = TextureRect.STRETCH_SCALE
			pic.size = Vector2(224, 160)
			pic.rotation = PI * 0.5
			pic.position = Vector2(160, 0)
		cell.add_child(pic)
		grid.add_child(cell)


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
## The stage strip on or off (key G, or its tab); kept in the settings.
## Folds or opens your own side's box, or the other side's (a click on its header).
func toggle_stage_strip(own: bool = true) -> void:
	GameSettings.set_value("display", "stage_strip" if own else "stage_strip_other", not GameSettings.stage_strip(own))
	refresh()


## Key G: both boxes together, to the opposite of your own.
func toggle_stage_strips() -> void:
	var open: bool = not GameSettings.stage_strip(true)
	GameSettings.set_value("display", "stage_strip", open)
	GameSettings.set_value("display", "stage_strip_other", open)
	refresh()


## A player's stages and cores in a box under its heroes (Marko 2026-11-02, mockup B): the
## stages as tiles with the name, and with energy claims that player's energy in each (a bar and
## "6/14"; "4 | 7" when the other side has some in it too); the cores as chips, placed ones
## full, face-down ones dashed, not-placed ones dim, a core on a hero with that hero's initial.
## The other side's cores show as far as the viewer knows them. The header folds the box (key G
## does too); folded, one line counts what is in it.
func _side_board(slot: int, right: bool) -> Control:
	var p: PlayerState = state.player(slot)
	var team_col: Color = Palette.team(state.team_of(slot))
	# The same slanted slice as a hero panel, as wide, with no art and the team's colour edge.
	var box := HeroSlice.new()
	box.set_mirrored(right)
	box.art_w = 0.0
	box.bg = Palette.PANEL_SOLID
	box.color_edge = team_col
	box.custom_minimum_size = Vector2(ROSTER_WIDTH, 40)
	# As wide as a hero panel and no wider: the column grows with an ability tab beside a panel.
	box.size_flags_horizontal = Control.SIZE_SHRINK_END if right else Control.SIZE_SHRINK_BEGIN
	# The slice leans on both sides: the top starts a cut in on the left, the bottom ends a cut
	# short on the right, so both margins keep the text (and the fold chevron) on the black.
	var cut: int = int(HeroSlice.CUT) + 8
	box.content.add_theme_constant_override("margin_left", cut)
	box.content.add_theme_constant_override("margin_right", cut)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.content.add_child(col)
	# The slice is a plain control: it takes its height from what is inside.
	# The box may be gone by the deferred call: a second refresh in the same frame rebuilds the column.
	var fit := func() -> void:
		if is_instance_valid(box):
			box.custom_minimum_size.y = box.content.get_combined_minimum_size().y
	box.content.minimum_size_changed.connect(fit)
	fit.call_deferred()
	var open: bool = GameSettings.stage_strip(local_slots.has(slot))
	var claimed: int = engine.claimed_count(state, slot)
	var mine: Array[StageState] = []
	for st: StageState in state.stages:
		if st.owner == slot:
			mine.append(st)
	var cores: Array[CoreState] = []
	for c: CoreState in state.cores:
		if c.owner == slot:
			cores.append(c)
	var placed: int = 0
	var known: int = 0
	var hidden: int = 0
	for c: CoreState in cores:
		if c.place != CoreState.UNPLACED:
			placed += 1
			if _core_known(c):
				known += 1
			else:
				hidden += 1
	var own: bool = local_slots.has(slot)
	var core_line: String
	if own:
		core_line = "%d PLACED · %d TO PLACE" % [placed, cores.size() - placed]
	else:
		core_line = "%d KNOWN · %d HIDDEN · %d TO PLACE" % [known, hidden, cores.size() - placed]
	# The header: a click folds or opens the box.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.layout_direction = Control.LAYOUT_DIRECTION_RTL if right else Control.LAYOUT_DIRECTION_LTR
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	head.tooltip_text = "Fold or open the stages and cores (key G)"
	head.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			head.accept_event()
			toggle_stage_strip(local_slots.has(slot)))
	var title: String = ("STAGES" if own else "%s STAGES" % player_name(slot).to_upper()) if open \
			else ("STAGES %d/%d · CORES %s" % [claimed, state.settings.stages_to_win, ("%d/%d" % [placed, cores.size()]) if own else ("%d KNOWN" % known)])
	head.add_child(UiTheme.label(title, 12, Palette.GOLD if own else Color(Palette.team(state.team_of(slot)), 0.9).lightened(0.3)))
	if open:
		head.add_child(UiTheme.label("CLAIMED %d/%d" % [claimed, state.settings.stages_to_win], 12, Palette.MUTED))
		if state.settings.energy_claims():
			# The goal once, small (Marko 2026-11-07), not on every tile.
			var goal_l: Label = UiTheme.label(("%d ENERGY CLAIMS A STAGE  ·" if right else "·  %d ENERGY CLAIMS A STAGE") % state.settings.stage_goal, 9, Palette.DIM)
			goal_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			head.add_child(goal_l)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	# The same gap from the team's colour edge on both sides, measured on the slant at the chevron's
	# own height (Marko 2026-11-08): the box leans away from a straight margin on one side and
	# towards it on the other. The header only keeps its place free.
	var chev_room := Control.new()
	chev_room.custom_minimum_size = FOLD_CHEVRON_SIZE
	chev_room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(chev_room)
	var chev: Control = _fold_chevron(open)
	box.add_child(chev)
	var place_chev := func() -> void:
		var inner: float = box.edge_inner_x(FOLD_CHEVRON_Y + FOLD_CHEVRON_SIZE.y * 0.5)
		chev.position = Vector2(inner + FOLD_CHEVRON_GAP - FOLD_CHEVRON_INK.x if right else inner - FOLD_CHEVRON_GAP - FOLD_CHEVRON_INK.y, FOLD_CHEVRON_Y)
	box.resized.connect(place_chev)
	col.add_child(head)
	if not open:
		return box
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 6)
	tiles.layout_direction = Control.LAYOUT_DIRECTION_RTL if right else Control.LAYOUT_DIRECTION_LTR
	tiles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(tiles)
	for st: StageState in mine:
		tiles.add_child(_board_stage(st, slot))
	if cores.is_empty():
		return box
	var chead := HBoxContainer.new()
	chead.add_theme_constant_override("separation", 8)
	chead.layout_direction = Control.LAYOUT_DIRECTION_RTL if right else Control.LAYOUT_DIRECTION_LTR
	chead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chead.add_child(UiTheme.label("CORES", 12, Palette.GOLD if own else Color(Palette.team(state.team_of(slot)), 0.9).lightened(0.3)))
	chead.add_child(UiTheme.label(core_line, 12, Palette.MUTED))
	col.add_child(chead)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 4)
	grid.layout_direction = Control.LAYOUT_DIRECTION_RTL if right else Control.LAYOUT_DIRECTION_LTR
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(grid)
	for c: CoreState in cores:
		grid.add_child(_board_core(c))
	return box


## Whether the viewer knows what core `c` is: its own, face up on the field, on a hero, or
## waiting in an inventory.
func _core_known(c: CoreState) -> bool:
	if local_slots.has(c.owner):
		return true
	return c.place == CoreState.ON_HERO or c.place == CoreState.IN_INVENTORY or (c.place == CoreState.ON_FIELD and c.face_up)


## A small drawn chevron: up while the box is open (click folds it), down while folded.
## A player's assists (Marko 2026-11-07, mockup 2c): under the stage box, the same slanted slice with
## the team's edge, as wide as its cards: each one's picture and name. Hovering one shows it big (a
## right click too, as on a hero panel).
func _assist_board(p: PlayerState, slot: int, right: bool) -> Control:
	var box := HeroSlice.new()
	box.set_mirrored(right)
	box.art_w = 0.0
	box.bg = Palette.PANEL_SOLID
	box.color_edge = Palette.team(state.team_of(slot))
	box.custom_minimum_size = Vector2(0, 40)
	box.size_flags_horizontal = Control.SIZE_SHRINK_END if right else Control.SIZE_SHRINK_BEGIN
	var cut: int = int(HeroSlice.CUT) + 8
	box.content.add_theme_constant_override("margin_left", cut)
	box.content.add_theme_constant_override("margin_right", cut)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.content.add_child(col)
	var fit := func() -> void: box.custom_minimum_size = box.content.get_combined_minimum_size()
	box.content.minimum_size_changed.connect(fit)
	fit.call_deferred()
	var own: bool = local_slots.has(slot)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.layout_direction = Control.LAYOUT_DIRECTION_RTL if right else Control.LAYOUT_DIRECTION_LTR
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(UiTheme.label("ASSISTS" if own else "%s ASSISTS" % player_name(slot).to_upper(), 12,
		Palette.GOLD if own else Color(Palette.team(state.team_of(slot)), 0.9).lightened(0.3)))
	head.add_child(UiTheme.label("%d/%d" % [p.assists.size(), state.settings.assist_limit], 12, Palette.MUTED))
	col.add_child(head)
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	cards.layout_direction = Control.LAYOUT_DIRECTION_RTL if right else Control.LAYOUT_DIRECTION_LTR
	cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(cards)
	for cid: String in p.assists:
		var card: CardDef = engine.catalog.get_card(cid)
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		cell.tooltip_text = _card_tip("%s\n%s" % [card.name, card.text]) if card != null else ""
		var tex: Texture2D = db.thumb(cid) if db != null else null
		if tex != null:
			var pic := TextureRect.new()
			pic.texture = tex
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_SCALE
			pic.custom_minimum_size = Vector2(30, 42)
			pic.material = round_corners()
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(pic)
		var name_l: Label = UiTheme.label(card.name if card != null else cid, 16, Palette.FG)
		name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(name_l)
		cell.mouse_entered.connect(func() -> void:
			_hover_cid = cid
			_show_big(cid))
		cell.mouse_exited.connect(func() -> void:
			if _hover_cid == cid:
				_hover_cid = ""
			if _big_cid == cid:
				_show_big(""))
		cell.gui_input.connect(func(e: InputEvent) -> void:
			_card_click(e, cid))
		cards.add_child(cell)
	return box


func _fold_chevron(open: bool) -> Control:
	var chev := Control.new()
	chev.custom_minimum_size = FOLD_CHEVRON_SIZE
	chev.size = FOLD_CHEVRON_SIZE
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chev.draw.connect(func() -> void:
		var pts := PackedVector2Array([Vector2(3, 10), Vector2(8, 5), Vector2(13, 10)] if open
			else [Vector2(3, 6), Vector2(8, 11), Vector2(13, 6)])
		chev.draw_polyline(pts, Palette.MUTED, 2.0, true))
	return chev


## One stage as a tile in its owner's box: the art, a band with the name (CLAIMED, HIDDEN) and,
## with energy claims, `slot`'s energy in it as a bar and a number.
## End phase, energy claims: where the energy went, said at the top and lit on the stage tiles
## for a few seconds ("+3 ENERGY INTO ONIGASHIMA · 9/14"), so one stage taking it all without
## a split box does not pass unnoticed.
func _energy_note(events: Array[Dictionary]) -> void:
	var until: int = Time.get_ticks_msec() + int(ENERGY_FLASH_MS * GameSettings.anim_scale())
	# What went where, per player in the order they banked.
	var order := PackedInt32Array()
	var owners := PackedInt32Array()
	var amounts := PackedInt32Array()
	var texts := PackedStringArray()
	for e: Dictionary in events:
		var st: StageState = state.stage(str(e.get("stage", "")))
		var amount: int = JsonUtil.as_int(e.get("amount", 0))
		var who: int = JsonUtil.as_int(e.get("player", -1), -1)
		var wasted: int = JsonUtil.as_int(e.get("wasted", 0))
		if st == null or (amount <= 0 and wasted <= 0):
			continue
		_energy_flash[st.id] = {"amount": amount, "player": who, "until": until, "start": Time.get_ticks_msec()}
		var known: bool = st.revealed or local_slots.has(st.owner)
		var text: String = "%s · %d/%d" % [_card_name(st.card_id) if known else "a hidden stage",
			JsonUtil.as_int(e.get("progress", 0)), JsonUtil.as_int(e.get("goal", 0))]
		if wasted > 0:
			text += " · %d lost" % wasted
		if not order.has(who):
			order.append(who)
		owners.append(who)
		amounts.append(amount)
		texts.append(text)
	if texts.is_empty():
		return
	# A band across the screen, short, in the player's colour (Marko 2026-11-09: the straw line
	# stood low over the table and was easy to miss). With bands off it is that line still.
	for who: int in order:
		var total: int = 0
		var rows := PackedStringArray()
		for i: int in texts.size():
			if owners[i] == who:
				total += amounts[i]
				rows.append(texts[i].to_upper())
		if GameSettings.banners() == "off":
			toast("%s +%d energy into %s" % [player_name(who), total, "   ·   ".join(rows)], Palette.team(state.team_of(who)), 2.6)
		else:
			banner("+%d ENERGY" % total, Palette.team(state.team_of(who)), player_name(who).to_upper(), "\n".join(rows), ENERGY_BANNER_TIME)
	# The tiles light up now and go back to normal by themselves.
	refresh.call_deferred()
	get_tree().create_timer(ENERGY_FLASH_MS * GameSettings.anim_scale() / 1000.0 + 0.05).timeout.connect(func() -> void:
		if state != null:
			refresh())


func _board_stage(st: StageState, slot: int) -> Control:
	var known: bool = st.revealed or local_slots.has(st.owner)
	var card: CardDef = engine.catalog.get_card(st.card_id) if known and not st.card_id.is_empty() else null
	var contested: bool = state.settings.energy_claims() and engine.contested(state, st)
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(96, 92)
	tile.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var flash: Dictionary = _energy_flash.get(st.id, {})
	var lit: bool = not flash.is_empty() and Time.get_ticks_msec() < JsonUtil.as_int(flash.get("until", 0))
	if not lit and not flash.is_empty():
		_energy_flash.erase(st.id)
	# A plain layer inside: the panel would stretch the band over the art.
	var inner := Control.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(inner)
	var tex: Texture2D = db.thumb(card.id) if card != null and db != null else null
	# The tile is its slanted picture, as the hero panels (Marko 2026-11-08, mockup 3), inside the
	# card's art frame so its dark corners stay out; the name and the energy stand under it. A state
	# is a thin edge along the slant (Marko 2026-11-08): breathing in the player's colour when energy
	# just went in, the claimer's when claimed (with CLAIMED on the picture), grey contested.
	var pic := HeroSlice.new()
	pic.art = tex
	pic.art_region = Rect2(0.115, 0.125, 0.77, 0.37)
	pic.art_w = 200.0
	pic.bg = Color(0, 0, 0, 0)
	pic.art_fallback = Palette.SURFACE_2
	pic.set_anchors_preset(Control.PRESET_TOP_WIDE)
	pic.offset_left = 2.0
	pic.offset_right = -2.0
	pic.offset_top = 2.0
	pic.offset_bottom = 58.0
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Yours but still face down: you know it, the table does not yet.
	if tex != null and not st.revealed:
		pic.art_tint = Color(1, 1, 1, 0.45)
	pic.outline_width = 1.5
	if lit:
		# A slow, calm pulse in the colour of whoever put the energy in (Marko 2026-11-08).
		var edge: Color = Palette.team(state.team_of(JsonUtil.as_int(flash.get("player", 0)))).lightened(0.15)
		pic.outline = edge
		var breathe := func(a: float) -> void:
			pic.outline = Color(edge, a)
			pic.queue_redraw()
		var pulse: Tween = pic.create_tween().set_loops()
		pulse.tween_method(breathe, 1.0, 0.4, ENERGY_PULSE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_method(breathe, 0.4, 1.0, ENERGY_PULSE_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	elif st.is_claimed():
		pic.outline = Palette.team(state.team_of(st.claimed_by))
	elif contested:
		pic.outline = Palette.DIM
	if st.id == table_stage:
		pic.outline = Palette.GOLD
		pic.outline_width = 3.0
	inner.add_child(pic)
	if st.is_claimed():
		var stamp: UiShape = UiShape.chip("CLAIMED", Palette.team(state.team_of(st.claimed_by)), Palette.FG, 16, 26.0, 9.0)
		stamp.position = Vector2(48, 30) - stamp.custom_minimum_size * 0.5
		stamp.pivot_offset = stamp.custom_minimum_size * 0.5
		stamp.rotation_degrees = -8.0
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(stamp)
	if tex == null:
		var q: Label = UiTheme.label("?", 26, Palette.DIM)
		q.set_anchors_preset(Control.PRESET_FULL_RECT)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pic.add_child(q)
	# The band along the bottom: the name, and the progress.
	var word: String = "HIDDEN" if not st.revealed and card != null else (card.name.to_upper() if card != null else "")
	var energy: bool = state.settings.energy_claims() and st.placed and not st.is_claimed() and card != null
	var other: int = -1
	for q: PlayerState in state.players:
		if q.slot != slot and st.progress_of(q.slot) > 0:
			other = q.slot
	if not word.is_empty() or energy:
		var band := PanelContainer.new()
		band.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		band.grow_vertical = Control.GROW_DIRECTION_BEGIN
		band.add_theme_stylebox_override("panel", UiTheme.box(Color(0, 0, 0, 0), 0, Color(0, 0, 0, 0), 3, 1))
		band.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(band)
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 1)
		rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(rows)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(line)
		var name_l: Label = UiTheme.label(word, 9, Palette.GOLD if st.is_claimed() else (Palette.DIM if contested else Palette.MUTED))
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.clip_text = true
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_child(name_l)
		# Stay claims: a hero that stayed here last turn claims it with one more Stay (Marko
		# 2026-11-02: ten stays and no claim, but never two in a row with the same hero).
		if not energy and st.placed and not st.is_claimed() and not st.stay_hero.is_empty() 				and st.stay_turn == state.turn - 1:
			var stayer: HeroState = state.hero(st.stay_hero)
			if stayer != null and state.heroes_on_stage(st).has(stayer):
				line.add_child(UiTheme.label("STAY 1/2", 10, Palette.team(state.team_of(stayer.owner)).lightened(0.45)))
		if energy:
			# Pips (Marko 2026-11-07, mockup 3): the blue team's energy fills from the left with its
			# number at that end, the red team's from the right with its number there; the goal is
			# said once in the box header. Grey while contested, the numbers stay in team colours.
			var goal: int = maxi(state.settings.stage_goal, 1)
			var sides: Array[int] = [-1, -1]
			for q: PlayerState in state.players:
				sides[clampi(state.team_of(q.slot), 0, 1)] = q.slot
			var row := HBoxContainer.new()
			row.layout_direction = Control.LAYOUT_DIRECTION_LTR
			row.add_theme_constant_override("separation", 2)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rows.add_child(row)
			var amounts: Array[int] = []
			for t: int in 2:
				amounts.append(st.progress_of(sides[t]) if sides[t] >= 0 else 0)
			var pips := HBoxContainer.new()
			pips.add_theme_constant_override("separation", 1)
			pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
			for t: int in 2:
				var n: Label = UiTheme.label(str(amounts[t]), 12, Palette.team(t).lightened(0.45))
				n.custom_minimum_size = Vector2(9, 0)
				n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if t == 1 else HORIZONTAL_ALIGNMENT_LEFT
				if t == 1:
					row.add_child(pips)
				row.add_child(n)
			for i: int in goal:
				var pip := ColorRect.new()
				pip.custom_minimum_size = Vector2(3, 8)
				pip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var c: Color = Color(0.22, 0.22, 0.22)
				if i < amounts[0]:
					c = Palette.team(0)
				elif i >= goal - amounts[1]:
					c = Palette.team(1)
				pip.color = c.darkened(0.5) if contested and c != Color(0.22, 0.22, 0.22) else c
				pips.add_child(pip)
	if lit:
		# Big and tilted in the middle, as CLAIMED (Marko 2026-11-08, from the mockups): pops up from
		# nothing, then floats off. Timed from the flash's start, the tiles are rebuilt on every refresh.
		var gain: UiShape = UiShape.chip("+%d" % JsonUtil.as_int(flash.get("amount", 0)),
			Palette.team(state.team_of(JsonUtil.as_int(flash.get("player", 0)))), Palette.FG, 24, 34.0, 11.0)
		var rest: Vector2 = Vector2(48, 30) - gain.custom_minimum_size * 0.5
		gain.position = rest
		gain.pivot_offset = gain.custom_minimum_size * 0.5
		gain.rotation_degrees = -8.0
		gain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(gain)
		var ticks: int = Time.get_ticks_msec()
		var age: float = (ticks - JsonUtil.as_int(flash.get("start", 0))) / 1000.0
		var left: float = (JsonUtil.as_int(flash.get("until", 0)) - ticks) / 1000.0
		var away: float = minf(ENERGY_GAIN_OUT, left)
		var moves: Tween = gain.create_tween()
		if age < ENERGY_GAIN_IN:
			gain.scale = Vector2.ONE * lerpf(0.2, 1.0, age / ENERGY_GAIN_IN)
			moves.tween_property(gain, "scale", Vector2.ONE, ENERGY_GAIN_IN - age).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		moves.tween_interval(maxf(left - away - maxf(ENERGY_GAIN_IN - age, 0.0), 0.0))
		# A refresh during the float carries on from where it was.
		var done: float = 1.0 - away / ENERGY_GAIN_OUT
		gain.position.y = rest.y - 22.0 * done
		gain.modulate.a = 1.0 - done
		moves.tween_property(gain, "position:y", rest.y - 22.0, away).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		moves.parallel().tween_property(gain, "modulate:a", 0.0, away)
	var whose: String = player_name(st.owner)
	if card != null:
		tile.tooltip_text = "%s (%s's stage%s)%s" % [card.name, whose, ", face down" if not st.revealed else "",
			("\n" + _card_tip(card.text)) if not _card_tip(card.text).is_empty() else ""]
	else:
		tile.tooltip_text = "%s's stage, face down until a hero stops on it" % whose
	if st.is_claimed():
		tile.tooltip_text += "\nClaimed by %s" % player_name(st.claimed_by)
	elif state.settings.energy_claims():
		if contested:
			tile.tooltip_text += "\nContested: heroes of both sides stand on it, no energy goes in"
		for p: PlayerState in state.players:
			if st.progress_of(p.slot) > 0:
				tile.tooltip_text += "\n%s: %d of %d energy" % [player_name(p.slot), st.progress_of(p.slot), state.settings.stage_goal]
	elif st.placed and not st.stay_hero.is_empty() and st.stay_turn == state.turn - 1:
		tile.tooltip_text += "\n%s stayed here last turn: one more Stay claims it" % _hero_label(st.stay_hero)
	# Not a ternary: its value is an untyped Array, which the typed parameter refuses.
	var hexes: Array[Vector2i] = []
	if st.placed:
		hexes = st.footprint()
	_board_hover(tile, hexes, card)
	return tile


## One core as a chip: what it does, in the look of where it is (not placed dim, face down on
## the field half, on a hero with that hero's initial by it); a core the viewer does not know
## is a "?" chip.
func _board_core(c: CoreState) -> Control:
	var known: bool = _core_known(c)
	var card: CardDef = engine.catalog.get_card(c.card_id) if known else null
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var chip: Control
	if known:
		chip = _core_slot(c.id, Palette.SURFACE_2, true)
	else:
		chip = UiShape.chip("?", Color("1b1f20"), Palette.MUTED, 10, 15.0, 3.0)
		chip.custom_minimum_size = Vector2(40, 15)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(chip)
	var where: String = ""
	var hexes: Array[Vector2i] = []
	match c.place:
		CoreState.ON_FIELD:
			where = "On the field, face up" if c.face_up else ("On the field, face down: only you know it" if known else "On the field, face down")
			if known or c.face_up:
				hexes.append(c.hex)
			if not c.face_up:
				chip.modulate = Color(1, 1, 1, 0.7)
		CoreState.ON_HERO:
			var h: HeroState = state.hero(c.holder)
			where = "On %s" % hero_name(h) if h != null else "On a hero"
			if h != null and h.is_on_map():
				hexes.append(h.hex)
			if h != null:
				var initial: UiShape = UiShape.chip(hero_name(h).left(1).to_upper(), Palette.team(state.team_of(h.owner)), Palette.FG, 8, 12.0, 2.0)
				initial.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
				box.add_child(initial)
		CoreState.IN_INVENTORY:
			where = "To put back on the field"
		_:
			where = "Not placed yet"
			chip.modulate = Color(1, 1, 1, 0.4)
	box.tooltip_text = "%s\n%s" % [card.name if card != null else "A core", where]
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
