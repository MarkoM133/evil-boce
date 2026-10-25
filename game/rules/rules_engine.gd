class_name RulesEngine
extends RefCounted
## Applies moves and roll outcomes to a GameState. Pure logic: no scene, no physics, no
## randomness outside the state's own RNG. Every public call returns "" or an error message
## and never changes the state when it fails. Assumptions the GDD leaves open are listed in
## docs/rules.md.

const DECISION_DAMAGE: String = "damage"
const DECISION_RETURN_CORE: String = "return_core"

var catalog: CardCatalog
## Card effects (docs/fx-keywords.md).
var fx: FxRuntime


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
		for cid: String in p.core_cards:
			n += 1
			var c := CoreState.new()
			c.id = "core:p%d:%d" % [i, n]
			c.card_id = cid
			c.owner = i
			s.cores.append(c)
	for p: PlayerState in s.players:
		_shuffle(s, p.deck)
	s.initiative = s.random_int(s.players.size())
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
				if stage_placement_error(s, st, a, gap).is_empty():
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
				if core_placement_error(s, c, a, gap).is_empty():
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
			if stage_placement_error(s, st, a).is_empty():
				options.append(a)
		if options.is_empty():
			for other: StageState in s.stages:
				other.placed = false
			return false
		st.center = options[s.random_int(options.size())]
		st.placed = true
	return true


## "" when stage `st` may be placed centred on `a`. `gap` is the fewest empty hexes between
## stage edges (-1 = the match setting).
func stage_placement_error(s: GameState, st: StageState, a: Vector2i, gap: int = -1) -> String:
	if gap < 0:
		gap = s.settings.effective_stage_gap()
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


## "" when core `c` may be put on `a` during setup.
func core_placement_error(s: GameState, c: CoreState, a: Vector2i, gap: int = -1) -> String:
	if not s.map().contains(a):
		return "not on the map"
	if not s.in_half_of_team(a, 1 - s.team_of(c.owner)):
		return "core goes into the opponent's half"
	return _core_spot_error(s, c, a, gap if gap >= 0 else s.settings.effective_core_gap())


## `gap` < 0 skips the distance rules (returning a core from the inventory).
func _core_spot_error(s: GameState, c: CoreState, a: Vector2i, gap: int) -> String:
	if s.wall_at(a) or s.hero_at(a) != null:
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
		GameState.PHASE_SELECT:
			err = _apply_select(s, m)
		GameState.PHASE_PREROLL:
			err = _apply_preroll(s, m)
		GameState.PHASE_ROLL:
			err = _apply_roll_phase(s, m)
		GameState.PHASE_POSTROLL, GameState.PHASE_BATTLE:
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


func _apply_select(s: GameState, m: Move) -> String:
	if m.type != Move.SELECT:
		return "select a hero"
	if s.active.has(m.player):
		return "already selected"
	var hid: String = m.str_arg("hero")
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
	s.active[m.player] = hid
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


func _apply_preroll(s: GameState, m: Move) -> String:
	if m.type == Move.CHOICE:
		if s.choices.has(m.player):
			return "already chosen"
		var h: HeroState = s.active_hero(m.player)
		if h == null:
			return "no activated hero"
		var roll: bool = m.bool_arg("roll", true)
		if not roll and h.zone == HeroState.ZONE_STRIP:
			return "a hero in the start zone must roll"
		s.choices[m.player] = roll
		return ""
	return _apply_card_round_move(s, m)


