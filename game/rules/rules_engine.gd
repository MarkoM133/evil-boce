class_name RulesEngine
extends RefCounted
## Applies moves and roll outcomes to a GameState. Pure logic: no scene, no physics, no
## randomness outside the state's own RNG. Every public call returns "" or an error message
## and never changes the state when it fails. Assumptions the GDD leaves open are listed in
## docs/rules.md.

const DECISION_DAMAGE: String = "damage"
## What a ring-out costs (Marko 2026-11-07): 1 DMG, or a card from the hand instead.
const RING_OUT_DAMAGE: int = 1
## Fire terrain: what a hero standing on it takes as the End phase starts.
const FIRE_DAMAGE: int = 1
## The least a hit lands as after damage reduction (Marko 2026-11-08).
const MIN_HIT: int = 1
const DECISION_RETURN_CORE: String = "return_core"
## After the roll: a player with a "Roll Phase:" card or ability may use one (or pass).
const DECISION_ROLL_OFFER: String = "roll_offer"
## End phase, energy claim variant: the player splits the energy left between the stages its
## heroes stand on: {"energy": n, "stages": [ids], "goal": n}.
const DECISION_STAGE_ENERGY: String = "stage_energy"
## Combo (2026-11-07; on top of the two cards since 2026-11-21): the second card of a pair was played in a battle; its
## player may pay more to add the combo to them.
const DECISION_COMBO: String = "combo_offer"

var catalog: CardCatalog
## Card effects (docs/fx-keywords.md).
var fx: FxRuntime
## Moves in progress, hero id -> depth (begin_move / end_move): only a hero's outermost move may
## cost energy in a stage, so a knockback's wall damage is part of the knockback. Per hero: a
## stage's reveal effect that knocks another hero back is still that hero's own, outermost, move.
var _moving: Dictionary[String, int] = {}
## What the setup look-ahead worked out for a layout (_setup_plan), by the layout's key.
var _setup_plans: Dictionary[String, SetupPlan] = {}


func _init(catalog_: CardCatalog) -> void:
	catalog = catalog_
	fx = FxRuntime.new(self)


# =====================================================================================
# Match setup
# =====================================================================================

## `decks[i]` for slot i: {"name": String, "heroes": [3 ids], "cards": {id: count},
## "stages": [3 ids], "cores": [6 ids]}. Hero ids follow docs/ids.md.
func start_match(settings: MatchSettings, decks: Array, seed: int) -> GameState:
	var s := GameState.new()
	s.settings = settings
	s.rng_seed = seed
	s.rng_state = seed
	s.turn = 0
	for i: int in decks.size():
		var d: Dictionary = JsonUtil.as_dict(decks[i])
		var p := PlayerState.new()
		p.slot = i
		p.team = JsonUtil.as_int(d.get("team", i), i)
		p.name = str(d.get("name", "Player %d" % (i + 1)))
		for hid: String in JsonUtil.as_strings(d.get("heroes", [])):
			var card: CardDef = catalog.get_card(hid)
			if card == null or not card.is_hero():
				continue
			var h := HeroState.new()
			h.id = "p%d:%s" % [i, hid]
			h.owner = i
			h.card_id = hid
			h.big = card.wt >= 4
			h.hp = card.hp
			s.heroes.append(h)
		var cards: Dictionary = JsonUtil.as_dict(d.get("cards", {}))
		var keys: Array = cards.keys()
		keys.sort()
		for k: Variant in keys:
			for _n: int in JsonUtil.as_int(cards[k]):
				p.deck.append(str(k))
		p.stage_cards = JsonUtil.as_strings(d.get("stages", []))
		p.core_cards = JsonUtil.as_strings(d.get("cores", []))
		s.players.append(p)
		var n: int = 0
		for sid: String in p.stage_cards:
			n += 1
			var st := StageState.new()
			st.id = "stage:p%d:%d" % [i, n]
			st.card_id = sid
			st.owner = i
			s.stages.append(st)
		n = 0
		# 0 cores per hero is a match without cores: none go on the table (Marko 2026-10-30).
		for cid: String in (p.core_cards if s.settings.core_slots > 0 else PackedStringArray()):
			n += 1
			var c := CoreState.new()
			c.id = "core:p%d:%d" % [i, n]
			c.card_id = cid
			c.owner = i
			s.cores.append(c)
	for p: PlayerState in s.players:
		_shuffle(s, p.deck)
		# A smaller deck (the Fast mode, GDD 13): the first `deck_size` of the shuffled cards,
		# a random draw from the full deck with the same copies and limits.
		if settings.deck_size > 0 and p.deck.size() > settings.deck_size:
			p.deck = p.deck.slice(0, settings.deck_size)
	# A series hands the first move to the last loser (MatchSeries); otherwise lots are drawn.
	var first: int = settings.first_initiative
	s.initiative = first if first >= 0 and first < s.players.size() else s.random_int(s.players.size())
	s.setup_turn = s.initiative
	s.event("match_start", {"initiative": s.initiative})
	s.phase = GameState.PHASE_SETUP_STAGES
	if not settings.manual_setup:
		_auto_place(s)
	_continue(s)
	return s


func _shuffle(s: GameState, arr: PackedStringArray) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = s.random_int(i + 1)
		var t: String = arr[i]
		arr[i] = arr[j]
		arr[j] = t


## Random placement with the setup rules. When the map cannot hold everything at the
## configured gap (six stages do not fit the middle third of a 17 x 17 map at gap 3), the gap
## shrinks for the items that are left and the log says so. See docs/pitanja.md.
func _auto_place(s: GameState) -> void:
	var cells: Array[Vector2i] = s.map().cells()
	# Placing one by one can box itself in; a few fresh tries usually find a full layout.
	for _attempt: int in 64:
		if _try_place_stages(s, cells):
			break
	for st: StageState in s.stages:
		if st.placed:
			continue
		for gap: int in range(s.settings.effective_stage_gap(), -1, -1):
			var options: Array[Vector2i] = []
			for a: Vector2i in cells:
				if _stage_spot_error(s, st, a, gap).is_empty():
					options.append(a)
			if options.is_empty():
				continue
			if gap < s.settings.effective_stage_gap():
				s.event("setup_gap_relaxed", {"stage": st.id, "gap": gap})
			st.center = options[s.random_int(options.size())]
			st.placed = true
			break
	for c: CoreState in s.cores:
		for gap: int in range(s.settings.effective_core_gap(), -1, -1):
			var options: Array[Vector2i] = []
			for a: Vector2i in cells:
				if _core_setup_error(s, c, a, gap).is_empty():
					options.append(a)
			if options.is_empty():
				continue
			if gap < s.settings.effective_core_gap():
				s.event("setup_gap_relaxed", {"core": c.id, "gap": gap})
			c.hex = options[s.random_int(options.size())]
			c.place = CoreState.ON_FIELD
			c.face_up = false
			break


## One random pass over all stages at the full gap; on a dead end it clears them and says false.
func _try_place_stages(s: GameState, cells: Array[Vector2i]) -> bool:
	for st: StageState in s.stages:
		st.placed = false
	for st: StageState in s.stages:
		var options: Array[Vector2i] = []
		for a: Vector2i in cells:
			if _stage_spot_error(s, st, a, s.settings.effective_stage_gap()).is_empty():
				options.append(a)
		if options.is_empty():
			for other: StageState in s.stages:
				other.placed = false
			return false
		st.center = options[s.random_int(options.size())]
		st.placed = true
	return true


## "" when stage `st` may be placed centred on `a`. `gap` is the fewest empty hexes between stage edges; -1 is
## the setup's own rule: the match's gap, and no spot that would leave the stages still to come without room
## (Marko 2026-11-13: six stages must always get out). When the map cannot hold them at that gap at all, the gap
## shrinks as far as it must (stage_setup_gap) and nothing is looked ahead.
func stage_placement_error(s: GameState, st: StageState, a: Vector2i, gap: int = -1) -> String:
	if gap >= 0:
		return _stage_spot_error(s, st, a, gap)
	var plan: SetupPlan = _stage_plan(s, st)
	var err: String = _stage_spot_error(s, st, a, plan.gap)
	if err.is_empty() and plan.ahead and not plan.ok.has(a):
		return "no room would be left for the stages still to come"
	return err


## The gap stage `st` is placed with now: the match's, or the widest smaller one that still has a spot.
func stage_setup_gap(s: GameState, st: StageState) -> int:
	return _stage_plan(s, st).gap


func _stage_spot_error(s: GameState, st: StageState, a: Vector2i, gap: int) -> String:
	for cell: Vector2i in Hex.spiral(a, 1):
		if not s.map().contains(cell):
			return "stage must be fully on the map"
	if not s.in_middle_third(a):
		return "stage must be in the middle third"
	for other: StageState in s.stages:
		if other == st or not other.placed:
			continue
		# `gap` empty hexes between the edges: centres are 1 + gap + 1 + 1 apart or more.
		if Hex.distance(a, other.center) < gap + 3:
			return "too close to another stage"
	return ""


## "" when core `c` may be put on `a` during setup; `gap` -1 is the setup's own rule, as for a stage.
func core_placement_error(s: GameState, c: CoreState, a: Vector2i, gap: int = -1) -> String:
	if gap >= 0:
		return _core_setup_error(s, c, a, gap)
	var plan: SetupPlan = _core_plan(s, c)
	var err: String = _core_setup_error(s, c, a, plan.gap)
	if err.is_empty() and plan.ahead and not plan.ok.has(a):
		return "no room would be left for the cores still to come"
	return err


func core_setup_gap(s: GameState, c: CoreState) -> int:
	return _core_plan(s, c).gap


func _core_setup_error(s: GameState, c: CoreState, a: Vector2i, gap: int) -> String:
	if not s.map().contains(a):
		return "not on the map"
	if not s.in_half_of_team(a, 1 - s.team_of(c.owner)):
		return "core goes into the opponent's half"
	return _core_spot_error(s, c, a, gap)


## What the setup allows for the next piece of a layout: the gap in force, whether spots are checked for the
## pieces still to come, and the spots that pass.
class SetupPlan extends RefCounted:
	var gap: int = 0
	var ahead: bool = false
	var ok: Dictionary[Vector2i, bool] = {}


func _stage_plan(s: GameState, st: StageState) -> SetupPlan:
	var full: int = s.settings.effective_stage_gap()
	var rest: int = 0
	var key: String = "S|%d|%d" % [s.settings.map_size, full]
	for other: StageState in s.stages:
		if other.placed:
			key += "|%d,%d" % [other.center.x, other.center.y]
		elif other != st:
			rest += 1
	key += "|%d" % rest
	if _setup_plans.has(key):
		return _setup_plans[key]
	var plan := SetupPlan.new()
	var free: Array[Vector2i] = []
	for gap: int in range(full, -1, -1):
		free = _sweep(s.map().cells().filter(func(a: Vector2i) -> bool: return _stage_spot_error(s, st, a, gap).is_empty()))
		plan.gap = gap
		if not free.is_empty():
			break
	_look_ahead(plan, free, rest, full + 3, plan.gap == full)
	_keep_plan(key, plan)
	return plan


func _core_plan(s: GameState, c: CoreState) -> SetupPlan:
	var full: int = s.settings.effective_core_gap()
	var team: int = s.team_of(c.owner)
	var rest: int = 0
	var key: String = "C|%d|%d|%d" % [s.settings.map_size, full, team]
	for other: CoreState in s.cores:
		if other.place == CoreState.ON_FIELD:
			key += "|%d,%d" % [other.hex.x, other.hex.y]
		elif other != c and other.place == CoreState.UNPLACED and s.team_of(other.owner) == team:
			rest += 1
	for st: StageState in s.stages:
		if st.placed:
			key += "|s%d,%d" % [st.center.x, st.center.y]
	key += "|%d" % rest
	if _setup_plans.has(key):
		return _setup_plans[key]
	var plan := SetupPlan.new()
	var free: Array[Vector2i] = []
	for gap: int in range(full, -1, -1):
		free = _sweep(s.map().cells().filter(func(a: Vector2i) -> bool: return _core_setup_error(s, c, a, gap).is_empty()))
		plan.gap = gap
		if not free.is_empty():
			break
	_look_ahead(plan, free, rest, full + 1, plan.gap == full)
	_keep_plan(key, plan)
	return plan


## Marks the spots of `free` after which `rest` more pieces still fit. No look-ahead when the gap is relaxed, when
## nothing more is to come, or when they would not all fit even now (then any spot the gap allows will do).
func _look_ahead(plan: SetupPlan, free: Array[Vector2i], rest: int, min_dist: int, full_gap: bool) -> void:
	if not full_gap or rest <= 0 or not SetupFit.fits(free, rest + 1, min_dist):
		return
	for a: Vector2i in free:
		if SetupFit.fits(SetupFit.without(free, a, min_dist), rest, min_dist):
			plan.ok[a] = true
	plan.ahead = not plan.ok.is_empty()


## Hexes in the order the look-ahead packs them: column by column across the map.
func _sweep(cells: Array[Vector2i]) -> Array[Vector2i]:
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var oa: Vector2i = Hex.axial_to_offset(a)
		var ob: Vector2i = Hex.axial_to_offset(b)
		return oa.x < ob.x or (oa.x == ob.x and oa.y < ob.y))
	return cells


func _keep_plan(key: String, plan: SetupPlan) -> void:
	if _setup_plans.size() > 64:
		_setup_plans.clear()
	_setup_plans[key] = plan


## `gap` < 0 skips the distance rules (returning a core from the inventory).
func _core_spot_error(s: GameState, c: CoreState, a: Vector2i, gap: int) -> String:
	if s.wall_at(a) or s.hero_at(a) != null or s.companion_at(a) != null:
		return "hex is taken"
	if s.stage_at(a) != null:
		return "not on a stage"
	for other: CoreState in s.cores:
		if other == c or other.place != CoreState.ON_FIELD:
			continue
		if other.hex == a:
			return "hex is taken"
		if gap >= 0 and Hex.distance(a, other.hex) <= gap:
			return "too close to another core"
	if gap >= 0:
		for st: StageState in s.stages:
			if st.placed and Hex.distance(a, st.center) <= gap + 1:
				return "too close to a stage"
	return ""


# =====================================================================================
# Moves
# =====================================================================================

## Applies one move. Returns "" or why it was refused (state untouched then).
func apply(s: GameState, m: Move) -> String:
	if s.is_over():
		return "the match is over"
	var p: PlayerState = s.player(m.player)
	if p == null:
		return "no such player"
	if p.surrendered:
		return "player has surrendered"
	if m.type == Move.SURRENDER:
		p.surrendered = true
		s.event("surrender", {"player": m.player})
		_end_match(s, other_slot(s, m.player), "surrender")
		return ""
	if not s.pending_knockbacks.is_empty():
		return "waiting for the knockback"
	# Decisions the engine is waiting for come before anything else.
	if not s.pending.is_empty():
		return _apply_decision(s, m)
	var err: String = ""
	match s.phase:
		GameState.PHASE_SETUP_STAGES:
			err = _apply_setup_stage(s, m)
		GameState.PHASE_SETUP_CORES:
			err = _apply_setup_core(s, m)
		GameState.PHASE_MULLIGAN:
			err = _apply_mulligan(s, m)
		GameState.PHASE_START:
			err = _apply_start(s, m)
		GameState.PHASE_ROLL:
			err = _apply_roll_phase(s, m)
		GameState.PHASE_PREROLL, GameState.PHASE_POSTROLL, GameState.PHASE_BATTLE:
			err = _apply_card_round_move(s, m)
		_:
			err = "no moves in phase %s" % s.phase
	if err.is_empty():
		_continue(s)
	return err


func _apply_setup_stage(s: GameState, m: Move) -> String:
	if m.type != Move.PLACE_STAGE:
		return "place a stage"
	if m.player != s.setup_turn:
		return "not your turn to place"
	var st: StageState = s.stage(m.str_arg("stage"))
	if st == null or st.owner != m.player:
		return "not your stage"
	if st.placed:
		return "stage already placed"
	var a: Vector2i = m.hex_arg("hex")
	var err: String = stage_placement_error(s, st, a)
	if not err.is_empty():
		return err
	var gap: int = stage_setup_gap(s, st)
	if gap < s.settings.effective_stage_gap():
		s.event("setup_gap_relaxed", {"stage": st.id, "gap": gap})
	st.center = a
	st.placed = true
	s.event("stage_placed", {"stage": st.id, "hex": Hex.to_json(a)})
	s.setup_turn = _next_slot(s, s.setup_turn)
	return ""


func _apply_setup_core(s: GameState, m: Move) -> String:
	if m.type != Move.PLACE_CORE:
		return "place a core"
	if m.player != s.setup_turn:
		return "not your turn to place"
	var c: CoreState = s.core(m.str_arg("core"))
	if c == null or c.owner != m.player:
		return "not your core"
	if c.place != CoreState.UNPLACED:
		return "core already placed"
	var a: Vector2i = m.hex_arg("hex")
	var err: String = core_placement_error(s, c, a)
	if not err.is_empty():
		return err
	var gap: int = core_setup_gap(s, c)
	if gap < s.settings.effective_core_gap():
		s.event("setup_gap_relaxed", {"core": c.id, "gap": gap})
	c.hex = a
	c.place = CoreState.ON_FIELD
	c.face_up = false
	s.event("core_placed", {"core": c.id, "hex": Hex.to_json(a)})
	s.setup_turn = _next_slot(s, s.setup_turn)
	return ""


func _apply_mulligan(s: GameState, m: Move) -> String:
	if m.type != Move.MULLIGAN:
		return "decide on the mulligan"
	var p: PlayerState = s.player(m.player)
	if p.mulligan_done:
		return "already decided"
	if not m.bool_arg("keep", true):
		var back: PackedStringArray = p.hand.duplicate()
		p.hand = PackedStringArray()
		p.deck.append_array(back)
		_shuffle(s, p.deck)
		draw(s, p, s.settings.start_hand)
		s.event("mulligan", {"player": p.slot})
	p.mulligan_done = true
	return ""


## Start (GDD 8, 2026-10-26): one move picks the hero to activate and whether it rolls
## (`roll`, default true). A hero in the start zone must roll.
func _apply_start(s: GameState, m: Move) -> String:
	if m.type != Move.SELECT:
		return "select a hero"
	if s.active.has(m.player):
		return "already selected"
	var hid: String = m.str_arg("hero")
	var roll: bool = m.bool_arg("roll", true)
	if hid.is_empty():
		if not selectable_heroes(s, m.player).is_empty():
			return "you have a hero that can be activated"
	else:
		var h: HeroState = s.hero(hid)
		if h == null or h.owner != m.player:
			return "not your hero"
		var why: String = activation_error(s, h)
		if not why.is_empty():
			return why
		if not roll and h.zone == HeroState.ZONE_STRIP:
			return "a hero in the start zone must roll"
		# A hero hidden in a companion comes out as it is activated (GDD 10, 2026-11-21): onto a free hex next to
		# it (`hex` picks which; the first free one otherwise), and from there it rolls or stays like any hero.
		if h.is_hidden():
			var out_err: String = leave_shelter(s, h, m.data.get("hex", null))
			if not out_err.is_empty():
				return out_err
	s.active[m.player] = hid
	if not hid.is_empty():
		s.choices[m.player] = roll
	return ""


func selectable_heroes(s: GameState, slot: int) -> Array[HeroState]:
	var out: Array[HeroState] = []
	for h: HeroState in s.heroes_of(slot):
		if activation_error(s, h).is_empty():
			out.append(h)
	return out


func activation_error(s: GameState, h: HeroState) -> String:
	if h.is_ko():
		return "hero is KO"
	if h.has_status("stun"):
		return "hero is stunned"
	if h.tie_turns > 0:
		return "hero is locked in a battle"
	return ""


## Roll: only aims. The phase has no card round; "Roll Phase:" cards and abilities come as a
## roll_offer decision when the balls stop.
func _apply_roll_phase(s: GameState, m: Move) -> String:
	if m.type == Move.AIM:
		if s.awaiting_roll:
			return "waiting for the roll"
		if not s.choices.get(m.player, false) or s.active_hero(m.player) == null:
			return "you are not rolling"
		if s.aims.has(m.player):
			return "already aimed"
		# A missed roll (the timer ran out, GDD 8): the hero is not thrown and stays where it is.
		if JsonUtil.as_bool(m.data.get("skip", false)):
			s.aims[m.player] = {"skip": true}
			s.event("roll_missed", {"player": m.player})
			return ""
		var dir: Array = JsonUtil.as_array(m.data.get("dir", []))
		if dir.size() != 2:
			return "dir must be [x, z]"
		var power: float = JsonUtil.as_float(m.data.get("power", 1.0), 1.0)
		if power < 0.0 or power > 1.0:
			return "power must be 0..1"
		s.aims[m.player] = {"dir": [JsonUtil.as_float(dir[0]), JsonUtil.as_float(dir[1])], "power": power}
		return ""
	return "aim first; the Roll phase has no card round"


## Pass or play a card, in turn. Playing cards arrives in step 2b.
func _apply_card_round_move(s: GameState, m: Move) -> String:
	if s.round_over:
		return "the card round is over"
	if m.player != s.to_act:
		return "not your turn"
	if m.type == Move.PASS:
		if not s.passed.has(m.player):
			s.passed.append(m.player)
		s.to_act = _next_slot(s, s.to_act)
		if s.passed.size() >= _active_slots(s).size():
			s.round_over = true
		return ""
	if m.type == Move.PLAY_CARD:
		if pass_only(s, m.player):
			var asked: CardDef = catalog.get_card(m.str_arg("card"))
			if asked == null or asked.type != "Assist":
				return PASS_ONLY_WHY
		var err: String = _play_card(s, m)
		if not err.is_empty():
			return err
		# Combo (2026-11-07; Marko 2026-11-21: on top of the cards): the card is played and resolved; when it is
		# the second of a combo's pair in this battle, its player is then asked whether to pay for the combo too.
		# The offer waits behind the choices the card itself asked for.
		var offer: Dictionary = _combo_offer(s, m.player, m.str_arg("card"))
		if not offer.is_empty():
			s.pending.append(offer)
		s.passed = PackedInt32Array()
		s.to_act = _next_slot(s, s.to_act)
		return ""
	if m.type == Move.USE_ABILITY:
		if pass_only(s, m.player):
			return PASS_ONLY_WHY
		var err: String = fx.use_ability(s, m.player, m.str_arg("hero"), m.str_arg("card"), JsonUtil.as_int(m.data.get("index", 0)))
		if not err.is_empty():
			return err
		# A core the ability took off comes back now, after the ability's own choices.
		_queue_core_returns(s)
		s.passed = PackedInt32Array()
		s.to_act = _next_slot(s, s.to_act)
		return ""
	return "pass, play a card or use an ability"


func _apply_decision(s: GameState, m: Move) -> String:
	var d: Dictionary = s.pending[0]
	var who: int = JsonUtil.as_int(d.get("player", -1), -1)
	# The roll offers of one stop wait together: each player answers its own, in any order.
	var offer: int = roll_offer_index(s, m.player) if str(d.get("type", "")) == DECISION_ROLL_OFFER else -1
	if offer >= 0:
		d = s.pending[offer]
		who = m.player
	if m.player != who:
		return "waiting for player %d" % who
	match str(d.get("type", "")):
		DECISION_DAMAGE:
			if m.type != Move.DAMAGE_TO:
				return "choose who takes the damage"
			var target: String = m.str_arg("target")
			var amount: int = JsonUtil.as_int(d.get("amount", 0))
			var targets: PackedStringArray = JsonUtil.as_strings(d.get("targets", []))
			var winner: String = str(d.get("winner", ""))
			var min_hero: int = JsonUtil.as_int(d.get("min_hero", hero_share(amount)))
			if target == "deck":
				return "the deck takes no damage: pick a hero, and cards from your hand for the rest"
			if not targets.has(target):
				return "target must be one of %s" % ", ".join(targets)
			var cards: PackedStringArray = JsonUtil.as_strings(m.data.get("cards", []))
			if cards.size() > amount - min_hero:
				return "at least %d DMG must go to the hero: at most %d cards from the hand" % [min_hero, amount - min_hero]
			var p: PlayerState = s.player(who)
			var left: PackedStringArray = p.hand.duplicate()
			for cid: String in cards:
				var at: int = left.find(cid)
				if at < 0:
					return "%s is not in your hand" % cid
				left.remove_at(at)
			s.pending.pop_front()
			var by: String = str(d.get("by", winner))
			hand_damage(s, p, cards, by)
			hero_damage(s, s.hero(target), amount - cards.size(), false, by)
			_drop_dead_targets(s)
		DECISION_RETURN_CORE:
			if m.type != Move.RETURN_CORE:
				return "put a core back first"
			var c: CoreState = s.core(m.str_arg("core"))
			var index: int = -1
			for i: int in s.pending.size():
				var q: Dictionary = s.pending[i]
				if str(q.get("type", "")) == DECISION_RETURN_CORE and JsonUtil.as_int(q.get("player", -1), -1) == who \
						and c != null and str(q.get("core", "")) == c.id:
					index = i
					break
			if index < 0:
				return "that core is not waiting in your inventory"
			var a: Vector2i = m.hex_arg("hex")
			var err: String = core_return_error(s, c, a)
			if not err.is_empty():
				return err
			s.pending.remove_at(index)
			var p: PlayerState = s.player(who)
			p.inventory.remove_at(p.inventory.find(c.id))
			c.place = CoreState.ON_FIELD
			c.hex = a
			c.picked_by = ""
			s.event("core_returned", {"core": c.id, "hex": Hex.to_json(a)})
		FxRuntime.DECISION_CHOOSE:
			if m.type != Move.CHOOSE:
				return str(d.get("prompt", "make your choice"))
			var trial: Array[Dictionary] = s.pending.duplicate()
			s.pending.pop_front()
			var err: String = fx.resume(s, d, m.data.get("value", null))
			if not err.is_empty():
				s.pending = trial
				return err
		DECISION_ROLL_OFFER:
			var err: String = _answer_roll_offer(s, offer, m)
			if not err.is_empty():
				return err
		DECISION_COMBO:
			var picked: String = ""
			if m.type == Move.CHOOSE:
				picked = str(m.data.get("value", ""))
			elif m.type != Move.PASS:
				return "choose the combo, or pass to go without it"
			var option: Dictionary = {}
			for o: Variant in JsonUtil.as_array(d.get("combos", [])):
				if str(JsonUtil.as_dict(o).get("id", "")) == picked:
					option = JsonUtil.as_dict(o)
			if not picked.is_empty() and option.is_empty():
				return "that combo is not on offer"
			if option.is_empty():
				# Declined: the two cards stay as they were played.
				s.pending.pop_front()
			else:
				var err: String = _accept_combo(s, who, d, option)
				if not err.is_empty():
					return err
				s.pending.pop_front()
		DECISION_STAGE_ENERGY:
			if m.type != Move.STAGE_ENERGY:
				return "put your energy into the stages first"
			var energy: int = JsonUtil.as_int(d.get("energy", 0))
			var ids: PackedStringArray = JsonUtil.as_strings(d.get("stages", []))
			var split: Dictionary = JsonUtil.as_dict(m.data.get("split", {}))
			var total: int = 0
			for k: Variant in split:
				if not ids.has(str(k)):
					return "%s is not a stage your energy can go into" % str(k)
				var n: int = JsonUtil.as_int(split[k])
				if n < 0:
					return "energy cannot be negative"
				total += n
			if total != energy:
				return "all %d energy goes into the stages (got %d)" % [energy, total]
			s.pending.pop_front()
			for id: String in ids:
				_put_energy(s, who, s.stage(id), JsonUtil.as_int(split.get(id, 0)))
			s.player(who).energy = 0
			var more: bool = false
			for other: Dictionary in s.pending:
				if str(other.get("type", "")) == DECISION_STAGE_ENERGY:
					more = true
			if not more:
				_claim_by_energy(s)
		_:
			return "unknown decision"
	_continue(s)
	return ""


## Where the pending roll offer of `slot` sits, -1 when it has none (answered, or not asked).
func roll_offer_index(s: GameState, slot: int) -> int:
	for i: int in s.pending.size():
		var q: Dictionary = s.pending[i]
		if str(q.get("type", "")) == DECISION_ROLL_OFFER and JsonUtil.as_int(q.get("player", -1), -1) == slot:
			return i
	return -1


## The roll_offer decision at `index`: `pass` declines; `use_ability` or `play_card` takes one
## of the offered options (one per stop). The offer leaves the queue before the effect runs,
## so a choice the effect asks for comes next.
func _answer_roll_offer(s: GameState, index: int, m: Move) -> String:
	var d: Dictionary = s.pending[index]
	if m.type == Move.PASS:
		s.pending.remove_at(index)
		s.event("roll_offer_declined", {"player": m.player})
		return ""
	# The offer was made before the hero went off (its own roll rang it out): Pass only now.
	if s.only_pass.has(m.player):
		return PASS_ONLY_WHY
	if m.type == Move.USE_ABILITY:
		var key: String = "%s|%s|%d" % [m.str_arg("hero"), m.str_arg("card"), JsonUtil.as_int(m.data.get("index", 0))]
		if not JsonUtil.as_strings(d.get("abilities", [])).has(key):
			return "that ability is not on offer"
		var trial: Array[Dictionary] = s.pending.duplicate()
		s.pending.remove_at(index)
		var err: String = fx.use_ability(s, m.player, m.str_arg("hero"), m.str_arg("card"), JsonUtil.as_int(m.data.get("index", 0)))
		if not err.is_empty():
			s.pending = trial
		else:
			_queue_core_returns(s)
			_decisions_first(s, trial.size() - 1)
		return err
	if m.type == Move.PLAY_CARD:
		if not JsonUtil.as_strings(d.get("cards", [])).has(m.str_arg("card")):
			return "that card is not on offer"
		var trial: Array[Dictionary] = s.pending.duplicate()
		s.pending.remove_at(index)
		var err: String = _play_card(s, m)
		if not err.is_empty():
			s.pending = trial
		else:
			_decisions_first(s, trial.size() - 1)
		return err
	return "use a Roll Phase card or ability, or pass"


## The decisions an answered offer added (past the `kept` older ones) go to the front, so the
## player who answered gets its choice now instead of behind the other offers of the stop.
func _decisions_first(s: GameState, kept: int) -> void:
	if s.pending.size() <= kept:
		return
	var added: Array[Dictionary] = s.pending.slice(kept)
	var rest: Array[Dictionary] = s.pending.slice(0, kept)
	s.pending = added + rest


## After the balls stop: one roll_offer per active player (initiative first) with the "Roll
## Phase:" abilities it may use now and the "Roll Phase:" Actions it can pay for the activated
## hero. Every player gets one, options or none, so nobody can read "has a Roll Phase card" off
## who is asked (GDD 8, 2026-10-26); the offers of one stop are answered in any order.
func _offer_roll_effects(s: GameState) -> void:
	var slot: int = s.initiative
	for _n: int in s.players.size():
		var p: PlayerState = s.player(slot)
		var h: HeroState = s.active_hero(slot)
		# Only a hero that rolled gets the offer: one that stayed has nothing to roll again
		# (Marko 2026-11-02). Roll or Stay is public, so no offer gives nothing away.
		# A player whose activated hero left the map this turn is down to Pass (Marko 2026-11-08: a
		# ringed-out Luffy rolled back in with Gear Second Soru): no offer, not even its abilities.
		if p != null and not p.surrendered and h != null and not h.is_ko() and s.choices.get(slot, false) 				and not s.only_pass.has(slot):
			var abilities := PackedStringArray()
			for a: Dictionary in fx.usable_abilities(s, slot):
				abilities.append(str(a["key"]))
			var cards := PackedStringArray()
			var hero_card: CardDef = catalog.get_card(h.card_id)
			for cid: String in p.playable_cards():
				var card: CardDef = catalog.get_card(cid)
				if card == null or not card.is_ready() or _play_phase(card) != "ROLL":
					continue
				if hero_card != null and not card.plays_for_color(hero_card.color):
					continue
				if hero_card != null and not JsonUtil.as_bool(FirstTag.play_verdict(catalog, card, hero_card, stat_card(h), gained_tags(s, h))["ok"]):
					continue
				if card_cost(s, p, card, h) <= p.energy:
					cards.append(cid)
			s.pending.append({"type": DECISION_ROLL_OFFER, "player": slot, "hero": h.id, "at": s.log.size(),
				"abilities": Array(abilities), "cards": Array(cards)})
		slot = _next_slot(s, slot)


## REVERSE_ROLL (GDD 10): the activated hero goes back to where it stood as the Roll phase
## began. Only that hero moves back; heroes it pushed, cores it picked up and stages it
## revealed stay as they are.
func reverse_roll(s: GameState, slot: int) -> String:
	if s.phase != GameState.PHASE_ROLL or not s.rolled:
		return "reverse roll only works in the Roll phase after the roll"
	var h: HeroState = s.active_hero(slot)
	if h == null or h.is_ko():
		return "no activated hero to put back"
	if not s.roll_snapshot.has(h.id):
		return "nothing to go back to"
	var before: Dictionary = s.roll_snapshot[h.id]
	h.zone = str(before.get("zone", h.zone))
	h.hex = JsonUtil.as_hex(before.get("hex", Hex.to_json(h.hex)))
	s.event("reverse_roll", {"hero": h.id, "hex": Hex.to_json(h.hex), "zone": h.zone})
	return ""


## The hero's name as the player sees it (its current card).
func hero_name(h: HeroState) -> String:
	var c: CardDef = stat_card(h)
	return c.name if c != null else h.id


## "" when an inventory core may go back onto `a`.
func core_return_error(s: GameState, c: CoreState, a: Vector2i) -> String:
	if not s.map().contains(a):
		return "not on the map"
	var err: String = _core_spot_error(s, c, a, -1)
	if not err.is_empty():
		return err
	var picker: HeroState = s.hero(c.picked_by)
	if picker != null and picker.is_on_map():
		if not reaches_hex(s, picker, a):
			return "must be within the range of %s" % hero_name(picker)
	elif not s.in_half_of_team(a, s.team_of(c.owner)):
		return "must be in your half"
	return ""


# =====================================================================================
# Roll outcome from the sim
# =====================================================================================

## Feeds the physics result of the pending knockbacks (GDD 10, 2026-10-26): every ball the sim
## moved lands where it stopped, with cores picked, stages revealed and ring-outs as in a roll;
## a hit costs nothing (Marko 2026-11-07: no wall damage; a ring-out costs 1 DMG). Then the match goes on.
func apply_knockback(s: GameState, o: RollOutcome) -> String:
	if s.pending_knockbacks.is_empty():
		return "no knockback waiting"
	var asked: Dictionary = {}
	# Whose doing each knockback is (a tie-break sends each side back by the other's); a ball
	# a knocked hero touched, directly or through others, is the same team's doing.
	var movers: Dictionary[String, int] = {}
	for k: Dictionary in s.pending_knockbacks:
		asked[str(k.get("hero", ""))] = JsonUtil.as_int(k.get("steps", 0))
		movers[str(k.get("hero", ""))] = JsonUtil.as_int(k.get("by_team", -1), -1)
	s.pending_knockbacks.clear()
	var causes: Dictionary[String, int] = _causes(s, o, movers)
	for r: RollResult in o.results:
		_apply_companion_result(s, r)
		var h: HeroState = s.hero(r.ball_id)
		if h == null or h.is_ko():
			continue
		var from: Vector2i = h.hex
		var by_team: int = causes.get(r.ball_id, -1)
		var was: StageState = begin_move(s, h)
		_apply_result(s, h, r)
		if asked.has(h.id):
			s.event("knockback", {"hero": h.id, "from": Hex.to_json(from), "to": Hex.to_json(h.hex),
				"steps": asked[h.id], "physics": true, "hits": r.collisions.size() + r.walls_hit})
		end_move(s, h, was, by_team)
	_unstack_companions(s)
	s.event("knockback_done", {"heroes": asked.keys()})
	_check_win(s)
	_continue(s)
	return ""