func _apply_roll_phase(s: GameState, m: Move) -> String:
	if m.type == Move.AIM:
		if s.awaiting_roll:
			return "waiting for the roll"
		if not s.choices.get(m.player, false) or s.active_hero(m.player) == null:
			return "you are not rolling"
		if s.aims.has(m.player):
			return "already aimed"
		var dir: Array = JsonUtil.as_array(m.data.get("dir", []))
		if dir.size() != 2:
			return "dir must be [x, z]"
		var power: float = JsonUtil.as_float(m.data.get("power", 1.0), 1.0)
		if power < 0.0 or power > 1.0:
			return "power must be 0..1"
		s.aims[m.player] = {"dir": [JsonUtil.as_float(dir[0]), JsonUtil.as_float(dir[1])], "power": power}
		return ""
	if s.awaiting_roll or not _all_aims_in(s):
		return "aim first"
	return _apply_card_round_move(s, m)


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
		if s.only_pass.has(m.player):
			return "you can only pass this turn"
		var err: String = _play_card(s, m)
		if not err.is_empty():
			return err
		s.passed = PackedInt32Array()
		s.to_act = _next_slot(s, s.to_act)
		return ""
	if m.type == Move.USE_ABILITY:
		if s.only_pass.has(m.player):
			return "you can only pass this turn"
		var err: String = fx.use_ability(s, m.player, m.str_arg("hero"), m.str_arg("card"), JsonUtil.as_int(m.data.get("index", 0)))
		if not err.is_empty():
			return err
		s.passed = PackedInt32Array()
		s.to_act = _next_slot(s, s.to_act)
		return ""
	return "pass, play a card or use an ability"


func _apply_decision(s: GameState, m: Move) -> String:
	var d: Dictionary = s.pending[0]
	var who: int = JsonUtil.as_int(d.get("player", -1), -1)
	if m.player != who:
		return "waiting for player %d" % who
	match str(d.get("type", "")):
		DECISION_DAMAGE:
			if m.type != Move.DAMAGE_TO:
				return "choose where the damage goes"
			var target: String = m.str_arg("target")
			var amount: int = JsonUtil.as_int(d.get("amount", 0))
			var targets: PackedStringArray = JsonUtil.as_strings(d.get("targets", []))
			if target == "deck":
				s.pending.pop_front()
				deck_damage(s, s.player(who), amount)
			elif targets.has(target):
				s.pending.pop_front()
				hero_damage(s, s.hero(target), amount)
			else:
				return "target must be \"deck\" or one of %s" % ", ".join(targets)
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
		_:
			return "unknown decision"
	_continue(s)
	return ""


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
			return "must be within the range of %s" % picker.id
	elif not s.in_half_of_team(a, s.team_of(c.owner)):
		return "must be in your half"
	return ""


# =====================================================================================
# Roll outcome from the sim
# =====================================================================================

## Feeds the physics result for this turn's throws. Every result whose ball id is a hero id
## moves that hero; others are ignored.
func apply_roll(s: GameState, o: RollOutcome) -> String:
	if s.phase != GameState.PHASE_ROLL or not s.awaiting_roll:
		return "not waiting for a roll"
	for r: RollResult in o.results:
		var h: HeroState = s.hero(r.ball_id)
		if h == null or h.is_ko():
			continue
		_apply_result(s, h, r)
	s.awaiting_roll = false
	s.rolled = true
	s.pending_rolls = PackedStringArray()
	s.event("rolled", {"moved": Array(o.moved_ids())})
	_start_card_round(s)
	_continue(s)
	return ""


func _apply_result(s: GameState, h: HeroState, r: RollResult) -> void:
	for cid: String in r.cores_picked:
		var c: CoreState = s.core(cid)
		if c != null and c.place == CoreState.ON_FIELD:
			pick_core(s, h, c)
	if r.ring_out or r.strip_entered >= 0:
		ring_out(s, h, "edge" if r.ring_out else "strip")
		return
	if r.end_area == BallWorld.Area.MAP:
		h.zone = HeroState.ZONE_MAP
		h.hex = r.end_hex
		s.event("moved", {"hero": h.id, "hex": Hex.to_json(h.hex)})
		var st: StageState = s.stage_at(h.hex)
		if st != null and not st.revealed:
			st.revealed = true
			s.event("stage_revealed", {"stage": st.id, "by": h.id})
			fx.on_reveal(s, st, h)
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
		hero_damage(s, h, JsonUtil.as_int(m.get("amount", 0)))


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
		_drop_held_hits(s)
		if not s.pending.is_empty():
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
				_set_phase(s, GameState.PHASE_DRAW)
			GameState.PHASE_DRAW:
				_draw_phase(s)
				_set_phase(s, GameState.PHASE_SELECT)
			GameState.PHASE_SELECT:
				if s.active.size() < _active_slots(s).size():
					return
				s.event("activated", {"heroes": s.active.duplicate()})
				_start_card_round(s)
				_set_phase(s, GameState.PHASE_PREROLL)
			GameState.PHASE_PREROLL:
				if not s.round_over or not _all_choices_in(s):
					return
				s.event("choices", {"roll": s.choices.duplicate()})
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
				if not s.round_over:
					return
				_start_card_round(s)
				_set_phase(s, GameState.PHASE_POSTROLL)
			GameState.PHASE_POSTROLL:
				if not s.round_over:
					return
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
				_end_phase(s)
				if s.is_over():
					return
				_set_phase(s, GameState.PHASE_DRAW)
			_:
				return