## Feeds the physics result for this turn's throws. Every result whose ball id is a hero id
## moves that hero; others are ignored.
func apply_roll(s: GameState, o: RollOutcome) -> String:
	if s.phase != GameState.PHASE_ROLL or not s.awaiting_roll:
		return "not waiting for a roll"
	var causes: Dictionary[String, int] = roll_causes(s, o)
	for r: RollResult in o.results:
		_apply_companion_result(s, r)
		var h: HeroState = s.hero(r.ball_id)
		if h == null or h.is_ko():
			continue
		var by_team: int = causes.get(r.ball_id, -1)
		_apply_result(s, h, r, by_team)
		# "If X rolls, this Evolution goes to the graveyard."
		if r.thrown and not h.is_ko() and has_status(s, h, "brittle"):
			remove_evolution(s, h, true)
	_unstack_companions(s)
	# A thrown hero that never left its start strip (too weak a throw) throws again, as if
	# nothing happened (Marko 2026-10-26): it may not stay there. The others keep where they
	# stopped and are not thrown again.
	var stuck: Array[HeroState] = []
	for r: RollResult in o.results:
		var h: HeroState = s.hero(r.ball_id)
		if h != null and r.thrown and not h.is_ko() and r.end_area == BallWorld.Area.STRIP and not r.ring_out \
				and r.strip_entered < 0 and h.zone == HeroState.ZONE_STRIP and s.active.get(h.owner, "") == h.id:
			stuck.append(h)
	if not stuck.is_empty():
		for slot: int in s.aims.keys():
			s.aims[slot] = {"skip": true}
		for h: HeroState in stuck:
			s.aims.erase(h.owner)
			s.event("roll_retry", {"hero": h.id})
		s.awaiting_roll = false
		s.pending_rolls = PackedStringArray()
		_continue(s)
		return ""
	s.awaiting_roll = false
	s.rolled = true
	s.pending_rolls = PackedStringArray()
	s.roll_offered = false
	s.event("rolled", {"moved": Array(o.moved_ids())})
	_continue(s)
	return ""


## A hero stopped on a hex (a roll, a knockback, an effect's move or swap): a face-down stage
## under it turns face up (GDD 6; Marko 2026-10-26: not only after a roll).
func arrive(s: GameState, h: HeroState) -> void:
	if h == null or not h.is_on_map():
		return
	var st: StageState = s.stage_at(h.hex)
	if st != null and st.placed and not st.revealed:
		reveal_stage(s, st, h)


## Who moved each ball of a roll, as a team: a thrown ball its own; a ball it did not throw the
## team of a thrower whose ball touched it (directly or through other balls), another team's
## first; with no touches reported (the analytic roll) another team that threw, else its own.
func roll_causes(s: GameState, o: RollOutcome) -> Dictionary[String, int]:
	var thrown: Dictionary[String, int] = {}
	for r: RollResult in o.results:
		var h: HeroState = s.hero(r.ball_id)
		if h != null and r.thrown:
			thrown[r.ball_id] = s.team_of(h.owner)
	return _causes(s, o, thrown)


## Who moved each ball of an outcome, as a team. `movers`: the balls set going and whose doing
## each was (a thrown ball its thrower's own team, a knocked-back one the team that knocked it).
## A mover keeps its entry; any other ball takes a mover's that touched it, directly or through
## other balls, another team's first; a ball no touch leads to a mover from (none reported) takes
## another team's among all the movers, else its own.
func _causes(s: GameState, o: RollOutcome, movers: Dictionary[String, int]) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	var touch: Dictionary[String, PackedStringArray] = {}
	for r: RollResult in o.results:
		for other: String in r.collisions:
			if not touch.has(r.ball_id):
				touch[r.ball_id] = PackedStringArray()
			if not touch.has(other):
				touch[other] = PackedStringArray()
			touch[r.ball_id].append(other)
			touch[other].append(r.ball_id)
	for r: RollResult in o.results:
		var h: HeroState = s.hero(r.ball_id)
		if h == null:
			continue
		var own: int = s.team_of(h.owner)
		if movers.has(r.ball_id):
			out[r.ball_id] = movers[r.ball_id]
			continue
		var teams: Dictionary[int, bool] = {}
		var seen: Dictionary[String, bool] = {r.ball_id: true}
		var queue: PackedStringArray = PackedStringArray([r.ball_id])
		while not queue.is_empty():
			var id: String = queue[queue.size() - 1]
			queue.remove_at(queue.size() - 1)
			if movers.has(id):
				teams[movers[id]] = true
			for next: String in touch.get(id, PackedStringArray()):
				if not seen.has(next):
					seen[next] = true
					queue.append(next)
		if teams.is_empty():
			for t: int in movers.values():
				teams[t] = true
		var by: int = own
		for t: int in teams:
			if t != own:
				by = t
				break
		out[r.ball_id] = by
	return out


## One ball's stop applied to its hero; `by_team` moved it (see end_move).
func _apply_result(s: GameState, h: HeroState, r: RollResult, by_team: int = -1) -> void:
	var was: StageState = begin_move(s, h)
	_place_result(s, h, r)
	end_move(s, h, was, by_team)


func _place_result(s: GameState, h: HeroState, r: RollResult) -> void:
	for cid: String in r.cores_picked:
		var c: CoreState = s.core(cid)
		if c != null and c.place == CoreState.ON_FIELD:
			pick_core(s, h, c)
		# A trap on the core knocked it out (code review 2026-11-13): it picks up nothing more and does not land.
		# It used to be put back on the map, or rung out into its start zone, with 0 HP.
		if h.is_ko():
			return
	if r.ring_out or r.strip_entered >= 0:
		ring_out(s, h, "edge" if r.ring_out else "strip")
		return
	if r.end_area == BallWorld.Area.MAP:
		h.zone = HeroState.ZONE_MAP
		h.hex = r.end_hex
		s.event("moved", {"hero": h.id, "hex": Hex.to_json(h.hex)})
		arrive(s, h)
	# end_area STRIP without entering the map: a weak throw, the hero stays in its zone.


func pick_core(s: GameState, h: HeroState, c: CoreState) -> void:
	var p: PlayerState = s.player(h.owner)
	if h.cores.size() < s.settings.core_slots:
		h.cores.append(c.id)
		c.place = CoreState.ON_HERO
		c.holder = h.id
		c.face_up = true
		s.event("core_activated", {"core": c.id, "hero": h.id})
		_spring_core_traps(s, h, c)
	else:
		p.inventory.append(c.id)
		c.place = CoreState.IN_INVENTORY
		c.holder = ""
		c.picked_by = h.id
		s.event("core_to_inventory", {"core": c.id, "hero": h.id})


## TRAP_CORE: an enemy of the trap's player activating that core this turn takes damage.
func _spring_core_traps(s: GameState, h: HeroState, c: CoreState) -> void:
	for m: Dictionary in s.turn_mods:
		if str(m.get("kind", "")) != "core_trap" or str(m.get("core", "")) != c.id:
			continue
		if s.team_of(JsonUtil.as_int(m.get("player", -1))) == s.team_of(h.owner):
			continue
		s.event("core_trap", {"core": c.id, "hero": h.id})
		hero_damage(s, h, JsonUtil.as_int(m.get("amount", 0)), false, "trap")


## "" when an effect may move core `c` onto `a` (free hex, not on a stage).
func core_move_error(s: GameState, c: CoreState, a: Vector2i) -> String:
	if not s.map().contains(a):
		return "not on the map"
	return _core_spot_error(s, c, a, -1)


func shuffle(s: GameState, arr: PackedStringArray) -> void:
	_shuffle(s, arr)


# =====================================================================================
# Phase flow
# =====================================================================================

## Runs every automatic step until the engine needs input.
func _continue(s: GameState) -> void:
	var guard: int = 0
	while not s.is_over() and guard < 64:
		guard += 1
		_sync_companions(s)
		_drop_held_hits(s)
		if not s.pending.is_empty() or not s.pending_knockbacks.is_empty():
			return
		match s.phase:
			GameState.PHASE_SETUP_STAGES:
				if not _all_stages_placed(s):
					return
				_set_phase(s, GameState.PHASE_SETUP_CORES)
			GameState.PHASE_SETUP_CORES:
				if not _all_cores_placed(s):
					return
				for p: PlayerState in s.players:
					draw(s, p, s.settings.start_hand)
				_set_phase(s, GameState.PHASE_MULLIGAN)
			GameState.PHASE_MULLIGAN:
				for p: PlayerState in s.players:
					if not p.mulligan_done:
						return
				s.turn = 1
				_begin_turn(s)
			GameState.PHASE_START:
				if s.active.size() < _active_slots(s).size() or not _all_choices_in(s):
					return
				# Everyone decided: the heroes and the Roll / Stay choices come out together.
				s.event("activated", {"heroes": s.active.duplicate()})
				s.event("choices", {"roll": s.choices.duplicate()})
				_start_card_round(s)
				_set_phase(s, GameState.PHASE_PREROLL)
			GameState.PHASE_PREROLL:
				if not s.round_over:
					return
				if _rollers(s).is_empty():
					_start_card_round(s)
					_set_phase(s, GameState.PHASE_POSTROLL)
				else:
					_set_phase(s, GameState.PHASE_ROLL)
			GameState.PHASE_ROLL:
				if not _all_aims_in(s):
					return
				if not s.rolled:
					if s.pending_rolls.is_empty():
						for h: HeroState in _rollers(s):
							s.pending_rolls.append(h.id)
					s.awaiting_roll = true
					return
				# The balls stopped: whoever has a "Roll Phase:" card or ability gets one offer
				# (a roll again brings a new stop and a new offer); then straight to Postroll.
				if not s.roll_offered:
					s.roll_offered = true
					_offer_roll_effects(s)
					if not s.pending.is_empty():
						return
				_start_card_round(s)
				_set_phase(s, GameState.PHASE_POSTROLL)
			GameState.PHASE_POSTROLL:
				if not s.round_over:
					return
				# Postroll bonuses without a duration end with the phase, before battles form;
				# only "until the end of the turn" ones can start a battle.
				_clear_phase_bonuses(s)
				_find_battles(s)
				s.battle_index = -1
				_set_phase(s, GameState.PHASE_BATTLE)
				_next_battle(s)
			GameState.PHASE_BATTLE:
				if s.battle_index >= s.battles.size():
					_set_phase(s, GameState.PHASE_END)
					continue
				var b: Dictionary = s.battles[s.battle_index]
				if JsonUtil.as_bool(b.get("resolved", false)):
					_next_battle(s)
					continue
				if not JsonUtil.as_bool(b.get("hits_done", false)):
					if not s.round_over:
						return
					_resolve_battle(s, s.battle_index)
					b["hits_done"] = true
					if not s.pending.is_empty():
						return
				_finish_battle(s, s.battle_index)
			GameState.PHASE_END:
				if s.settings.energy_claims() and not s.energy_banked:
					_bank_energy(s)
					if not s.pending.is_empty():
						return
				_end_phase(s)
				if s.is_over():
					return
				_begin_turn(s)
			_:
				return


## A new turn: the draw (cards, energy, turn data) and then the Start phase, whose "Start
## Phase:" effects fire before anyone picks.
func _begin_turn(s: GameState) -> void:
	_draw_phase(s)
	_set_phase(s, GameState.PHASE_START)


## Every phase change goes through here, so inventory cores get queued for their return.
func _set_phase(s: GameState, phase: String) -> void:
	s.phase = phase
	_clear_phase_bonuses(s)
	# A hero that left its stage (or whose stage got claimed) loses the reveal bonus for good.
	s.stage_buffs = s.stage_buffs.filter(func(b: Dictionary) -> bool: return _stage_buff_holds(s, b))
	_queue_core_returns(s)
	if phase == GameState.PHASE_BATTLE:
		s.battle_snapshot.clear()
		for h: HeroState in s.heroes:
			s.battle_snapshot[h.id] = {"zone": h.zone, "hex": Hex.to_json(h.hex)}
	if phase == GameState.PHASE_ROLL:
		# Where everyone stands before the balls fly, for REVERSE_ROLL.
		s.roll_snapshot.clear()
		for h: HeroState in s.heroes:
			s.roll_snapshot[h.id] = {"zone": h.zone, "hex": Hex.to_json(h.hex)}
	if phase == GameState.PHASE_END:
		_burn(s)
		_doom(s)
		_late_heals(s)
		_returns(s)
	match phase:
		GameState.PHASE_START, GameState.PHASE_PREROLL, GameState.PHASE_ROLL, GameState.PHASE_POSTROLL, \
				GameState.PHASE_BATTLE, GameState.PHASE_END:
			fx.fire_phase(s, phase)


func _all_stages_placed(s: GameState) -> bool:
	for st: StageState in s.stages:
		if not st.placed:
			return false
	return true


func _all_cores_placed(s: GameState) -> bool:
	for c: CoreState in s.cores:
		if c.place == CoreState.UNPLACED:
			return false
	return true


func _all_choices_in(s: GameState) -> bool:
	for slot: int in _active_slots(s):
		if s.active_hero(slot) != null and not s.choices.has(slot):
			return false
	return true


func _rollers(s: GameState) -> Array[HeroState]:
	var out: Array[HeroState] = []
	for slot: int in _active_slots(s):
		if s.choices.get(slot, false):
			var h: HeroState = s.active_hero(slot)
			# "They cannot roll this turn" (a card moved the hero instead).
			if h != null and not h.is_ko() and not h.has_status("no_roll"):
				out.append(h)
	return out


func _all_aims_in(s: GameState) -> bool:
	for h: HeroState in _rollers(s):
		if not s.aims.has(h.owner):
			return false
	return true


func _start_card_round(s: GameState) -> void:
	s.to_act = s.initiative
	s.passed = PackedInt32Array()
	s.round_over = false


func _draw_phase(s: GameState) -> void:
	s.reset_turn_data()
	for h: HeroState in s.heroes:
		if not h.turn_bonus.is_empty():
			h.turn_bonus.clear()
			clamp_hp(s, h)
	for p: PlayerState in s.players:
		if p.surrendered:
			continue
		draw(s, p, 1)
		p.energy = mini(s.turn, s.settings.max_energy)
	s.event("draw")


func draw(s: GameState, p: PlayerState, n: int) -> void:
	for _i: int in n:
		if p.deck.is_empty():
			return
		p.hand.append(p.deck[0])
		p.deck.remove_at(0)


## Players still in the match.
func _active_slots(s: GameState) -> PackedInt32Array:
	var out := PackedInt32Array()
	for p: PlayerState in s.players:
		if not p.surrendered:
			out.append(p.slot)
	return out


func _next_slot(s: GameState, slot: int) -> int:
	var n: int = s.players.size()
	for i: int in range(1, n + 1):
		var cand: int = (slot + i) % n
		if not s.player(cand).surrendered:
			return cand
	return slot


func other_slot(s: GameState, slot: int) -> int:
	var team: int = s.team_of(slot)
	for p: PlayerState in s.players:
		if p.team != team:
			return p.slot
	return -1


## At the start of every phase a player with cores in the inventory must put them back; a core
## deactivated by an ability or a card is asked for at once, in the same phase (Marko 2026-11-07:
## Zoro's core waited for the Battle phase), after the effect's own choices. One asking per core.
func _queue_core_returns(s: GameState) -> void:
	if s.phase == GameState.PHASE_SETUP_STAGES or s.phase == GameState.PHASE_SETUP_CORES \
			or s.phase == GameState.PHASE_MULLIGAN:
		return
	for p: PlayerState in s.players:
		for cid: String in p.inventory:
			if _return_pending(s, cid) or not _has_free_return_spot(s, s.core(cid)):
				continue
			s.pending.append({"type": DECISION_RETURN_CORE, "player": p.slot, "core": cid})


func _return_pending(s: GameState, cid: String) -> bool:
	for d: Dictionary in s.pending:
		if str(d.get("type", "")) == DECISION_RETURN_CORE and str(d.get("core", "")) == cid:
			return true
	return false


func _has_free_return_spot(s: GameState, c: CoreState) -> bool:
	for a: Vector2i in s.map().cells():
		if core_return_error(s, c, a).is_empty():
			return true
	return false


# =====================================================================================
# Battle
# =====================================================================================

## Battles form at the start of the Battle phase: any two opposing heroes in range. The one
## with the activated hero goes first, the others follow in initiative order. A hero is in at
## most one battle.
func _find_battles(s: GameState) -> void:
	s.battles.clear()
	var taken: PackedStringArray = PackedStringArray()
	var seeds: Array[HeroState] = []
	# Locked (tied) groups keep fighting first.
	for h: HeroState in s.heroes:
		if h.is_on_map() and h.tie_turns > 0:
			seeds.append(h)
	var order: PackedInt32Array = PackedInt32Array()
	var slot: int = s.initiative
	for _i: int in s.players.size():
		order.append(slot)
		slot = _next_slot(s, slot)
	for sl: int in order:
		var a: HeroState = s.active_hero(sl)
		if a != null and a.is_on_map():
			seeds.append(a)
	for sl: int in order:
		for h: HeroState in s.heroes_of(sl):
			if h.is_on_map():
				seeds.append(h)
	for seed: HeroState in seeds:
		if taken.has(seed.id):
			continue
		var members: Array[HeroState] = [seed]
		if seed.tie_turns > 0:
			for lid: String in seed.locked_with:
				var l: HeroState = s.hero(lid)
				if l != null and l.is_on_map() and not taken.has(l.id):
					members.append(l)
		# The starters: the seed (or the locked group) and the enemies in range with it. Then
		# whoever is in range with a starter of the other team joins, allies of the seed too
		# (playtest 2026-10-30: Zoro reaching the enemy was left out). Then one chain step
		# (Marko 2026-11-06: the activated Zoro next to Luffy, a joiner, was left out): whoever is
		# in range with an enemy already in, once; those pull nobody further (GDD 10).
		var starters: Array[HeroState] = members.duplicate()
		for other: HeroState in _joiners(s, [seed], taken, members):
			members.append(other)
			starters.append(other)
		for other: HeroState in _joiners(s, starters, taken, members):
			members.append(other)
		for other: HeroState in _joiners(s, members.duplicate(), taken, members):
			members.append(other)
		var has_enemy: bool = false
		for m: HeroState in members:
			if not s.same_team(m, seed):
				has_enemy = true
		if not has_enemy:
			continue
		var ids: Array = []
		for m: HeroState in members:
			ids.append(m.id)
			taken.append(m.id)
		s.battles.append({"heroes": ids, "resolved": false, "winner_team": -1, "tie": false})
	if not s.battles.is_empty():
		s.event("battles", {"battles": s.battles.duplicate(true)})


## Heroes on the map, free and not yet in `members`, in range (either way) with a hero of
## `against` from the other team.
func _joiners(s: GameState, against: Array[HeroState], taken: PackedStringArray,
		members: Array[HeroState]) -> Array[HeroState]:
	var out: Array[HeroState] = []
	for other: HeroState in s.heroes:
		if not other.is_on_map() or taken.has(other.id) or members.has(other) or out.has(other):
			continue
		for m: HeroState in against:
			if not s.same_team(m, other) and (in_range(s, m, other) or in_range(s, other, m)):
				out.append(other)
				break
	return out


func _next_battle(s: GameState) -> void:
	s.battle_index += 1
	if s.battle_index < s.battles.size():
		_start_card_round(s)
		fx.fire_battle(s)


## After a hit: the hits still waiting drop the heroes that went down with it (online playtest
## 2026-11-07: "3 DMG from Sanji" asked where to put a hit on a Shanks already at 0). A hit with
## nobody left to take it is wasted, event `hit_wasted {hero, targets}`.
func _drop_dead_targets(s: GameState) -> void:
	var i: int = 0
	while i < s.pending.size():
		var d: Dictionary = s.pending[i]
		if str(d.get("type", "")) != DECISION_DAMAGE:
			i += 1
			continue
		var alive: Array = []
		var gone: Array = []
		# A ring-out's own cost waits for a hero that is on its strip by then (Marko 2026-11-11: with two
		# heroes ringed out by one roll the second choice went as a hit with nobody left); only a KO ends it.
		var ring_out: bool = JsonUtil.as_bool(d.get("ring_out", false))
		for id: String in JsonUtil.as_strings(d.get("targets", [])):
			var h: HeroState = s.hero(id)
			if h != null and (h.is_on_map() or (ring_out and not h.is_ko())):
				alive.append(id)
			else:
				gone.append(id)
		if alive.is_empty():
			s.pending.remove_at(i)
			s.event("hit_wasted", {"hero": str(d.get("winner", "")), "targets": gone})
			continue
		if not gone.is_empty():
			d["targets"] = alive
			d["player"] = s.hero(str(alive[0])).owner
		i += 1


## A winner that chose HOLD_HIT deals no damage: its pending damage decisions go away.
func _drop_held_hits(s: GameState) -> void:
	var i: int = 0
	while i < s.pending.size():
		var d: Dictionary = s.pending[i]
		var w: HeroState = s.hero(str(d.get("winner", "")))
		if str(d.get("type", "")) == DECISION_DAMAGE and w != null and w.has_status("hold_hit"):
			s.pending.remove_at(i)
			s.event("hit_held", {"hero": w.id})
			continue
		i += 1


func _battle_heroes(s: GameState, b: Dictionary) -> Array[HeroState]:
	var out: Array[HeroState] = []
	for id: String in JsonUtil.as_strings(b.get("heroes", [])):
		var h: HeroState = s.hero(id)
		if h != null and h.is_on_map():
			out.append(h)
	return out


func _resolve_battle(s: GameState, index: int) -> void:
	var b: Dictionary = s.battles[index]
	var members: Array[HeroState] = _battle_heroes(s, b)
	var power: Dictionary[int, int] = {}
	for h: HeroState in members:
		var t: int = s.team_of(h.owner)
		power[t] = JsonUtil.as_int(power.get(t, 0)) + stat(s, h, "pwr")
	var teams: Array = power.keys()
	if teams.size() < 2:
		b["resolved"] = true
		return
	# A side with a hero that gives the battle up ("loses this Battle without taking DMG") cannot win it.
	var fled: Array[int] = []
	for h: HeroState in members:
		if h.has_status("flee") and not fled.has(s.team_of(h.owner)):
			fled.append(s.team_of(h.owner))
	var best: int = -1
	var best_pow: int = -1
	var tie: bool = false
	for t: int in teams:
		if fled.has(t):
			continue
		if power[t] > best_pow:
			best_pow = power[t]
			best = t
			tie = false
		elif power[t] == best_pow:
			tie = true
	var fighters: Array = []
	for h: HeroState in members:
		fighters.append(h.id)
	s.event("battle", {"index": index, "power": power.duplicate(), "heroes": fighters})
	# A hero that gave the battle up leaves its friends in it to lose it (Marko and the other author, 2026-11-23): its
	# side cannot win, they take the hit as losers, it goes unhit and is ringed out after the battle.
	if best < 0:
		# Every side gave up: nobody wins, nobody is hit.
		b["winner_team"] = -2
		return
	if tie:
		b["tie"] = true
		_battle_tie(s, members)
		return
	b["winner_team"] = best
	var winners: Array[HeroState] = []
	var losers: Array[HeroState] = []
	for h: HeroState in members:
		if s.team_of(h.owner) == best:
			winners.append(h)
		else:
			losers.append(h)
	# Each winner that reaches a loser hits with its own DMG; the loser picks the target.
	for w: HeroState in winners:
		var targets: Array = []
		for l: HeroState in losers:
			if in_range(s, w, l) and not l.has_status("flee"):
				targets.append(l.id)
		if targets.is_empty():
			# Said in the log (playtest 2026-11-06): a win with nothing after it looked like a bug.
			var far: Array = []
			for l: HeroState in losers:
				far.append(l.id)
			s.event("out_of_reach", {"hero": w.id, "losers": far})
			continue
		# "After winning, may deal no DMG": the owner decides before the loser does.
		if fx.hold_hit_effect(s, w) != null:
			fx.offer_hold_hit(s, w)
		var loser_owner: int = s.hero(str(targets[0])).owner
		var amount: int = stat(s, w, "dmg")
		# An Assist that may go to the graveyard in place of a small hit is offered first.
		fx.offer_shields(s, targets, amount)
		# FULL_HIT (Divine Departure, 2026-11-05): the whole hit lands on the hero, none on cards from the hand.
		var min_hero: int = amount if fx.full_hit(s, w) else hero_share(amount)
		s.pending.append({
			"type": DECISION_DAMAGE, "player": loser_owner, "winner": w.id,
			"amount": amount, "targets": targets, "min_hero": min_hero,
		})


## After every damage decision: knockback, then the next battle.
func _finish_battle(s: GameState, index: int) -> void:
	var b: Dictionary = s.battles[index]
	if JsonUtil.as_bool(b.get("resolved", false)):
		return
	b["resolved"] = true
	if JsonUtil.as_bool(b.get("tie", false)):
		_ring_out_fled(s, _battle_heroes(s, b))
		_check_win(s)
		return
	var best: int = JsonUtil.as_int(b.get("winner_team", -1), -1)
	var members: Array[HeroState] = _battle_heroes(s, b)
	var winners: Array[HeroState] = []
	var losers: Array[HeroState] = []
	for h: HeroState in members:
		if s.team_of(h.owner) == best:
			winners.append(h)
		else:
			losers.append(h)
	fx.on_battle_done(s, winners, members)
	# "After the Battle, they are ringed out": a full ring-out, before any knockback.
	_ring_out_fled(s, members)
	var kb: int = 0
	for w: HeroState in winners:
		kb = maxi(kb, stat(s, w, "kb") * (2 if w.has_status("hold_hit") else 1))
	for l: HeroState in losers:
		if not l.is_on_map():
			continue
		var from: HeroState = null
		for w: HeroState in winners:
			if in_range(s, w, l) and (from == null or Hex.distance(w.hex, l.hex) < Hex.distance(from.hex, l.hex)):
				from = w
		if from == null:
			continue
		knockback(s, l, Hex.direction_towards(from.hex, l.hex), kb, best)
	for h: HeroState in members:
		h.tie_turns = 0
		h.locked_with = PackedStringArray()
	_check_win(s)


func _ring_out_fled(s: GameState, members: Array[HeroState]) -> void:
	for h: HeroState in members:
		if h.has_status("flee") and h.is_on_map():
			h.statuses.erase("flee")
			h.tie_turns = 0
			h.locked_with = PackedStringArray()
			var fled_from: StageState = begin_move(s, h)
			ring_out(s, h, "fled")
			end_move(s, h, fled_from, -1)


func _battle_tie(s: GameState, members: Array[HeroState]) -> void:
	var ids: PackedStringArray = PackedStringArray()
	for h: HeroState in members:
		ids.append(h.id)
	var turns: int = 0
	for h: HeroState in members:
		turns = maxi(turns, h.tie_turns)
	turns += 1
	if turns >= s.settings.max_tie_turns:
		# Second tie: everyone flies back towards their own side for the other side's full KB.
		var kb_of_team: Dictionary[int, int] = {}
		for h: HeroState in members:
			var t: int = s.team_of(h.owner)
			kb_of_team[t] = maxi(JsonUtil.as_int(kb_of_team.get(t, 0)), stat(s, h, "kb"))
		for h: HeroState in members:
			var t: int = s.team_of(h.owner)
			var kb: int = 0
			for other_t: int in kb_of_team:
				if other_t != t:
					kb = maxi(kb, kb_of_team[other_t])
			var by_team: int = -1
			for other_t: int in kb_of_team:
				if other_t != t:
					by_team = other_t
			h.tie_turns = 0
			h.locked_with = PackedStringArray()
			knockback(s, h, 1 if t == 0 else 4, kb, by_team)
		s.event("battle_tie_break", {"heroes": Array(ids)})
		return
	for h: HeroState in members:
		h.tie_turns = turns
		h.locked_with = PackedStringArray()
		for id: String in ids:
			if id != h.id:
				h.locked_with.append(id)
	s.event("battle_locked", {"heroes": Array(ids), "turns": turns})


# =====================================================================================
# Damage, knockback, KO, ring-out
# =====================================================================================

## Damage to a hero, after "takes ±N DMG from all sources" modifiers (unless unblockable).
## `by`: who or what dealt it (a hero id, "wall", "trap", "ring_out"), `card`: the card that did, for the log.
func hero_damage(s: GameState, h: HeroState, amount: int, unblockable: bool = false, by: String = "", card: String = "") -> void:
	if h == null or h.is_ko() or amount <= 0:
		return
	if h.has_status("stone"):
		s.event("damage", {"hero": h.id, "amount": 0, "hp": h.hp, "blocked": "stone"})
		return
	# A hit of that size was bought off this turn (an Assist put into the graveyard instead).
	for i: int in s.turn_mods.size():
		var pm: Dictionary = s.turn_mods[i]
		if str(pm.get("kind", "")) == "prevent" and str(pm.get("hero", "")) == h.id and amount <= JsonUtil.as_int(pm.get("max", 0)):
			s.turn_mods.remove_at(i)
			s.event("damage", {"hero": h.id, "amount": 0, "hp": h.hp, "blocked": "prevented"})
			return
	if not unblockable:
		# Less damage taken never brings a hit under 1 (Marko 2026-11-08: Kaido paid 0 for a
		# ring-out); more damage taken adds as before.
		var mod: int = fx.damage_mod(s, h)
		amount = maxi(amount + mod, MIN_HIT if mod < 0 else 0)
	var info: Dictionary = {"hero": h.id, "amount": maxi(amount, 0), "hp": h.hp}
	if not by.is_empty():
		info["by"] = by
	if not card.is_empty():
		info["card"] = card
	if amount <= 0:
		s.event("damage", info)
		return
	h.hp -= amount
	info["hp"] = h.hp
	s.event("damage", info)
	if h.hp <= 0 and fx.save_from_ko(s, h):
		# "The first time one of your Heroes would be KO'd, they stay at 1 HP instead."
		h.hp = 1
		s.event("saved", {"hero": h.id})
		return
	if h.hp <= 0:
		h.hp = 0
		var was: StageState = begin_move(s, h)
		knock_out(s, h)
		var source: HeroState = s.hero(by)
		end_move(s, h, was, s.team_of(source.owner) if source != null else -1)


func heal(s: GameState, h: HeroState, amount: int) -> void:
	h.hp = mini(h.hp + amount, max_hp(s, h))


## A lost battle's damage: at least half of it (rounded up) lands on the hero; the rest the loser
## may take as cards from the hand, one card per DMG (Marko, 2026-11-02). The deck
## never takes damage and the match is never lost by running out of cards.
static func hero_share(amount: int) -> int:
	return (amount + 1) / 2


## Cards from the hand to the graveyard in place of damage (one per DMG); `by` is the hitter.
func hand_damage(s: GameState, p: PlayerState, cards: PackedStringArray, by: String = "") -> void:
	if cards.is_empty():
		return
	for cid: String in cards:
		var at: int = p.hand.find(cid)
		if at < 0:
			continue
		p.hand.remove_at(at)
		p.graveyard.append(cid)
	var info: Dictionary = {"player": p.slot, "cards": Array(cards), "amount": cards.size(), "hand": p.hand.size()}
	if not by.is_empty():
		info["by"] = by
	s.event("hand_damage", info)


func knock_out(s: GameState, h: HeroState) -> void:
	h.zone = HeroState.ZONE_KO
	var p: PlayerState = s.player(h.owner)
	for cid: String in h.equipment:
		p.graveyard.append(cid)
	for cid: String in h.evolutions:
		p.graveyard.append(cid)
	if not h.temp_evo.is_empty():
		p.graveyard.append(h.temp_evo)
	h.equipment = PackedStringArray()
	h.evolutions = PackedStringArray()
	h.temp_evo = ""
	h.temp_until = 0
	_drop_cores(s, h)
	h.statuses.clear()
	h.stun_by = ""
	h.tie_turns = 0
	h.locked_with = PackedStringArray()
	_lost_active(s, h)
	s.event("ko", {"hero": h.id})
	_release_stunned_by(s, h)


func ring_out(s: GameState, h: HeroState, reason: String) -> void:
	h.zone = HeroState.ZONE_STRIP
	var p: PlayerState = s.player(h.owner)
	for cid: String in h.equipment:
		p.graveyard.append(cid)
	h.equipment = PackedStringArray()
	_scatter_cores(s, h)
	h.tie_turns = 0
	h.locked_with = PackedStringArray()
	_lost_active(s, h)
	s.event("ring_out", {"hero": h.id, "reason": reason})
	_release_stunned_by(s, h)
	# "If an Opponent's Hero is ringed out in this Battle Phase, draw 1 card": once, for whoever armed it.
	if s.phase == GameState.PHASE_BATTLE:
		for i: int in s.turn_mods.size():
			var rm: Dictionary = s.turn_mods[i]
			if str(rm.get("kind", "")) == "ring_out_draw" and s.team_of(JsonUtil.as_int(rm.get("player", 0))) != s.team_of(h.owner):
				s.turn_mods.remove_at(i)
				draw(s, s.player(JsonUtil.as_int(rm.get("player", 0))), JsonUtil.as_int(rm.get("amount", 1)))
				break
	# Every ring-out costs 1 DMG (Marko 2026-11-07, in place of wall damage): with a card in the
	# hand the player may discard one instead (the usual damage decision, nothing has to land on
	# the hero); with none it lands at once. A hero at 1 HP can be knocked out by it.
	if s.player(h.owner).hand.is_empty():
		hero_damage(s, h, RING_OUT_DAMAGE, false, "ring_out")
	else:
		s.pending.append({"type": DECISION_DAMAGE, "player": h.owner, "winner": "", "by": "ring_out",
			"amount": RING_OUT_DAMAGE, "targets": [h.id], "min_hero": 0, "ring_out": true})


## Cores fall off a ringed-out hero and the game throws them onto random free hexes
## (not on a stage); each keeps its face state.
func _scatter_cores(s: GameState, h: HeroState) -> void:
	for cid: String in h.cores:
		var c: CoreState = s.core(cid)
		if c == null:
			continue
		c.holder = ""
		c.picked_by = ""
		var options: Array[Vector2i] = []
		for a: Vector2i in s.map().cells():
			if _core_spot_error(s, c, a, -1).is_empty():
				options.append(a)
		if options.is_empty():
			c.place = CoreState.IN_INVENTORY
			s.player(c.owner).inventory.append(c.id)
			continue
		c.hex = options[s.random_int(options.size())]
		c.place = CoreState.ON_FIELD
		s.event("core_scattered", {"core": c.id, "hex": Hex.to_json(c.hex)})
	h.cores = PackedStringArray()


## Cores fall off a KO'd hero and go back to their owners, who put them anywhere in their
## own half.
func _drop_cores(s: GameState, h: HeroState) -> void:
	for cid: String in h.cores:
		var c: CoreState = s.core(cid)
		if c == null:
			continue
		c.place = CoreState.IN_INVENTORY
		c.holder = ""
		c.picked_by = ""
		s.player(c.owner).inventory.append(c.id)
	h.cores = PackedStringArray()


## The activated hero leaving the map mid-turn leaves its player with Pass or an Assist (pass_only); in a battle,
## which battle it was is kept too.
func _lost_active(s: GameState, h: HeroState) -> void:
	if s.active.get(h.owner, "") == h.id and not s.only_pass.has(h.owner):
		s.only_pass.append(h.owner)
		if s.phase == GameState.PHASE_BATTLE and s.battle_index >= 0 and s.battle_index < s.battles.size():
			s.only_pass_battle[h.owner] = s.battle_index


const PASS_ONLY_WHY: String = "your activated hero is out: pass, or play an Assist"


## Whether `slot` is down to Pass or an Assist now (GDD 10; Marko 2026-11-13): its activated hero was
## knocked out or rung out this turn. Outside the Battle phase that holds until the turn ends: cards go to the
## activated hero there, and it is gone. In the Battle phase it holds only in the battle it fell in; in the
## battles after it (all of them, when it fell before the Battle phase) the player's other heroes get their cards
## and use their abilities as ever. An Assist goes on no hero, so it may always be played (its colour is the
## activated hero's, gone or not: _play).
func pass_only(s: GameState, slot: int) -> bool:
	if not s.only_pass.has(slot):
		return false
	if s.phase != GameState.PHASE_BATTLE:
		return true
	return s.battle_index >= 0 and s.only_pass_battle.get(slot, -1) == s.battle_index


## Grid knockback: `steps` hexes in direction `dir`. A wall or hero stops it (no damage,
## Marko 2026-11-07); leaving the map is a ring-out.
## Knockback (GDD 10). In the "physics" mode (the game) the hero is not moved here: the
## knockback waits in `pending_knockbacks` for the sim (apply_knockback). On the grid it goes
## hex by hex, stopped by walls and heroes.
## `by_team`: the team whose doing it is (a battle's winners, an effect's player), for the
## energy claim variant (end_move).
func knockback(s: GameState, h: HeroState, dir: int, steps: int, by_team: int = -1) -> void:
	if steps <= 0 or not h.is_on_map() or has_status(s, h, "immune_kb"):
		return
	if s.settings.knockback == "physics":
		s.pending_knockbacks.append({"hero": h.id, "dir": dir, "steps": steps, "by_team": by_team})
		s.event("knockback_launched", {"hero": h.id, "dir": dir, "steps": steps})
		return
	var was: StageState = begin_move(s, h)
	_grid_knockback(s, h, dir, steps)
	end_move(s, h, was, by_team)