## Every phase change goes through here, so inventory cores get queued for their return.
func _set_phase(s: GameState, phase: String) -> void:
	s.phase = phase
	for h: HeroState in s.heroes:
		if not h.phase_bonus.is_empty():
			h.phase_bonus.clear()
			clamp_hp(s, h)
	_queue_core_returns(s)
	match phase:
		GameState.PHASE_PREROLL, GameState.PHASE_ROLL, GameState.PHASE_POSTROLL, GameState.PHASE_BATTLE, GameState.PHASE_END:
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
			if h != null and not h.is_ko():
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


## At the start of every phase a player with cores in the inventory must put them back.
func _queue_core_returns(s: GameState) -> void:
	if s.phase == GameState.PHASE_SETUP_STAGES or s.phase == GameState.PHASE_SETUP_CORES \
			or s.phase == GameState.PHASE_MULLIGAN or s.phase == GameState.PHASE_DRAW:
		return
	for p: PlayerState in s.players:
		for cid: String in p.inventory:
			if not _has_free_return_spot(s, s.core(cid)):
				continue
			s.pending.append({"type": DECISION_RETURN_CORE, "player": p.slot, "core": cid})


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
		for other: HeroState in s.heroes:
			if other == seed or not other.is_on_map() or taken.has(other.id) or members.has(other):
				continue
			if s.same_team(seed, other):
				continue
			if in_range(s, seed, other) or in_range(s, other, seed):
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


func _next_battle(s: GameState) -> void:
	s.battle_index += 1
	if s.battle_index < s.battles.size():
		_start_card_round(s)
		fx.fire_battle(s)


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
	var best: int = -1
	var best_pow: int = -1
	var tie: bool = false
	for t: int in teams:
		if power[t] > best_pow:
			best_pow = power[t]
			best = t
			tie = false
		elif power[t] == best_pow:
			tie = true
	s.event("battle", {"index": index, "power": power.duplicate()})
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
			if in_range(s, w, l):
				targets.append(l.id)
		if targets.is_empty():
			continue
		# "After winning, may deal no DMG": the owner decides before the loser does.
		if fx.hold_hit_effect(s, w) != null:
			fx.offer_hold_hit(s, w)
		var loser_owner: int = s.hero(str(targets[0])).owner
		s.pending.append({
			"type": DECISION_DAMAGE, "player": loser_owner, "winner": w.id,
			"amount": stat(s, w, "dmg"), "targets": targets,
		})


## After every damage decision: knockback, then the next battle.
func _finish_battle(s: GameState, index: int) -> void:
	var b: Dictionary = s.battles[index]
	if JsonUtil.as_bool(b.get("resolved", false)):
		return
	b["resolved"] = true
	if JsonUtil.as_bool(b.get("tie", false)):
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
		knockback(s, l, Hex.direction_towards(from.hex, l.hex), kb)
	for h: HeroState in members:
		h.tie_turns = 0
		h.locked_with = PackedStringArray()
	_check_win(s)


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
			h.tie_turns = 0
			h.locked_with = PackedStringArray()
			knockback(s, h, 1 if t == 0 else 4, kb)
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
func hero_damage(s: GameState, h: HeroState, amount: int, unblockable: bool = false) -> void:
	if h == null or h.is_ko() or amount <= 0:
		return
	if not unblockable:
		amount = maxi(amount + fx.damage_mod(s, h), 0)
	if amount <= 0:
		s.event("damage", {"hero": h.id, "amount": 0, "hp": h.hp})
		return
	h.hp -= amount
	s.event("damage", {"hero": h.id, "amount": amount, "hp": h.hp})
	if h.hp <= 0:
		h.hp = 0
		knock_out(s, h)