func _grid_knockback(s: GameState, h: HeroState, dir: int, steps: int) -> void:
	var start: Vector2i = h.hex
	var pos: Vector2i = h.hex
	var left: int = steps
	while left > 0:
		var next: Vector2i = Hex.neighbor(pos, dir)
		var off_map: bool = false
		var blocked: bool = false
		for cell: Vector2i in Hex.spiral(next, 1 if h.big else 0):
			if not s.map().contains(cell):
				off_map = true
			elif s.wall_at(cell) or s.hero_at(cell, h) != null:
				blocked = true
		if off_map:
			h.hex = next
			s.event("knockback", {"hero": h.id, "from": Hex.to_json(start), "to": Hex.to_json(next), "steps": steps - left + 1})
			ring_out(s, h, "knockback")
			return
		if blocked:
			break
		pos = next
		left -= 1
	h.hex = pos
	s.event("knockback", {"hero": h.id, "from": Hex.to_json(start), "to": Hex.to_json(pos), "steps": steps - left})
	arrive(s, h)


# =====================================================================================
# End of turn
# =====================================================================================

func _end_phase(s: GameState) -> void:
	if not s.settings.energy_claims():
		_check_claims(s)
	for h: HeroState in s.heroes:
		var gone: PackedStringArray = PackedStringArray()
		for name: String in h.statuses:
			if h.statuses[name] > 0:
				h.statuses[name] -= 1
				if h.statuses[name] == 0:
					gone.append(name)
		for name: String in gone:
			h.statuses.erase(name)
			if name == "stun":
				h.stun_by = ""
	_check_win(s)
	if s.is_over():
		return
	_expire_temp_evolutions(s)
	_drop_tokens(s)
	s.event("turn_end")
	s.turn += 1
	s.initiative = _next_slot(s, s.initiative)


## Temporary evolutions whose last turn this was go to the graveyard (GDD 10, 2026-11-15).
func _expire_temp_evolutions(s: GameState) -> void:
	for h: HeroState in s.heroes:
		if not h.temp_evo.is_empty() and s.turn >= h.temp_until:
			_drop_temp_evolution(s, h, "expired")


## Takes a hero's temporary evolution off (card to the graveyard): the hero is back on the level under it.
## The damage is remembered (Marko 2026-11-15): 10/12 that was 6/8 in the form is 10/12 again; the change
## itself never kills (1 HP at least). `why`: expired | replaced | evolved | removed.
func _drop_temp_evolution(s: GameState, h: HeroState, why: String) -> void:
	if h.temp_evo.is_empty():
		return
	var cid: String = h.temp_evo
	var damage: int = max_hp(s, h) - h.hp
	h.temp_evo = ""
	h.temp_until = 0
	s.player(h.owner).graveyard.append(cid)
	h.hp = clampi(max_hp(s, h) - damage, 1, max_hp(s, h))
	s.event("evolution_removed", {"card": cid, "hero": h.id, "temporary": true, "why": why})
	_drop_unfit_equipment(s, h)


## Claims (GDD 6): activated hero stayed on the stage; two heroes on it without a battle;
## or the winner of the battle fought on it.
func _check_claims(s: GameState) -> void:
	for st: StageState in s.stages:
		if not st.placed or st.is_claimed():
			continue
		var on: Array[HeroState] = s.heroes_on_stage(st)
		if on.is_empty():
			continue
		var claimer: int = -1
		var teams: Dictionary[int, int] = {}
		for h: HeroState in on:
			var t: int = s.team_of(h.owner)
			teams[t] = teams.get(t, 0) + 1
		if teams.size() >= 2:
			for b: Dictionary in s.battles:
				var ids: PackedStringArray = JsonUtil.as_strings(b.get("heroes", []))
				var wt: int = JsonUtil.as_int(b.get("winner_team", -1), -1)
				if wt < 0:
					continue
				for h: HeroState in on:
					if ids.has(h.id) and s.team_of(h.owner) == wt:
						claimer = h.owner
						break
				if claimer >= 0:
					break
		else:
			# Stay: the same activated hero must stay on the stage two turns in a row.
			var stayer: HeroState = null
			for slot: int in s.active:
				var a: HeroState = s.active_hero(slot)
				if a != null and on.has(a) and s.choices.has(slot) and not s.choices[slot]:
					stayer = a
			if stayer != null:
				if st.stay_hero == stayer.id and st.stay_turn == s.turn - 1:
					claimer = stayer.owner
				else:
					st.stay_hero = stayer.id
					st.stay_turn = s.turn
					s.event("stage_stay", {"stage": st.id, "hero": stayer.id})
			if claimer < 0:
				var by_owner: Dictionary[int, int] = {}
				for h: HeroState in on:
					by_owner[h.owner] = by_owner.get(h.owner, 0) + 1
				for slot: int in by_owner:
					if by_owner[slot] >= 2 and not _battled_on(s, on):
						claimer = slot
		if claimer >= 0 and _claim_blocked(s, claimer, st):
			s.event("claim_blocked", {"stage": st.id, "player": claimer})
			claimer = -1
		if claimer >= 0:
			st.claimed_by = claimer
			st.claimed_heroes = _claimers_on(s, st, claimer)
			st.terrain_until_turn = s.turn + 1
			s.event("stage_claimed", {"stage": st.id, "player": claimer, "heroes": Array(st.claimed_heroes)})


## The heroes of the side of `slot` that stand on a stage: who took it, for its flag.
func _claimers_on(s: GameState, st: StageState, slot: int) -> PackedStringArray:
	var out := PackedStringArray()
	for h: HeroState in s.heroes_on_stage(st):
		if s.team_of(h.owner) == s.team_of(slot):
			out.append(h.id)
	return out


# =====================================================================================
# Energy claim variant (Marko 2026-11-02, MatchSettings.CLAIM_ENERGY, under test)
# =====================================================================================

## End phase: each player's energy left goes into the unclaimed stages its own heroes stand on.
## A stage with heroes of two teams on it is contested: nobody puts energy in. One stage takes
## it all; more than one asks the player for a split (DECISION_STAGE_ENERGY). Energy that finds
## no stage is lost, as it always is at the end of the turn.
func _bank_energy(s: GameState) -> void:
	s.energy_banked = true
	for st: StageState in s.stages:
		if contested(s, st):
			s.event("stage_contested", {"stage": st.id})
	for slot: int in _active_slots(s):
		var p: PlayerState = s.player(slot)
		if p.energy <= 0:
			continue
		var open: Array[StageState] = energy_stages(s, slot)
		if open.is_empty():
			continue
		if open.size() == 1:
			_put_energy(s, slot, open[0], p.energy)
			p.energy = 0
			continue
		var ids: Array = []
		for st: StageState in open:
			ids.append(st.id)
		s.pending.append({"type": DECISION_STAGE_ENERGY, "player": slot, "energy": p.energy,
			"stages": ids, "goal": s.settings.stage_goal})
	# Claims are looked at when all the energy is in (code review 2026-11-13): with a split still to be made, a
	# full ring was claimed before the other side's energy could take places in it, and that energy then went
	# into a claimed stage and was lost. The last split answered looks at the claims (_apply_decision).
	for d: Dictionary in s.pending:
		if str(d.get("type", "")) == DECISION_STAGE_ENERGY:
			return
	_claim_by_energy(s)


## Unclaimed stages `slot` can put energy into now: one of its own heroes stands on it and no
## hero of another team does.
func energy_stages(s: GameState, slot: int) -> Array[StageState]:
	var out: Array[StageState] = []
	for st: StageState in s.stages:
		if not st.placed or st.is_claimed() or contested(s, st):
			continue
		for h: HeroState in s.heroes_on_stage(st):
			if h.owner == slot:
				out.append(st)
				break
	return out


## An unclaimed stage with heroes of two teams on it.
func contested(s: GameState, st: StageState) -> bool:
	if not st.placed or st.is_claimed():
		return false
	var teams: Dictionary[int, bool] = {}
	for h: HeroState in s.heroes_on_stage(st):
		teams[s.team_of(h.owner)] = true
	return teams.size() >= 2


## The energy in `st` of every player on `team` (the shared ring is per team).
func stage_energy_of_team(s: GameState, st: StageState, team: int) -> int:
	var total: int = 0
	for slot: int in st.progress:
		if s.team_of(slot) == team:
			total += st.progress[slot]
	return total


## The shared ring's empty places in `st`.
func ring_free(s: GameState, st: StageState) -> int:
	var total: int = 0
	for slot: int in st.progress:
		total += st.progress[slot]
	return maxi(s.settings.stage_goal - total, 0)


## The shared ring (CLAIM_RING): `n` energy of `slot` into `st`. It fills the empty places first;
## with none left, each energy turns one place of another team into this player's (from whoever
## holds the most, the lower slot on a tie). What is left when the ring is all its team's is lost.
func _put_energy_ring(s: GameState, slot: int, st: StageState, n: int) -> void:
	var goal: int = s.settings.stage_goal
	var team: int = s.team_of(slot)
	var filled: int = mini(n, ring_free(s, st))
	var left: int = n - filled
	var taken: int = 0
	while left > 0:
		var from: int = -1
		var slots: Array = st.progress.keys()
		slots.sort()
		for other: int in slots:
			if s.team_of(other) != team and st.progress[other] > 0 and (from < 0 or st.progress[other] > st.progress[from]):
				from = other
		if from < 0:
			break
		var part: int = mini(left, st.progress[from])
		st.progress[from] -= part
		taken += part
		left -= part
	st.progress[slot] = st.progress_of(slot) + filled + taken
	var p: PlayerState = s.player(slot)
	if p != null:
		# Everything put in counts for the tie-break, places taken too (Marko 2026-11-10).
		p.energy_invested += n
	var info: Dictionary = {"player": slot, "stage": st.id, "amount": filled + taken,
		"progress": stage_energy_of_team(s, st, team), "goal": goal}
	if taken > 0:
		info["taken"] = taken
	if left > 0:
		info["wasted"] = left
	s.event("stage_energy", info)


## `n` energy of `slot` into `st`, up to the goal (more is lost).
func _put_energy(s: GameState, slot: int, st: StageState, n: int) -> void:
	if st == null or n <= 0:
		return
	if s.settings.shared_ring():
		_put_energy_ring(s, slot, st, n)
		return
	var goal: int = s.settings.stage_goal
	var have: int = st.progress_of(slot)
	var added: int = mini(n, maxi(goal - have, 0))
	st.progress[slot] = have + added
	var p: PlayerState = s.player(slot)
	if p != null:
		p.energy_invested += n
	var info: Dictionary = {"player": slot, "stage": st.id, "amount": added, "progress": have + added, "goal": goal}
	if n > added:
		info["wasted"] = n - added
	s.event("stage_energy", info)


## A stage is claimed by the first player whose energy in it reached the goal (a "cannot claim"
## effect holds it back until a later End phase).
func _claim_by_energy(s: GameState) -> void:
	for st: StageState in s.stages:
		if st.is_claimed():
			continue
		var slots: Array = st.progress.keys()
		slots.sort()
		for slot: int in slots:
			# The shared ring is claimed by a team holding all of it.
			var have: int = stage_energy_of_team(s, st, s.team_of(slot)) if s.settings.shared_ring() else st.progress[slot]
			if have < s.settings.stage_goal or st.progress[slot] <= 0:
				continue
			if _claim_blocked(s, slot, st):
				s.event("claim_blocked", {"stage": st.id, "player": slot})
				continue
			st.claimed_by = slot
			st.claimed_heroes = _claimers_on(s, st, slot)
			st.terrain_until_turn = s.turn + 1
			s.event("stage_claimed", {"stage": st.id, "player": slot, "energy": st.progress[slot], "heroes": Array(st.claimed_heroes)})
			break


## The stage under `h` as one of its moves begins; pair with end_move.
func begin_move(s: GameState, h: HeroState) -> StageState:
	if h == null:
		return null
	_moving[h.id] = _moving.get(h.id, 0) + 1
	return s.stage_at(h.hex) if h.is_on_map() else null


## A move of `h` that began on stage `was` is over. With the energy claim variant, a hero that
## left an unclaimed stage through team `by_team`'s doing (another team: a hit, a knockback, a
## ring-out, a KO, an effect) costs its player half the energy in that stage, rounded down;
## leaving by its own roll (or its own side's doing) costs nothing, and so does it while another
## of the player's heroes still stands there (Marko 2026-11-02).
func end_move(s: GameState, h: HeroState, was: StageState, by_team: int) -> void:
	if h == null:
		return
	var depth: int = _moving.get(h.id, 1) - 1
	if depth > 0:
		_moving[h.id] = depth
		return
	_moving.erase(h.id)
	if was == null or not s.settings.energy_claims() or was.is_claimed():
		return
	if h.is_on_map() and was.covers(h.hex):
		return
	if by_team < 0 or by_team == s.team_of(h.owner):
		return
	var have: int = was.progress_of(h.owner)
	var lost: int = have / 2
	for o: HeroState in s.heroes_on_stage(was):
		if o != h and o.owner == h.owner:
			lost = 0
	if lost > 0:
		was.progress[h.owner] = have - lost
	s.event("stage_knocked_off", {"hero": h.id, "stage": was.id, "player": h.owner, "lost": lost,
		"progress": have - lost, "goal": s.settings.stage_goal, "by_team": by_team})


## "Cannot claim" this turn: the player (NO_CLAIM OPP), or every hero of the player standing on
## that stage carries the "no_claim" status (NO_CLAIM on heroes, Conqueror's Haki 2026-11-05).
func _claim_blocked(s: GameState, slot: int, st: StageState) -> bool:
	for m: Dictionary in s.turn_mods:
		if str(m.get("kind", "")) == "no_claim" and JsonUtil.as_int(m.get("player", -1)) == slot:
			return true
	var mine: int = 0
	var blocked: int = 0
	for h: HeroState in s.heroes_on_stage(st):
		if h.owner == slot:
			mine += 1
			if h.has_status("no_claim"):
				blocked += 1
	return mine > 0 and blocked == mine


func _battled_on(s: GameState, on: Array[HeroState]) -> bool:
	for b: Dictionary in s.battles:
		var ids: PackedStringArray = JsonUtil.as_strings(b.get("heroes", []))
		for h: HeroState in on:
			if ids.has(h.id):
				return true
	return false


func claimed_count(s: GameState, slot: int) -> int:
	var n: int = 0
	for st: StageState in s.stages:
		if st.claimed_by == slot:
			n += 1
	return n


func _check_win(s: GameState) -> void:
	if s.is_over():
		return
	var winners: PackedInt32Array = PackedInt32Array()
	var teams_alive: Dictionary[int, bool] = {}
	for h: HeroState in s.heroes:
		if not h.is_ko() and not s.player(h.owner).surrendered:
			teams_alive[s.team_of(h.owner)] = true
	for p: PlayerState in s.players:
		if p.surrendered:
			continue
		var won: bool = claimed_count(s, p.slot) >= s.settings.stages_to_win
		if teams_alive.size() == 1 and teams_alive.has(p.team):
			won = true
		if won and not winners.has(p.team):
			winners.append(p.team)
	if winners.size() == 1:
		for p: PlayerState in s.players:
			if p.team == winners[0]:
				var reason: String = "stages" if claimed_count(s, p.slot) >= s.settings.stages_to_win else "ko"
				_end_match(s, p.slot, reason)
				return
	elif winners.size() > 1:
		# Energy claims (Marko 2026-11-04): when every side reaches its stages in the same End phase, the side
		# that put more energy into stages over the whole match (over the goal and later lost included) wins;
		# equal is a draw.
		var by_stages: bool = s.settings.energy_claims()
		for p: PlayerState in s.players:
			if winners.has(p.team) and claimed_count(s, p.slot) < s.settings.stages_to_win:
				by_stages = false
		if by_stages:
			var totals: Dictionary[int, int] = {}
			for p: PlayerState in s.players:
				totals[p.team] = totals.get(p.team, 0) + p.energy_invested
			var best: int = -1
			var best_total: int = -1
			var tied: bool = false
			for team: int in winners:
				var t: int = totals.get(team, 0)
				if t > best_total:
					best_total = t
					best = team
					tied = false
				elif t == best_total:
					tied = true
			var shown: Dictionary = {}
			for team: int in winners:
				shown[str(team)] = totals.get(team, 0)
			s.event("tie_broken", {"by": "energy", "totals": shown, "winner_team": -1 if tied else best})
			if not tied:
				for p: PlayerState in s.players:
					if p.team == best:
						_end_match(s, p.slot, "stages_energy")
						return
		_end_match(s, -1, "draw")


func _end_match(s: GameState, winner_slot: int, reason: String) -> void:
	s.winner = winner_slot
	s.result = reason
	s.event("match_end", {"winner": winner_slot, "result": reason})
	s.phase = GameState.PHASE_OVER


# =====================================================================================
# Queries
# =====================================================================================

## The card whose stats the hero uses: its own, or the top evolution's; a temporary evolution is over both.
func stat_card(h: HeroState) -> CardDef:
	if not h.temp_evo.is_empty():
		var temp: CardDef = catalog.get_card(h.temp_evo)
		if temp != null:
			return temp
	if not h.evolutions.is_empty():
		var evo: CardDef = catalog.get_card(h.evolutions[h.evolutions.size() - 1])
		if evo != null:
			return evo
	return catalog.get_card(h.card_id)


## One current stat: "hp" (max), "dmg", "pwr", "rng" or "kb": the flat value plus what
## passive effects in play add. Never below 0 (a Debuff core can pull a small stat under).
func stat(s: GameState, h: HeroState, key: String) -> int:
	# "has 0 Power and cannot take DMG this turn".
	if key == "pwr" and h.has_status("stone"):
		return 0
	return maxi(0, stat_flat(s, h, key) + fx.passive_stat(s, h, key))


## The printed value of the hero's current card (range after the match's range change), before
## anything adds to it: the HUD colours a stat that differs.
func base_stat(s: GameState, h: HeroState, key: String) -> int:
	var card: CardDef = stat_card(h)
	if card == null:
		return 0
	match key:
		"hp":
			return card.hp
		"dmg":
			return card.dmg
		"pwr":
			return card.pwr
		"rng":
			return s.settings.adjust_rng(card.rng)
		"kb":
			return card.kb
	return 0


## The card's value plus equipment and active core `bonus` fields plus bonuses that last the
## phase or the turn; no passive effects (they use this to avoid asking about themselves).
func stat_flat(s: GameState, h: HeroState, key: String) -> int:
	var card: CardDef = stat_card(h)
	if card == null:
		return 0
	var base: int = 0
	match key:
		"hp":
			base = card.hp
		"dmg":
			base = card.dmg
		"pwr":
			base = card.pwr
		"rng":
			base = s.settings.adjust_rng(card.rng)
		"kb":
			base = card.kb
	for eid: String in h.equipment:
		var e: CardDef = catalog.get_card(eid)
		if e != null and equipment_works(h, eid):
			base += e.bonus.get(key, 0)
	# A core counts while it sits in one of the hero's slots (GDD 7.4): a Debuff hurts whoever
	# picked it up.
	for cid: String in h.cores:
		var c: CoreState = s.core(cid)
		var core: CardDef = catalog.get_card(c.card_id) if c != null else null
		if core != null:
			base += core.bonus.get(key, 0)
	base += h.phase_bonus.get(key, 0) + h.turn_bonus.get(key, 0)
	for b: Dictionary in s.stage_buffs:
		if str(b.get("hero", "")) == h.id and str(b.get("stat", "")) == key and _stage_buff_holds(s, b):
			base += JsonUtil.as_int(b.get("amount", 0))
	return base