func heal(s: GameState, h: HeroState, amount: int) -> void:
	h.hp = mini(h.hp + amount, max_hp(s, h))


## Deck damage: cards from the top of the deck to the graveyard; from the hand once the deck
## is empty; losing the match when the hand runs out too.
func deck_damage(s: GameState, p: PlayerState, amount: int) -> void:
	for _i: int in amount:
		if not p.deck.is_empty():
			p.graveyard.append(p.deck[0])
			p.deck.remove_at(0)
		elif not p.hand.is_empty():
			p.graveyard.append(p.hand[p.hand.size() - 1])
			p.hand.remove_at(p.hand.size() - 1)
		else:
			s.event("deck_out", {"player": p.slot})
			_end_match(s, other_slot(s, p.slot), "deckout")
			return
	s.event("deck_damage", {"player": p.slot, "amount": amount})


func knock_out(s: GameState, h: HeroState) -> void:
	h.zone = HeroState.ZONE_KO
	var p: PlayerState = s.player(h.owner)
	for cid: String in h.equipment:
		p.graveyard.append(cid)
	for cid: String in h.evolutions:
		p.graveyard.append(cid)
	h.equipment = PackedStringArray()
	h.evolutions = PackedStringArray()
	_drop_cores(s, h)
	h.statuses.clear()
	h.tie_turns = 0
	h.locked_with = PackedStringArray()
	_lost_active(s, h)
	s.event("ko", {"hero": h.id})


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


## The activated hero leaving the map mid-turn leaves its player with Pass only.
func _lost_active(s: GameState, h: HeroState) -> void:
	if s.active.get(h.owner, "") == h.id and not s.only_pass.has(h.owner):
		s.only_pass.append(h.owner)


## Grid knockback: `steps` hexes in direction `dir`. A wall or hero stops it, with
## wall_damage per step not taken; leaving the map is a ring-out.
func knockback(s: GameState, h: HeroState, dir: int, steps: int) -> void:
	if steps <= 0 or not h.is_on_map() or h.has_status("immune_kb"):
		return
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
	if left > 0:
		hero_damage(s, h, left * s.settings.wall_damage)


# =====================================================================================
# End of turn
# =====================================================================================

func _end_phase(s: GameState) -> void:
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
	_check_win(s)
	if s.is_over():
		return
	s.event("turn_end")
	s.turn += 1
	s.initiative = _next_slot(s, s.initiative)


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
			for slot: int in s.active:
				var a: HeroState = s.active_hero(slot)
				if a != null and on.has(a) and s.choices.has(slot) and not s.choices[slot]:
					claimer = slot
			if claimer < 0:
				var by_owner: Dictionary[int, int] = {}
				for h: HeroState in on:
					by_owner[h.owner] = by_owner.get(h.owner, 0) + 1
				for slot: int in by_owner:
					if by_owner[slot] >= 2 and not _battled_on(s, on):
						claimer = slot
		if claimer >= 0 and _claim_blocked(s, claimer):
			s.event("claim_blocked", {"stage": st.id, "player": claimer})
			claimer = -1
		if claimer >= 0:
			st.claimed_by = claimer
			st.terrain_until_turn = s.turn + 1
			s.event("stage_claimed", {"stage": st.id, "player": claimer})


func _claim_blocked(s: GameState, slot: int) -> bool:
	for m: Dictionary in s.turn_mods:
		if str(m.get("kind", "")) == "no_claim" and JsonUtil.as_int(m.get("player", -1)) == slot:
			return true
	return false


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
		_end_match(s, -1, "draw")


func _end_match(s: GameState, winner_slot: int, reason: String) -> void:
	s.winner = winner_slot
	s.result = reason
	s.event("match_end", {"winner": winner_slot, "result": reason})
	s.phase = GameState.PHASE_OVER


# =====================================================================================
# Queries
# =====================================================================================

## The card whose stats the hero uses: its own, or the top evolution's.
func stat_card(h: HeroState) -> CardDef:
	if not h.evolutions.is_empty():
		var evo: CardDef = catalog.get_card(h.evolutions[h.evolutions.size() - 1])
		if evo != null:
			return evo
	return catalog.get_card(h.card_id)