func _clear_phase_bonuses(s: GameState) -> void:
	for h: HeroState in s.heroes:
		if not h.phase_bonus.is_empty():
			h.phase_bonus.clear()
			clamp_hp(s, h)


## A stage reveal bonus counts while its hero stands on that stage and the stage is unclaimed.
func _stage_buff_holds(s: GameState, b: Dictionary) -> bool:
	var h: HeroState = s.hero(str(b.get("hero", "")))
	var st: StageState = s.stage(str(b.get("stage", "")))
	return h != null and st != null and h.is_on_map() and st.covers(h.hex) and not st.is_claimed()


## Current HP never exceeds the current max (GDD 10: losing an HP source lowers HP to the
## new max, never below it).
func clamp_hp(s: GameState, h: HeroState) -> void:
	h.hp = mini(h.hp, max_hp(s, h))


# =====================================================================================
# Playing cards (step 2b: no text effects yet)
# =====================================================================================

## Own heroes a card may be played for right now: the activated hero, or in a battle the
## own heroes taking part in it. Cards are played in the colour of these heroes.
func card_context_heroes(s: GameState, slot: int) -> Array[HeroState]:
	var out: Array[HeroState] = []
	if s.phase == GameState.PHASE_BATTLE:
		# Only the heroes of the battle being fought; between battles (a core being put back,
		# a knockback) nobody, not the activated hero (playtest 2026-10-30).
		if s.battle_index >= 0 and s.battle_index < s.battles.size():
			for h: HeroState in _battle_heroes(s, s.battles[s.battle_index]):
				if h.owner == slot:
					out.append(h)
		return out
	var a: HeroState = s.active_hero(slot)
	if a != null and not a.is_ko():
		out.append(a)
	return out


## play_card {"card": id, "hero": target id (optional when only one fits), "replace": assist id}.
func _play_card(s: GameState, m: Move) -> String:
	return _play(s, m.player, m.str_arg("card"), m.str_arg("hero"), false, null, m.str_arg("replace"), m.str_arg("wearer"))


## FREE_PLAY: a card from the hand goes on `on` without paying its cost (colour and context
## rules do not apply; the card's own limits and phase lock do).
func play_free(s: GameState, slot: int, cid: String, on: HeroState) -> String:
	return _play(s, slot, cid, on.id, true, on)


## Why play_free would refuse `cid` on `on` ("" when it would go), tried on a copy.
func free_play_error(s: GameState, slot: int, cid: String, on: HeroState) -> String:
	var copy: GameState = GameState.from_dict(s.to_dict())
	return play_free(copy, slot, cid, copy.hero(on.id))


## `wearer`: for an Equipment that goes on another friendly hero (EQUIP_OTHER), the hero that takes it.
func _play(s: GameState, slot: int, cid: String, wanted: String, free: bool, forced: HeroState,
		replace: String = "", wearer: String = "") -> String:
	var p: PlayerState = s.player(slot)
	# A token (GDD 10, 2026-11-14) is played like a card from the hand, from beside it.
	if not p.hand.has(cid) and not p.tokens.has(cid):
		return "card is not in your hand"
	var card: CardDef = catalog.get_card(cid)
	if card == null:
		return "unknown card"
	if not card.is_ready():
		return "card effects are not ready yet"
	var phase_lock: String = _play_phase(card)
	if not phase_lock.is_empty() and phase_lock != s.phase.to_upper():
		return "playable in the %s phase" % phase_lock.to_lower()
	var same_colour: Array[HeroState] = []
	if forced != null:
		same_colour.append(forced)
	else:
		var context: Array[HeroState] = card_context_heroes(s, slot)
		if context.is_empty() and card.type == "Assist" and pass_only(s, slot) and s.active_hero(slot) != null:
			# Down to Pass or an Assist: the Assist is played in the colour of the activated hero that is gone.
			context.append(s.active_hero(slot))
		if context.is_empty():
			return "no hero to play cards for"
		# A colorless card is for a hero of any colour (its bonus is worked out per hero).
		for h: HeroState in context:
			var hc: CardDef = catalog.get_card(h.card_id)
			if hc != null and card.plays_for_color(hc.color):
				same_colour.append(h)
		if same_colour.is_empty():
			if s.phase == GameState.PHASE_BATTLE:
				return "needs a %s hero in this battle" % card.color
			return "needs an activated %s hero" % card.color
	# The first tag (GDD 10): the card goes only to a hero it names, or whose current traits fit.
	var fit: Array[HeroState] = []
	var unfit: String = ""
	for h: HeroState in same_colour:
		# "No cards can be played for X."
		if has_status(s, h, "no_cards"):
			unfit = "no cards can be played for %s" % hero_name(h)
			continue
		var v: Dictionary = FirstTag.play_verdict(catalog, card, catalog.get_card(h.card_id), stat_card(h), gained_tags(s, h))
		if JsonUtil.as_bool(v["ok"]):
			fit.append(h)
		else:
			unfit = str(v["why"])
	if fit.is_empty():
		return unfit
	same_colour = fit
	var target: HeroState = null
	if wanted.is_empty():
		if same_colour.size() == 1:
			target = same_colour[0]
		elif card.type != "Assist":
			return "say which hero: " + ", ".join(_ids(same_colour))
	else:
		for h: HeroState in same_colour:
			if h.id == wanted:
				target = h
		if target == null:
			return "that hero cannot take this card now"
	# The cost depends on the hero the card is played for (a colorless card's bonus): with no
	# target picked (an Assist), the cheapest of the heroes that fit.
	var cost: int = 0 if free else card_cost(s, p, card, target if target != null else _cheapest_for(s, p, card, same_colour))
	# A stage cursed by an opposing side: no Battle Phase cards for a hero standing on it, for the rest of the match.
	if s.phase == GameState.PHASE_BATTLE and target != null and target.is_on_map():
		var under: StageState = s.stage_at(target.hex)
		if under != null and under.cursed_by >= 0 and under.cursed_by != s.team_of(slot):
			return "no Battle Phase cards for a hero on that stage"
	var hp_before: int = target.hp if target != null else 0
	var had_phase: Dictionary = target.phase_bonus.duplicate() if target != null else {}
	var had_turn: Dictionary = target.turn_bonus.duplicate() if target != null else {}
	var gain_before: int = _bonus_pwr(target)
	# The cards in play as the card is played: they are the ones that see it (a hero's own card still answers the
	# Evolution that takes its place).
	var watchers: Array[Dictionary] = fx.sources(s)
	if cost > p.energy:
		return "not enough energy (%d, costs %d)" % [p.energy, cost]
	match card.type:
		"Equipment":
			# "Equip this to another friendly Hero in Range with {Tag}": the hero it is played for hands it on.
			var takes: HeroState = target
			var other: FxEffect = _effect_with(card, "EQUIP_OTHER")
			if other != null:
				var fits: Array[HeroState] = equip_other_options(s, target, card, other)
				if fits.is_empty():
					return "no other friendly hero in range that can take it"
				takes = null
				for h: HeroState in fits:
					if h.id == wearer or (wearer.is_empty() and fits.size() == 1):
						takes = h
				if takes == null:
					return "say who takes it: " + ", ".join(_ids(fits))
			if takes.equipment.size() >= s.settings.equipment_limit:
				return "hero already has %d equipment" % s.settings.equipment_limit
			if takes.equipment.has(cid):
				return "hero already has that equipment"
			# "As an additional cost, your Hero takes 3 DMG" on an Equipment: the hero that takes it pays, as it goes on.
			var gear_cost: int = _cost_damage(s, slot, takes, card)
			if gear_cost > 0 and takes.hp <= gear_cost:
				return "cannot pay %d damage" % gear_cost
			_take_from_hand(p, cid)
			takes.equipment.append(cid)
			s.event("equipped", {"card": cid, "hero": takes.id})
			if gear_cost > 0:
				hero_damage(s, takes, gear_cost, false, "", cid)
		"Evolution":
			if not target.is_on_map():
				return "a hero in the start zone cannot evolve"
			var hero_card: CardDef = catalog.get_card(target.card_id)
			if hero_card == null or hero_card.name != card.hero:
				return "this evolution is for %s" % card.hero
			# A temporary evolution goes on any level (GDD 10, 2026-11-15); one that stays goes level by level,
			# counted without the temporary one that may sit on top.
			if card.temp_turns <= 0 and card.evo != target.evolutions.size() + 1:
				return "needs evolution level %d first" % (card.evo - 1)
			# "As an additional cost, X takes 3 DMG" on an Evolution: paid as it goes on.
			var evo_cost: int = _cost_damage(s, slot, target, card)
			if evo_cost > 0 and target.hp <= evo_cost:
				return "cannot pay %d damage" % evo_cost
			_take_from_hand(p, cid)
			var damage: int = max_hp(s, target) - target.hp
			# Either kind takes the temporary one off first: a new temporary replaces it, an evolution that
			# stays goes on the level under it.
			if not target.temp_evo.is_empty():
				var old: String = target.temp_evo
				target.temp_evo = ""
				target.temp_until = 0
				s.player(target.owner).graveyard.append(old)
				s.event("evolution_removed", {"card": old, "hero": target.id, "temporary": true, "why": "replaced" if card.temp_turns > 0 else "evolved"})
			if card.temp_turns > 0:
				target.temp_evo = cid
				target.temp_until = s.turn + card.temp_turns - 1
				# The form itself never kills: 1 HP at least.
				target.hp = maxi(max_hp(s, target) - damage, 1)
				s.event("evolved", {"card": cid, "hero": target.id, "level": target.evolutions.size(), "temporary": true, "until": target.temp_until})
			else:
				target.evolutions.append(cid)
				target.hp = maxi(max_hp(s, target) - damage, 0)
				s.event("evolved", {"card": cid, "hero": target.id, "level": card.evo})
			_drop_unfit_equipment(s, target)
			if evo_cost > 0:
				hero_damage(s, target, evo_cost, false, "", cid)
		"Assist":
			if p.assists.has(cid):
				return "that assist is already in play"
			var comp_err: String = _companion_blocker(s, slot, target, card)
			if not comp_err.is_empty():
				return comp_err
			if p.assists.size() >= s.settings.assist_limit:
				var out: String = replace
				if not p.assists.has(out):
					return "choose an assist to replace: " + ", ".join(p.assists)
				p.assists.remove_at(p.assists.find(out))
				p.graveyard.append(out)
			_take_from_hand(p, cid)
			p.assists.append(cid)
			s.event("assist", {"card": cid, "player": slot})
			_note_played(s, slot, cid, "", {})
		"Action":
			if card.bonus.is_empty() and card.effects.is_empty():
				return "card effects are not ready yet"
			var extra: int = _cost_damage(s, slot, target, card)
			if extra > 0 and target.hp <= extra:
				return "cannot pay %d damage" % extra
			# An Action whose effect has nothing to work on (no hex for its wall, no core in reach)
			# is not played: it stays in the hand and costs nothing.
			var blocked: String = _requirement(s, slot, target, card)
			if blocked.is_empty():
				blocked = _play_blocker(s, slot, target, card)
			if not blocked.is_empty():
				return blocked
			_take_from_hand(p, cid)
			# The stat box, unless a bonus line says "instead" of it for this hero ("Yellow Bonus: … instead").
			var box: Dictionary[String, int] = {}
			if not fx.box_replaced(s, slot, target, card):
				box = card.bonus
			for key: String in box:
				target.add_bonus(target.phase_bonus, key, box[key])
			# A played token is gone: it never reaches the graveyard.
			if card.token:
				s.event("action", {"card": cid, "hero": target.id, "token": true})
			else:
				p.graveyard.append(cid)
				s.event("action", {"card": cid, "hero": target.id})
			_note_played(s, slot, cid, target.id, box)
		_:
			return "%s cards cannot be played" % card.type
	p.energy -= cost
	s.turn_plays.append({"player": slot, "card": cid, "hero": target.id if target != null else "", "phase": s.phase,
		"battle": s.battle_index if s.phase == GameState.PHASE_BATTLE else -1})
	_run_play_effects(s, slot, target, card)
	# Cards in play that watch for a card being played ("Whenever you play a {Fire} card, …").
	fx.on_card_played(s, slot, card, target, {"hp_before": hp_before, "pwr_gain": _bonus_pwr(target) - gain_before}, watchers)
	_note_gave(s, cid, target, had_phase, had_turn)
	return ""


## What a card played in the battle gave its hero, kept with the card in the battle's list: whatever undoes the
## card takes exactly that back.
func _note_gave(s: GameState, cid: String, target: HeroState, had_phase: Dictionary, had_turn: Dictionary) -> void:
	if target == null or s.phase != GameState.PHASE_BATTLE or s.battle_index < 0 or s.battle_index >= s.battles.size():
		return
	var played: Array = JsonUtil.as_array(s.battles[s.battle_index].get("played", []))
	for i: int in range(played.size() - 1, -1, -1):
		var x: Dictionary = played[i]
		if str(x.get("card", "")) == cid and str(x.get("hero", "")) == target.id and not x.has("gave_phase"):
			x["gave_phase"] = _bonus_diff(target.phase_bonus, had_phase)
			x["gave_turn"] = _bonus_diff(target.turn_bonus, had_turn)
			return