## One current stat: "hp" (max), "dmg", "pwr", "rng" or "kb": the flat value plus what
## passive effects in play add.
func stat(s: GameState, h: HeroState, key: String) -> int:
	return stat_flat(s, h, key) + fx.passive_stat(s, h, key)


## The card's value plus equipment `bonus` fields plus bonuses that last the phase or the
## turn; no passive effects (they use this to avoid asking about themselves).
func stat_flat(_s: GameState, h: HeroState, key: String) -> int:
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
			base = card.rng
		"kb":
			base = card.kb
	for eid: String in h.equipment:
		var e: CardDef = catalog.get_card(eid)
		if e != null:
			base += e.bonus.get(key, 0)
	base += h.phase_bonus.get(key, 0) + h.turn_bonus.get(key, 0)
	return base


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
	if s.phase == GameState.PHASE_BATTLE and s.battle_index >= 0 and s.battle_index < s.battles.size():
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
	return _play(s, m.player, m.str_arg("card"), m.str_arg("hero"), false, null, m.str_arg("replace"))


## FREE_PLAY: a card from the hand goes on `on` without paying its cost (colour and context
## rules do not apply; the card's own limits and phase lock do).
func play_free(s: GameState, slot: int, cid: String, on: HeroState) -> String:
	return _play(s, slot, cid, on.id, true, on)


func _play(s: GameState, slot: int, cid: String, wanted: String, free: bool, forced: HeroState,
		replace: String = "") -> String:
	var p: PlayerState = s.player(slot)
	if not p.hand.has(cid):
		return "card is not in your hand"
	var card: CardDef = catalog.get_card(cid)
	if card == null:
		return "unknown card"
	if not card.is_ready():
		return "card effects are not ready yet"
	var cost: int = 0 if free else card_cost(s, p, card)
	if cost > p.energy:
		return "not enough energy (%d, costs %d)" % [p.energy, cost]
	var phase_lock: String = _play_phase(card)
	if not phase_lock.is_empty() and phase_lock != s.phase.to_upper():
		return "playable in the %s phase" % phase_lock.to_lower()
	var same_colour: Array[HeroState] = []
	if forced != null:
		same_colour.append(forced)
	else:
		var context: Array[HeroState] = card_context_heroes(s, slot)
		if context.is_empty():
			return "no hero to play cards for"
		for h: HeroState in context:
			var hc: CardDef = catalog.get_card(h.card_id)
			if hc != null and hc.color == card.color:
				same_colour.append(h)
		if same_colour.is_empty():
			return "no %s hero to play this for" % card.color
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
	match card.type:
		"Equipment":
			if target.equipment.size() >= s.settings.equipment_limit:
				return "hero already has %d equipment" % s.settings.equipment_limit
			if target.equipment.has(cid):
				return "hero already has that equipment"
			_take_from_hand(p, cid)
			target.equipment.append(cid)
			s.event("equipped", {"card": cid, "hero": target.id})
		"Evolution":
			if not target.is_on_map():
				return "a hero in the start zone cannot evolve"
			var hero_card: CardDef = catalog.get_card(target.card_id)
			if hero_card == null or hero_card.name != card.hero:
				return "this evolution is for %s" % card.hero
			if card.evo != target.evolutions.size() + 1:
				return "needs evolution level %d first" % (card.evo - 1)
			_take_from_hand(p, cid)
			var damage: int = max_hp(s, target) - target.hp
			target.evolutions.append(cid)
			target.hp = maxi(max_hp(s, target) - damage, 0)
			s.event("evolved", {"card": cid, "hero": target.id, "level": card.evo})
		"Assist":
			if p.assists.has(cid):
				return "that assist is already in play"
			if p.assists.size() >= s.settings.assist_limit:
				var out: String = replace
				if not p.assists.has(out):
					return "choose an assist to replace: " + ", ".join(p.assists)
				p.assists.remove_at(p.assists.find(out))
				p.graveyard.append(out)
			_take_from_hand(p, cid)
			p.assists.append(cid)
			s.event("assist", {"card": cid})
		"Action":
			if card.bonus.is_empty() and card.effects.is_empty():
				return "card effects are not ready yet"
			var extra: int = _cost_damage(card)
			if extra > 0 and target.hp <= extra:
				return "cannot pay %d damage" % extra
			_take_from_hand(p, cid)
			for key: String in card.bonus:
				target.add_bonus(target.phase_bonus, key, card.bonus[key])
			p.graveyard.append(cid)
			s.event("action", {"card": cid, "hero": target.id})
		_:
			return "%s cards cannot be played" % card.type
	p.energy -= cost
	_run_play_effects(s, slot, target, card)
	return ""