static func _bonus_diff(now: Dictionary, was: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in now:
		var d: int = JsonUtil.as_int(now[k]) - JsonUtil.as_int(was.get(k, 0))
		if d != 0:
			out[k] = d
	return out


## A card played in this battle is undone (Marko 2026-11-22): it loses the stats it gave and its effects that still
## wait ("If you win this Battle, …"); what already happened stays. `x` is its entry in the battle's list.
func undo_card(s: GameState, x: Dictionary) -> void:
	var h: HeroState = s.hero(str(x.get("hero", "")))
	if h != null:
		var gave_phase: Dictionary = JsonUtil.as_dict(x.get("gave_phase", x.get("bonus", {})))
		for k: Variant in gave_phase:
			h.add_bonus(h.phase_bonus, str(k), -JsonUtil.as_int(gave_phase[k]))
		var gave_turn: Dictionary = JsonUtil.as_dict(x.get("gave_turn", {}))
		for k: Variant in gave_turn:
			h.add_bonus(h.turn_bonus, str(k), -JsonUtil.as_int(gave_turn[k]))
		clamp_hp(s, h)
	for i: int in range(s.deferred.size() - 1, -1, -1):
		var d: Dictionary = s.deferred[i]
		if str(JsonUtil.as_dict(d.get("ctx", {})).get("card", "")) == str(x.get("card", "")) and str(d.get("hero", "")) == str(x.get("hero", "")):
			s.deferred.remove_at(i)
			break
	x["negated"] = true
	x["used"] = true
	s.event("card_undone", {"card": x.get("card", ""), "hero": x.get("hero", "")})


## The card's effect that carries the verb; null when none does.
func _effect_with(card: CardDef, verb: String) -> FxEffect:
	for e: FxEffect in card.effects:
		if e.has_verb(verb):
			return e
	return null


## The heroes an Equipment with EQUIP_OTHER may go on: other heroes of the player on the map, in the range of the
## hero it is played for, carrying the tag the line names, with room for it.
func equip_other_options(s: GameState, by: HeroState, card: CardDef, e: FxEffect) -> Array[HeroState]:
	var out: Array[HeroState] = []
	var tag: String = ""
	for a: Dictionary in e.actions:
		for x: String in JsonUtil.as_strings(a["args"]):
			if x.begins_with("{"):
				tag = x
	if by == null:
		return out
	for h: HeroState in s.heroes_of(by.owner):
		if h == by or not h.is_on_map() or not in_range(s, by, h) or h.equipment.has(card.id) or h.equipment.size() >= s.settings.equipment_limit:
			continue
		if tag.is_empty() or hero_has_tag(s, h, tag):
			out.append(h)
	return out


## The Power the hero has from this phase and this turn's bonuses (what cards gave it).
func _bonus_pwr(h: HeroState) -> int:
	if h == null:
		return 0
	return JsonUtil.as_int(h.phase_bonus.get("pwr", 0)) + JsonUtil.as_int(h.turn_bonus.get("pwr", 0))


## A card played in the battle being fought, for the combo offer: who, which hero (an Assist has none)
## and the stat bonus it put on the hero.
func _note_played(s: GameState, slot: int, cid: String, hero: String, bonus: Dictionary) -> void:
	if s.phase != GameState.PHASE_BATTLE or s.battle_index < 0 or s.battle_index >= s.battles.size():
		return
	var b: Dictionary = s.battles[s.battle_index]
	var played: Array = JsonUtil.as_array(b.get("played", []))
	played.append({"player": slot, "card": cid, "hero": hero, "bonus": bonus.duplicate(), "used": false})
	b["played"] = played


## A bonus something in play put on the card played last in this battle ("The first {Mage} card you play gets
## +2000 Power"): kept with that card, so whatever takes the card back takes the bonus too.
func note_card_bonus(s: GameState, stat_key: String, amount: int) -> void:
	if s.phase != GameState.PHASE_BATTLE or s.battle_index < 0 or s.battle_index >= s.battles.size():
		return
	var played: Array = JsonUtil.as_array(s.battles[s.battle_index].get("played", []))
	if played.is_empty():
		return
	var last: Dictionary = JsonUtil.as_dict(played[played.size() - 1])
	var bonus: Dictionary = JsonUtil.as_dict(last.get("bonus", {}))
	bonus[stat_key] = JsonUtil.as_int(bonus.get(stat_key, 0)) + amount
	last["bonus"] = bonus
	played[played.size() - 1] = last
	s.battles[s.battle_index]["played"] = played


## Combo (2026-11-07; Marko 2026-11-21: a bonus on top, not a replacement): two cards of a combo's pair played by
## one player in the same battle. Both resolve as ever; right after the second, its player may pay the combo's
## extra energy and the Combo card's effect comes on top of them. The Combo card says who plays them (Marko
## 2026-11-22): a team combo two different heroes, a solo combo one hero both. The decision, or {} when no combo
## is on offer.
func _combo_offer(s: GameState, slot: int, cid: String) -> Dictionary:
	if s.phase != GameState.PHASE_BATTLE or s.battle_index < 0 or s.battle_index >= s.battles.size():
		return {}
	var card: CardDef = catalog.get_card(cid)
	if card == null or (card.type != "Action" and card.type != "Assist"):
		return {}
	# A token is never part of a combo (GDD 10, 2026-11-14), whatever a combo card lists.
	if card.token:
		return {}
	var hero: String = ""
	var options: Array = []
	for combo: CardDef in catalog.of_type("Combo"):
		if combo.ingredients.size() != 2 or not combo.ingredients.has(cid) or not combo.is_ready():
			continue
		var other: String = combo.ingredients[1] if combo.ingredients[0] == cid else combo.ingredients[0]
		var other_card: CardDef = catalog.get_card(other)
		if other_card != null and other_card.token:
			continue
		var pair: Array[Dictionary] = _combo_pair(s, slot, other, cid, combo.combo_kind == "solo")
		if pair.is_empty() or s.player(slot).energy < combo_cost(s, slot, combo):
			continue
		if not _combo_payable(s, slot, combo, _combo_heroes(s, pair)):
			continue
		hero = str(pair[1].get("hero", ""))
		options.append({"id": combo.id, "with": other, "with_hero": str(pair[0].get("hero", "")), "extra": combo_cost(s, slot, combo)})
	if options.is_empty():
		return {}
	return {"type": DECISION_COMBO, "player": slot, "card": cid, "hero": hero, "combos": options}


## The two played cards a combo of `first_id` and `second_id` would be made of now: [the earlier one, the one
## played last], records of this battle's card round not yet in a combo; [] when they are not both there.
## A team combo (Marko 2026-11-22): the two cards were played for two different heroes of the player in the battle
## (an Assist has no hero and pairs with any). A solo combo: both were played for the same hero (an Assist goes with
## the other card's hero). The same holds when the pair is two copies of one card.
func _combo_pair(s: GameState, slot: int, first_id: String, second_id: String, solo: bool = false) -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	var played: Array = JsonUtil.as_array(s.battles[s.battle_index].get("played", []))
	var last: int = -1
	for i: int in range(played.size() - 1, -1, -1):
		var r: Dictionary = JsonUtil.as_dict(played[i])
		if JsonUtil.as_int(r.get("player", -1), -1) == slot and str(r.get("card", "")) == second_id and not JsonUtil.as_bool(r.get("used", false)):
			last = i
			break
	if last < 0:
		return none
	var second: Dictionary = JsonUtil.as_dict(played[last])
	if not solo and card_context_heroes(s, slot).size() < 2:
		return none
	for i: int in played.size():
		if i == last:
			continue
		var r: Dictionary = JsonUtil.as_dict(played[i])
		if JsonUtil.as_int(r.get("player", -1), -1) != slot or str(r.get("card", "")) != first_id or JsonUtil.as_bool(r.get("used", false)):
			continue
		var a: String = str(r.get("hero", ""))
		var b: String = str(second.get("hero", ""))
		# Team: not both on one hero. Solo: not on two different heroes.
		if not a.is_empty() and not b.is_empty() and (a == b) != solo:
			continue
		var out: Array[Dictionary] = [r, second]
		return out
	return none


## The heroes a combo works for: the ones its two cards were played for (one, when both were played for it).
func _combo_heroes(s: GameState, pair: Array[Dictionary]) -> Array[HeroState]:
	var out: Array[HeroState] = []
	for r: Dictionary in pair:
		var h: HeroState = s.hero(str(r.get("hero", "")))
		if h != null and not out.has(h):
			out.append(h)
	return out


## Can every hero of the combo pay its additional cost (COST_DAMAGE needs more HP than it takes)?
func _combo_payable(s: GameState, slot: int, combo: CardDef, heroes: Array[HeroState]) -> bool:
	for h: HeroState in heroes:
		var n: int = _cost_damage(s, slot, h, combo)
		if n > 0 and h.hp <= n:
			return false
	return true


## The combo is paid: the two cards stay as they were played, and the Combo card comes on top. Its stat boxes
## and whatever its text does for "your Hero" go to both heroes the cards were played for (Marko 2026-11-21);
## an effect that names its own targets ("Each of your Heroes in this Battle …") runs once.
func _accept_combo(s: GameState, slot: int, d: Dictionary, option: Dictionary) -> String:
	var p: PlayerState = s.player(slot)
	var cid: String = str(d.get("card", ""))
	var combo: CardDef = catalog.get_card(str(option.get("id", "")))
	if combo == null:
		return "that combo cannot be made now"
	var extra: int = combo_cost(s, slot, combo)
	if p.energy < extra:
		return "not enough energy (%d, costs %d)" % [p.energy, extra]
	var pair: Array[Dictionary] = _combo_pair(s, slot, str(option.get("with", "")), cid, combo.combo_kind == "solo")
	if pair.is_empty():
		return "the other card of the combo is no longer in this battle"
	var heroes: Array[HeroState] = _combo_heroes(s, pair)
	if not _combo_payable(s, slot, combo, heroes):
		return "a hero cannot pay the combo's additional cost"
	p.energy -= extra
	pair[0]["used"] = true
	pair[1]["used"] = true
	s.event("combo", {"combo": combo.id, "cards": [str(pair[0].get("card", "")), cid], "heroes": [str(pair[0].get("hero", "")), str(pair[1].get("hero", ""))], "player": slot, "extra": extra})
	for h: HeroState in heroes:
		for k: String in combo.bonus:
			h.add_bonus(h.phase_bonus, k, combo.bonus[k])
	# The second card's hero leads (the first one's for an Assist): effects that run once run for it.
	var lead: Array[HeroState] = []
	if not heroes.is_empty():
		lead.append(heroes[heroes.size() - 1])
	for e: FxEffect in combo.effects:
		if _for_each_hero(e) and not heroes.is_empty():
			for h: HeroState in heroes:
				_run_play_effect(s, slot, h, combo, e, s.battle_index)
		else:
			_run_play_effect(s, slot, lead[0] if not lead.is_empty() else null, combo, e, s.battle_index)
	_queue_core_returns(s)
	return ""


## The extra energy a combo costs this player now ("Your combos cost 2 Energy less").
func combo_cost(s: GameState, slot: int, combo: CardDef) -> int:
	var mod: int = fx.cost_mod(s, s.player(slot), combo, null)
	# Like a card (Marko 2026-11-22): a discount never brings a combo that costs something under 1.
	return maxi(combo.extra_cost + mod, 0 if combo.extra_cost <= 0 else 1)


## Does a combo's effect speak of "your Hero" (then it runs for each hero of the combo), or of targets of its own?
func _for_each_hero(e: FxEffect) -> bool:
	if e.bonus or e.cond == "ACTIVATED":
		return true
	for a: Dictionary in e.actions:
		if str(a["target"]) == "SELF" or str(a["verb"]) == "COST_DAMAGE":
			return true
	return false


## Why the first effect an Action runs as it is played cannot start ("" when it can).
func _play_blocker(s: GameState, slot: int, target: HeroState, card: CardDef) -> String:
	var ctx: Dictionary = {"player": slot, "hero": target.id if target != null else "", "card": card.id, "stage": ""}
	for e: FxEffect in card.effects:
		if e.when == "PASSIVE" or e.when == "REVEAL" or e.when == "PLAYED" or e.waits_for_battle():
			continue
		if not fx.cond_ok(s, ctx, e):
			continue
		var err: String = fx.first_error(s, ctx, e)
		# A line that is only a cost ("As an additional cost, deactivate a Core on your Hero.") is followed by what the
		# card does: that has to be able to start too, or the cost would be paid for nothing.
		if not err.is_empty() or not _only_costs(e):
			return err
	return ""


## Is the effect nothing but what the card asks of its player before it does anything?
func _only_costs(e: FxEffect) -> bool:
	for a: Dictionary in e.actions:
		if not ["REQUIRE", "COST_DAMAGE", "DEACTIVATE_CORE", "PAY", "OWN_COST"].has(str(a["verb"])):
			return false
	return not e.actions.is_empty()


## "Play this card only if …" (REQUIRE): why the card may not be played now, "" when it may.
func _requirement(s: GameState, slot: int, target: HeroState, card: CardDef) -> String:
	var ctx: Dictionary = {"player": slot, "hero": target.id if target != null else "", "card": card.id, "stage": ""}
	for e: FxEffect in card.effects:
		if e.has_verb("REQUIRE") and fx.cond_ok(s, ctx, e):
			var err: String = fx.first_error(s, ctx, e)
			if not err.is_empty():
				return err
	return ""


## Effects that happen as the card is played: PLAY ones, and phase ones on an Action
## (its WHEN only says when it may be played). "If you win" ones wait for the battle.
func _run_play_effects(s: GameState, slot: int, target: HeroState, card: CardDef, battle: int = -1) -> void:
	for e: FxEffect in card.effects:
		_run_play_effect(s, slot, target, card, e, battle)
	# A core the card took off comes back now, after the card's own choices.
	_queue_core_returns(s)


## One effect of a card as it is played for `target` (null: no hero).
func _run_play_effect(s: GameState, slot: int, target: HeroState, card: CardDef, e: FxEffect, battle: int = -1) -> void:
	var ctx: Dictionary = {"player": slot, "hero": target.id if target != null else "", "card": card.id, "stage": ""}
	if battle >= 0:
		ctx["battle"] = battle
	if e.when == "PASSIVE" or e.when == "REVEAL" or e.when == "PLAYED":
		return
	if card.type != "Action" and card.type != "Combo" and e.when != "PLAY":
		return
	if e.optional and card.type != "Action":
		return
	if not fx.cond_ok(s, ctx, e):
		return
	if e.waits_for_battle() and not e.arms_on_play():
		s.deferred.append({"player": slot, "hero": ctx["hero"], "fx": e.line, "ctx": ctx})
		return
	var err: String = fx.run(s, ctx, e)
	if not err.is_empty():
		s.event("fx_skipped", {"card": card.id, "why": err})


## The phase an Action is locked to ("" = any card round).
func _play_phase(card: CardDef) -> String:
	if card.type != "Action":
		# An Equipment handed to another hero is played in the phase its sentence opens with.
		var other: FxEffect = _effect_with(card, "EQUIP_OTHER")
		return other.when if other != null and other.when != "PLAY" and other.when != "PASSIVE" else ""
	for e: FxEffect in card.effects:
		if e.when != "PLAY" and e.when != "PASSIVE" and e.when != "PLAYED":
			return e.when
	return ""


## The damage `target` pays as the card's additional cost: its COST_DAMAGE that counts for this hero (a bonus
## may replace it: "Do not pay the additional cost" is INSTEAD … COST_DAMAGE 0).
func _cost_damage(s: GameState, slot: int, target: HeroState, card: CardDef) -> int:
	var ctx: Dictionary = {"player": slot, "hero": target.id if target != null else "", "card": card.id, "stage": ""}
	for e: FxEffect in card.effects:
		if not e.has_verb("COST_DAMAGE") or not fx.cond_ok(s, ctx, e):
			continue
		for a: Dictionary in e.actions:
			if str(a["verb"]) == "COST_DAMAGE":
				var args: PackedStringArray = a["args"]
				return args[0].to_int()
	return 0


## Energy a card costs this player now: discounts never go below 1 (GDD 10). `hero` is the hero
## the card is played for (a colorless card's own-cost bonus); without one, the cheapest of the
## heroes it could go to now, so the hand shows the price the player can get.
func card_cost(s: GameState, p: PlayerState, card: CardDef, hero: HeroState = null) -> int:
	if hero == null:
		hero = _cheapest_for(s, p, card, playable_heroes(s, p.slot, card))
	var mod: int = fx.cost_mod(s, p, card, hero) + fx.own_cost(s, p, card, hero)
	if card.cost <= 0:
		return maxi(card.cost + mod, 0)
	return maxi(card.cost + mod, 1)


## The heroes in the card round's context that this card may go to now (colour and first tag).
func playable_heroes(s: GameState, slot: int, card: CardDef) -> Array[HeroState]:
	var out: Array[HeroState] = []
	for h: HeroState in card_context_heroes(s, slot):
		var hc: CardDef = catalog.get_card(h.card_id)
		if hc == null or not card.plays_for_color(hc.color):
			continue
		if JsonUtil.as_bool(FirstTag.play_verdict(catalog, card, hc, stat_card(h), gained_tags(s, h))["ok"]):
			out.append(h)
	return out


## Of these heroes, the one the card costs least for (its colour bonus); null when none.
func _cheapest_for(s: GameState, p: PlayerState, card: CardDef, heroes: Array[HeroState]) -> HeroState:
	var best: HeroState = null
	var best_cost: int = 0
	for h: HeroState in heroes:
		var c: int = fx.own_cost(s, p, card, h) + fx.cost_mod(s, p, card, h)
		if best == null or c < best_cost:
			best = h
			best_cost = c
	return best


## ROLL_AGAIN: the activated hero rolls once more, right away, in the Roll phase.
func roll_again(s: GameState, slot: int) -> String:
	if s.phase != GameState.PHASE_ROLL or not s.rolled:
		return "roll again only works in the Roll phase after the roll"
	var h: HeroState = s.active_hero(slot)
	if h == null or h.is_ko():
		return "no activated hero to roll"
	s.rolled = false
	# Only this hero is thrown again (playtest 2026-11-06: the others' aims stayed and their balls were
	# thrown a second time with the same aim); the others stay where they stopped, as with roll_retry.
	for other: int in s.aims.keys():
		s.aims[other] = {"skip": true}
	s.aims.erase(slot)
	s.choices[slot] = true
	s.pending_rolls = PackedStringArray([h.id])
	# The other offers of this stop fall away; everyone gets a new one when the ball stops again.
	s.pending = s.pending.filter(func(d: Dictionary) -> bool: return str(d.get("type", "")) != DECISION_ROLL_OFFER)
	s.roll_offered = false
	s.event("roll_again", {"hero": h.id})
	return ""


## A core comes off a hero (deactivated by an effect): its owner puts it back within the
## hero's range at the next phase, like an overflow core.
func deactivate_core(s: GameState, h: HeroState, cid: String) -> void:
	if not h.cores.has(cid):
		return
	var c: CoreState = s.core(cid)
	h.cores.remove_at(h.cores.find(cid))
	if c == null:
		return
	c.place = CoreState.IN_INVENTORY
	c.holder = ""
	c.picked_by = h.id
	s.player(h.owner).inventory.append(c.id)
	s.event("core_deactivated", {"core": c.id, "hero": h.id})


## The card leaves the hand as it is played; a token leaves the tokens beside it.
func _take_from_hand(p: PlayerState, cid: String) -> void:
	var at: int = p.hand.find(cid)
	if at >= 0:
		p.hand.remove_at(at)
		return
	at = p.tokens.find(cid)
	if at >= 0:
		p.tokens.remove_at(at)


## TOKEN (GDD 10, 2026-11-14): n copies of a token card appear beside the player's hand, open to everyone.
## Nothing is made in the End phase (the turn's end would take it at once). "" or why not.
func make_token(s: GameState, slot: int, cid: String, n: int = 1) -> String:
	var card: CardDef = catalog.get_card(cid)
	if card == null or not card.token:
		return "%s is not a token card" % cid
	var p: PlayerState = s.player(slot)
	if p == null:
		return "no such player"
	if s.phase == GameState.PHASE_END:
		return ""
	var count: int = maxi(n, 1)
	for _i: int in count:
		p.tokens.append(cid)
	s.event("token", {"player": slot, "card": cid, "amount": count})
	return ""


## The end of the turn takes every token nobody played: no graveyard, as if it had never been.
func _drop_tokens(s: GameState) -> void:
	for p: PlayerState in s.players:
		if p.tokens.is_empty():
			continue
		s.event("tokens_gone", {"player": p.slot, "cards": Array(p.tokens)})
		p.tokens = PackedStringArray()


static func _ids(list: Array[HeroState]) -> PackedStringArray:
	var out := PackedStringArray()
	for h: HeroState in list:
		out.append(h.id)
	return out


## Takes the top evolution off (card to the graveyard); HP only drops to the new max. A temporary
## evolution is the top one while it lasts.
## `rolled`: it broke because its hero was thrown, not because a card took it off.
func remove_evolution(s: GameState, h: HeroState, rolled: bool = false) -> void:
	if not h.temp_evo.is_empty():
		_drop_temp_evolution(s, h, "removed")
		return
	if h.evolutions.is_empty():
		return
	var cid: String = h.evolutions[h.evolutions.size() - 1]
	# "If this Evolution is removed, X is KO'd": asked while the Evolution is still on.
	var fatal: bool = not rolled and has_status(s, h, "ko_if_removed")
	h.evolutions.remove_at(h.evolutions.size() - 1)
	s.player(h.owner).graveyard.append(cid)
	clamp_hp(s, h)
	s.event("evolution_removed", {"card": cid, "hero": h.id})
	_drop_unfit_equipment(s, h)
	if fatal:
		ko_hero(s, h, "", cid)


## Whether a piece of equipment on the hero does anything now. In a temporary evolution the hero has that
## form's traits; equipment whose first tag the form does not satisfy stays on the hero but does not work
## until the form is gone (Marko 2026-11-15): no stat bonus, no effect of its own. It still is equipped
## (the limit, and effects that count equipped cards).
func equipment_works(h: HeroState, cid: String) -> bool:
	if h.temp_evo.is_empty():
		return true
	var c: CardDef = catalog.get_card(cid)
	if c == null:
		return false
	return JsonUtil.as_bool(FirstTag.play_verdict(catalog, c, catalog.get_card(h.card_id), stat_card(h))["ok"])


## Equipment whose first tag the hero no longer satisfies (an evolution came or went) falls
## into the graveyard (GDD 10, 2026-10-26). Not while a temporary evolution lasts: then it only stops
## working (equipment_works) and is looked at again when the form is gone.
func _drop_unfit_equipment(s: GameState, h: HeroState) -> void:
	if not h.temp_evo.is_empty():
		return
	for cid: String in h.equipment.duplicate():
		var c: CardDef = catalog.get_card(cid)
		if c == null:
			continue
		var v: Dictionary = FirstTag.play_verdict(catalog, c, catalog.get_card(h.card_id), stat_card(h), gained_tags(s, h))
		if not JsonUtil.as_bool(v["ok"]):
			remove_equipment(s, h, cid)
			s.event("equipment_unfit", {"card": cid, "hero": h.id, "why": str(v["why"])})


## Takes one equipment off (card to the graveyard); HP only drops to the new max.
func remove_equipment(s: GameState, h: HeroState, cid: String) -> void:
	if not h.equipment.has(cid):
		return
	h.equipment.remove_at(h.equipment.find(cid))
	s.player(h.owner).graveyard.append(cid)
	clamp_hp(s, h)
	s.event("equipment_removed", {"card": cid, "hero": h.id})


## All current stats, for display.
func stats(s: GameState, h: HeroState) -> Dictionary:
	var out: Dictionary = {}
	for key: String in ["hp", "dmg", "pwr", "rng", "kb"]:
		out[key] = stat(s, h, key)
	return out


func max_hp(s: GameState, h: HeroState) -> int:
	return stat(s, h, "hp")


## Attacker `a` reaches `b`: b's footprint lies within a's range, counted from a's outer hexes.
# =====================================================================================
# Companions (GDD 10, 2026-11-21)
# =====================================================================================

## A companion could rest on `a`: on the map, no wall, hero, core or other companion there.
func companion_spot_free(s: GameState, a: Vector2i) -> bool:
	return s.map().contains(a) and not s.wall_at(a) and s.hero_at(a) == null and s.core_at(a) == null and s.companion_at(a) == null


## Where `h`'s player may put a companion: the free hexes nearest to the hero. Next to it when there is room;
## with none there, the nearest ring that has a free hex (Marko 2026-11-22). The player picks among them.
func companion_spots(s: GameState, h: HeroState) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	if h == null or not h.is_on_map():
		return none
	return _nearest_free(s, h.hex, null)


## Where the hero hidden in a companion may come out as it is activated: the free hexes nearest to the companion
## (next to it when there is room, else the nearest ring that has one; Marko 2026-11-22). The player picks.
func shelter_exits(s: GameState, h: HeroState) -> Array[Vector2i]:
	var none: Array[Vector2i] = []
	var c: CompanionState = s.shelter_of(h.id) if h != null else null
	if c == null:
		return none
	return _nearest_free(s, c.hex, h)


## The free hexes of the first ring round `center` that has any, from the centre out: free for `hero` to stand
## on (its size counted), or for a companion when `hero` is null. [] only when the map is full.
func _nearest_free(s: GameState, center: Vector2i, hero: HeroState) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r: int in range(0, s.settings.map_size * 2 + 1):
		for a: Vector2i in Hex.ring(center, r):
			if (s.is_free(a, hero.big, hero) if hero != null else companion_spot_free(s, a)):
				out.append(a)
		if not out.is_empty():
			return out
	return out


## The hero an Assist's companion is put next to: the one the card was played for, else the player's hero
## that cards go to now (the activated one; in a battle, theirs in it).
func companion_hero(s: GameState, slot: int, hero_id: String) -> HeroState:
	var h: HeroState = s.hero(hero_id)
	if h != null:
		return h
	var ctx: Array[HeroState] = card_context_heroes(s, slot)
	return ctx[0] if not ctx.is_empty() else s.active_hero(slot)


## An Assist whose PLAY effect puts a companion down is not played without a free hex for it (a full map).
func _companion_blocker(s: GameState, slot: int, target: HeroState, card: CardDef) -> String:
	for e: FxEffect in card.effects_when("PLAY"):
		for a: Dictionary in e.actions:
			if str(a["verb"]) == "COMPANION" and companion_spots(s, companion_hero(s, slot, target.id if target != null else "")).is_empty():
				return "no free space on the map"
	return ""


## Puts `slot`'s companion from `card_id` on `a`. A player has one: the one before it leaves with its Assist.
func place_companion(s: GameState, slot: int, card_id: String, a: Vector2i) -> void:
	var old: CompanionState = s.companion_of(slot)
	if old != null:
		remove_companion(s, old, "replaced")
	var c := CompanionState.new()
	c.id = CompanionState.id_for(slot)
	c.owner = slot
	c.card_id = card_id
	c.hex = a
	s.companions.append(c)
	s.event("companion", {"id": c.id, "player": slot, "card": card_id, "hex": Hex.to_json(a)})


## Takes a companion off the table. `why`: assist (its Assist left play) | replaced (a new one came) | fell
## (off the table). A hero inside comes out where it stood, unhurt; a fall is handled by companion_falls first.
## Replaced or fallen, its Assist goes to the graveyard with it.
func remove_companion(s: GameState, c: CompanionState, why: String) -> void:
	if c == null or not s.companions.has(c):
		return
	var inside: HeroState = s.hero(c.inside)
	s.companions.erase(c)
	c.inside = ""
	if inside != null and inside.is_hidden():
		_put_out(s, inside, c.hex, null)
	var p: PlayerState = s.player(c.owner)
	if why != "assist" and p != null and p.assists.has(c.card_id):
		p.assists.remove_at(p.assists.find(c.card_id))
		p.graveyard.append(c.card_id)
	s.event("companion_gone", {"id": c.id, "player": c.owner, "card": c.card_id, "why": why})


## A companion left the table (a ball pushed it over the edge): it is gone with its Assist; a hero inside
## pays as for a ring-out and goes back to its start zone.
func companion_falls(s: GameState, c: CompanionState) -> void:
	var inside: HeroState = s.hero(c.inside)
	c.inside = ""
	s.event("companion_fell", {"id": c.id, "player": c.owner, "hero": inside.id if inside != null else ""})
	remove_companion(s, c, "fell")
	if inside != null and inside.is_hidden():
		ring_out(s, inside, "companion")


## A companion whose Assist is no longer in play leaves; a hero that was knocked out inside is not inside.
func _sync_companions(s: GameState) -> void:
	for c: CompanionState in s.companions.duplicate():
		var p: PlayerState = s.player(c.owner)
		var h: HeroState = s.hero(c.inside)
		if not c.inside.is_empty() and (h == null or not h.is_hidden()):
			c.inside = ""
		if p == null or not p.assists.has(c.card_id):
			remove_companion(s, c, "assist")


## Heroes of `c`'s owner that may hide in it now: on the map, free (not locked in a tie), within `reach`.
func shelter_candidates(s: GameState, c: CompanionState, reach: int) -> Array[HeroState]:
	var out: Array[HeroState] = []
	if c == null or not c.inside.is_empty():
		return out
	for h: HeroState in s.heroes_of(c.owner):
		if not h.is_on_map() or h.tie_turns > 0:
			continue
		if Hex.distance(c.hex, h.hex) - (1 if h.big else 0) <= reach:
			out.append(h)
	return out


## `h` hides in its player's companion: off the table (not a target, in no battle, on no stage, no cards
## for it); if it was the activated hero, its player is down to Pass or an Assist for the turn.
func enter_shelter(s: GameState, h: HeroState, c: CompanionState) -> void:
	var was: StageState = begin_move(s, h)
	h.zone = HeroState.ZONE_SHELTER
	c.inside = h.id
	_lost_active(s, h)
	end_move(s, h, was, -1)
	s.event("sheltered", {"hero": h.id, "companion": c.id})


## A hidden hero comes out as it is activated: on `wanted` (a hex as JSON) when that is one of its exits
## (shelter_exits), else on the first of them. "" or why not.
func leave_shelter(s: GameState, h: HeroState, wanted: Variant) -> String:
	var c: CompanionState = s.shelter_of(h.id)
	if c == null:
		return "hero is not hidden"
	var exits: Array[Vector2i] = shelter_exits(s, h)
	if exits.is_empty():
		return "no free space on the map"
	var at: Vector2i = exits[0]
	if wanted != null:
		at = JsonUtil.as_hex(wanted)
		if not exits.has(at):
			return "not one of the free hexes nearest to the companion"
	c.inside = ""
	_set_out(s, h, at)
	return ""


## Puts a hidden hero back on the map round `from`, the hex its companion stood on: there when it is free (the
## companion is gone), else on the nearest free hex.
func _put_out(s: GameState, h: HeroState, from: Vector2i, _wanted: Variant) -> bool:
	var spots: Array[Vector2i] = _nearest_free(s, from, h)
	if spots.is_empty():
		return false
	_set_out(s, h, spots[0])
	return true


func _set_out(s: GameState, h: HeroState, at: Vector2i) -> void:
	h.zone = HeroState.ZONE_MAP
	h.hex = at
	s.event("left_shelter", {"hero": h.id, "hex": Hex.to_json(h.hex)})
	arrive(s, h)


## The End phase: a companion walks by itself, 1 to `steps` hexes in a direction drawn by lot, until
## something is in the way; a direction with no free first step is skipped. It never leaves the table and
## carries the hero inside along.
func wander_companion(s: GameState, c: CompanionState, steps: int) -> void:
	if c == null or steps <= 0:
		return
	var first: int = s.random_int(6)
	var want: int = 1 + s.random_int(steps)
	for k: int in 6:
		var dir: int = (first + k) % 6
		var at: Vector2i = c.hex
		var done: int = 0
		while done < want:
			var next: Vector2i = Hex.neighbor(at, dir)
			if not companion_spot_free(s, next):
				break
			at = next
			done += 1
		if done > 0:
			var from: Vector2i = c.hex
			c.hex = at
			s.event("companion_moved", {"id": c.id, "from": Hex.to_json(from), "hex": Hex.to_json(at), "why": "wander"})
			return


## One ball's stop that is a companion's (the sim reports it under the companion's id): it rests where it
## stopped, or it is gone when it left the map.
func _apply_companion_result(s: GameState, r: RollResult) -> void:
	var c: CompanionState = s.companion(r.ball_id)
	if c == null:
		return
	if r.ring_out or r.strip_entered >= 0 or r.end_area != BallWorld.Area.MAP:
		companion_falls(s, c)
		return
	if r.end_hex != c.hex:
		var from: Vector2i = c.hex
		c.hex = r.end_hex
		s.event("companion_moved", {"id": c.id, "from": Hex.to_json(from), "hex": Hex.to_json(c.hex), "why": "pushed"})


## A hero that stopped on a companion's hex pushes it onto the nearest free one (a roll worked out without
## the sim, or two stops snapped to the same hex).
func _unstack_companions(s: GameState) -> void:
	for c: CompanionState in s.companions:
		if s.hero_at(c.hex) == null and not s.wall_at(c.hex):
			continue
		for r: int in range(1, 5):
			var moved: bool = false
			for a: Vector2i in Hex.spiral(c.hex, r):
				if companion_spot_free(s, a):
					var from: Vector2i = c.hex
					c.hex = a
					s.event("companion_moved", {"id": c.id, "from": Hex.to_json(from), "hex": Hex.to_json(a), "why": "pushed"})
					moved = true
					break
			if moved:
				break


func in_range(s: GameState, a: HeroState, b: HeroState) -> bool:
	if not a.is_on_map() or not b.is_on_map():
		return false
	var gap: int = Hex.distance(a.hex, b.hex) - (1 if a.big else 0) - (1 if b.big else 0)
	return gap <= stat(s, a, "rng")


## A hex in `a`'s range. A hero in its start zone reaches nothing (GDD 6: it does not act on the
## map until it enters it).
func reaches_hex(s: GameState, a: HeroState, cell: Vector2i) -> bool:
	if not a.is_on_map():
		return false
	var gap: int = Hex.distance(a.hex, cell) - (1 if a.big else 0)
	return gap >= 1 and gap <= stat(s, a, "rng")


## Terrain in force: revealed stages, until the turn after their claim.
func terrain(s: GameState) -> TerrainMap:
	var tm := TerrainMap.new()
	for st: StageState in s.stages:
		if not st.placed or not st.revealed:
			continue
		if st.is_claimed() and s.turn > st.terrain_until_turn:
			continue
		var kind: Terrain.Type = stage_terrain(st)
		if kind == Terrain.Type.NONE:
			continue
		tm.set_patch(st.center, kind, s.map(), maxi(0, st.wind_dir))
	return tm


## The stage's terrain: the one a card put on it, else its own.
func stage_terrain(st: StageState) -> Terrain.Type:
	if not st.terrain_override.is_empty():
		return Terrain.parse(st.terrain_override)
	var card: CardDef = catalog.get_card(st.card_id)
	return card.terrain if card != null else Terrain.Type.NONE


## The revealed, unclaimed stage this hero stands on; null when none.
func stage_under(s: GameState, h: HeroState) -> StageState:
	if h == null or not h.is_on_map():
		return null
	for st: StageState in s.stages:
		if st.placed and st.revealed and not st.is_claimed() and st.covers(h.hex):
			return st
	return null


## Does the hero carry this status now: one put on it, or one a passive in play gives it ("is immune to Knockback")?
func has_status(s: GameState, h: HeroState, name: String) -> bool:
	return h.has_status(name) or fx.passive_status(s, h, name.to_upper())


## Tags the hero got in the match ("The equipped Hero gains {Mage}", "Your Heroes gain {Brave Hero}"): from passives
## in play and from this turn's effects. They count like tags it carries, for playing cards and for effects.
func gained_tags(s: GameState, h: HeroState) -> PackedStringArray:
	var out: PackedStringArray = fx.passive_tags(s, h)
	for m: Dictionary in s.turn_mods:
		if str(m.get("kind", "")) == "tag" and str(m.get("hero", "")) == h.id:
			out.append(str(m.get("tag", "")))
	return out


## Does the hero carry the tag now: on the card it plays as, or gained in the match?
func hero_has_tag(s: GameState, h: HeroState, tag: String) -> bool:
	var want: String = FirstTag.norm(tag.trim_prefix("{").trim_suffix("}"))
	var card: CardDef = stat_card(h)
	if card != null and FirstTag.has_trait(card, want):
		return true
	for g: String in gained_tags(s, h):
		if FirstTag.norm(g) == want:
			return true
	return false


## Is this the hero a name or tag speaks of: it is called that, or it has the tag?
func hero_is(s: GameState, h: HeroState, tag: String) -> bool:
	var base: CardDef = catalog.get_card(h.card_id)
	var want: String = FirstTag.norm(tag.trim_prefix("{").trim_suffix("}"))
	return (base != null and FirstTag.aliases_of(base).has(want)) or hero_has_tag(s, h, tag)


## An Assist leaves play for the graveyard (sacrificed by its own text, or used up).
func discard_assist(s: GameState, slot: int, cid: String, why: String) -> bool:
	var p: PlayerState = s.player(slot)
	var at: int = p.assists.find(cid)
	if at < 0:
		return false
	p.assists.remove_at(at)
	p.graveyard.append(cid)
	s.event("assist_gone", {"card": cid, "player": slot, "why": why})
	return true


## As the End phase starts: the heals that were put off till then ("heals 1 HP at the end of the turn").
func _late_heals(s: GameState) -> void:
	for m: Dictionary in s.turn_mods:
		if str(m.get("kind", "")) != "end_heal":
			continue
		var h: HeroState = s.hero(str(m.get("hero", "")))
		if h == null or h.is_ko():
			continue
		heal(s, h, JsonUtil.as_int(m.get("amount", 0)))
		s.event("heal", {"hero": h.id, "amount": JsonUtil.as_int(m.get("amount", 0)), "hp": h.hp})


## As the End phase starts: heroes sent back to where the Battle phase found them ("At the end of the turn, return
## your Hero to where they were at the start of the Battle Phase"): from wherever they are now, onto that hex or
## the free hex nearest to it. A hero that is KO stays out.
func _returns(s: GameState) -> void:
	for m: Dictionary in s.turn_mods:
		if str(m.get("kind", "")) != "return":
			continue
		var h: HeroState = s.hero(str(m.get("hero", "")))
		var was: Dictionary = JsonUtil.as_dict(s.battle_snapshot.get(str(m.get("hero", "")), {}))
		if h == null or h.is_ko() or h.is_hidden() or str(was.get("zone", "")) != HeroState.ZONE_MAP:
			continue
		var home: Vector2i = JsonUtil.as_hex(was.get("hex", null))
		if h.is_on_map() and h.hex == home:
			continue
		var spots: Array[Vector2i] = _nearest_free(s, home, h)
		if spots.is_empty():
			continue
		var from: StageState = begin_move(s, h)
		h.zone = HeroState.ZONE_MAP
		h.hex = spots[0]
		s.event("moved", {"hero": h.id, "hex": Hex.to_json(h.hex), "by": "return"})
		arrive(s, h)
		end_move(s, h, from, s.team_of(h.owner))


## A face-down stage turns face up (a hero stopped on it, or a card says so).
func reveal_stage(s: GameState, st: StageState, by: HeroState) -> void:
	if st == null or not st.placed or st.revealed:
		return
	st.revealed = true
	# A wind blows in a direction drawn now and kept (GDD 6, 2026-10-26); it goes into the
	# state and the replay with the stage.
	st.wind_dir = s.random_int(6)
	s.event("stage_revealed", {"stage": st.id, "by": by.id if by != null else "", "wind": st.wind_dir})
	if by != null:
		fx.on_reveal(s, st, by)


## The hero goes down whatever HP it has (a card's "KO", the End of a doomed hero), as a hit for all its HP: what
## saves a hero from a KO can save it here too.
func ko_hero(s: GameState, h: HeroState, by: String = "", card: String = "") -> void:
	if h == null or h.is_ko():
		return
	hero_damage(s, h, maxi(h.hp, 1), true, by, card)


## As the End phase starts: a hero marked to go down ("Your Hero is KO'd during the End Phase") does.
func _doom(s: GameState) -> void:
	for h: HeroState in s.heroes:
		if h.has_status("doomed") and not h.is_ko():
			s.event("doomed", {"hero": h.id})
			ko_hero(s, h, "doom")


## A hero that held others still ("… or until X is KO'd or ringed out") lets them go as it leaves the map.
func _release_stunned_by(s: GameState, h: HeroState) -> void:
	for o: HeroState in s.heroes:
		if o.stun_by == h.id:
			o.stun_by = ""
			o.statuses.erase("stun")
			s.event("released", {"hero": o.id, "by": h.id})


## A hero that ignores terrain: Ice, Mud, Wind and Fire do nothing to it; a Ramp still does.
func ignores_terrain(s: GameState, h: HeroState) -> bool:
	return has_status(s, h, "ignore_terrain")


## Fire terrain (Marko 2026-11-22): as the End phase starts, each hero standing on it takes 1 DMG.
func _burn(s: GameState) -> void:
	var tm: TerrainMap = terrain(s)
	if not tm.has(Terrain.Type.FIRE):
		return
	for h: HeroState in s.heroes:
		if not h.is_on_map() or tm.at(h.hex) != Terrain.Type.FIRE or ignores_terrain(s, h):
			continue
		s.event("burn", {"hero": h.id})
		hero_damage(s, h, FIRE_DAMAGE, false, "fire")