## Effects that happen as the card is played: PLAY ones, and phase ones on an Action
## (its WHEN only says when it may be played). "If you win" ones wait for the battle.
func _run_play_effects(s: GameState, slot: int, target: HeroState, card: CardDef) -> void:
	var ctx: Dictionary = {"player": slot, "hero": target.id if target != null else "", "card": card.id, "stage": ""}
	for e: FxEffect in card.effects:
		if e.when == "PASSIVE" or e.when == "REVEAL":
			continue
		if card.type != "Action" and e.when != "PLAY":
			continue
		if e.optional and card.type != "Action":
			continue
		if not fx.cond_ok(s, ctx, e):
			continue
		if e.cond == "WIN":
			s.deferred.append({"player": slot, "hero": ctx["hero"], "fx": e.line, "ctx": ctx})
			continue
		var err: String = fx.run(s, ctx, e)
		if not err.is_empty():
			s.event("fx_skipped", {"card": card.id, "why": err})


## The phase an Action is locked to ("" = any card round).
func _play_phase(card: CardDef) -> String:
	if card.type != "Action":
		return ""
	for e: FxEffect in card.effects:
		if e.when != "PLAY" and e.when != "PASSIVE":
			return e.when
	return ""


func _cost_damage(card: CardDef) -> int:
	for e: FxEffect in card.effects:
		for a: Dictionary in e.actions:
			if str(a["verb"]) == "COST_DAMAGE":
				var args: PackedStringArray = a["args"]
				return args[0].to_int()
	return 0


## Energy a card costs this player now: discounts never go below 1 (GDD 10).
func card_cost(s: GameState, p: PlayerState, card: CardDef) -> int:
	var mod: int = fx.cost_mod(s, p, card)
	if card.cost <= 0:
		return maxi(card.cost + mod, 0)
	return maxi(card.cost + mod, 1)


## ROLL_AGAIN: the activated hero rolls once more, right away, in the Roll phase.
func roll_again(s: GameState, slot: int) -> String:
	if s.phase != GameState.PHASE_ROLL or not s.rolled:
		return "roll again only works in the Roll phase after the roll"
	var h: HeroState = s.active_hero(slot)
	if h == null or h.is_ko():
		return "no activated hero to roll"
	s.rolled = false
	s.aims.erase(slot)
	s.choices[slot] = true
	s.pending_rolls = PackedStringArray([h.id])
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


func _take_from_hand(p: PlayerState, cid: String) -> void:
	p.hand.remove_at(p.hand.find(cid))


static func _ids(list: Array[HeroState]) -> PackedStringArray:
	var out := PackedStringArray()
	for h: HeroState in list:
		out.append(h.id)
	return out


## Takes the top evolution off (card to the graveyard); HP only drops to the new max.
func remove_evolution(s: GameState, h: HeroState) -> void:
	if h.evolutions.is_empty():
		return
	var cid: String = h.evolutions[h.evolutions.size() - 1]
	h.evolutions.remove_at(h.evolutions.size() - 1)
	s.player(h.owner).graveyard.append(cid)
	clamp_hp(s, h)
	s.event("evolution_removed", {"card": cid, "hero": h.id})


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
func in_range(s: GameState, a: HeroState, b: HeroState) -> bool:
	if not a.is_on_map() or not b.is_on_map():
		return false
	var gap: int = Hex.distance(a.hex, b.hex) - (1 if a.big else 0) - (1 if b.big else 0)
	return gap <= stat(s, a, "rng")


func reaches_hex(s: GameState, a: HeroState, cell: Vector2i) -> bool:
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
		var card: CardDef = catalog.get_card(st.card_id)
		if card == null or card.terrain == Terrain.Type.NONE:
			continue
		tm.set_patch(st.center, card.terrain, s.map())
	return tm
