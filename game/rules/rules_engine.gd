class_name RulesEngine
extends RefCounted
## Applies moves and roll outcomes to a GameState. Pure logic: no scene, no physics, no
## randomness outside the state's own RNG. Every public call returns "" or an error message
## and never changes the state when it fails. Assumptions the GDD leaves open are listed in
## docs/rules.md.

const DECISION_DAMAGE: String = "damage"
## What a ring-out costs (Marko 2026-11-07): 1 DMG, or a card from the hand instead.
const RING_OUT_DAMAGE: int = 1
const DECISION_RETURN_CORE: String = "return_core"
## After the roll: a player with a "Roll Phase:" card or ability may use one (or pass).
const DECISION_ROLL_OFFER: String = "roll_offer"
## End phase, energy claim variant: the player splits the energy left between the stages its
## heroes stand on: {"energy": n, "stages": [ids], "goal": n}.
const DECISION_STAGE_ENERGY: String = "stage_energy"
## Combo (2026-11-07): the second card of a pair was played in a battle; its player may pay more to turn both into the combo.
const DECISION_COMBO: String = "combo_offer"

var catalog: CardCatalog
## Card effects (docs/fx-keywords.md).
var fx: FxRuntime
## Moves in progress, hero id -> depth (begin_move / end_move): only a hero's outermost move may
## cost energy in a stage, so a knockback's wall damage is part of the knockback. Per hero: a
## stage's reveal effect that knocks another hero back is still that hero's own, outermost, move.
var _moving: Dictionary[String, int] = {}


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
		if s.only_pass.has(m.player):
			return "you can only pass this turn"
		# Combo (2026-11-07): the second card of a pair, for another of the player's heroes in this battle,
		# is offered as the combo first; the card is played (or replaced) when the offer is answered.
		var offer: Dictionary = _combo_offer(s, m)
		if not offer.is_empty():
			s.pending.append(offer)
			s.passed = PackedInt32Array()
			s.to_act = _next_slot(s, s.to_act)
			return ""
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
				return "choose the combo, or pass to play the card as it is"
			var option: Dictionary = {}
			for o: Variant in JsonUtil.as_array(d.get("combos", [])):
				if str(JsonUtil.as_dict(o).get("id", "")) == picked:
					option = JsonUtil.as_dict(o)
			if not picked.is_empty() and option.is_empty():
				return "that combo is not on offer"
			var cid: String = str(d.get("card", ""))
			var wanted: String = str(d.get("hero", ""))
			if option.is_empty():
				# Declined: the card goes as it would have.
				var err: String = _play(s, who, cid, wanted, false, null, str(d.get("replace", "")))
				if not err.is_empty():
					return err
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
		if p != null and not p.surrendered and h != null and not h.is_ko() and s.choices.get(slot, false):
			var abilities := PackedStringArray()
			for a: Dictionary in fx.usable_abilities(s, slot):
				abilities.append(str(a["key"]))
			var cards := PackedStringArray()
			var hero_card: CardDef = catalog.get_card(h.card_id)
			for cid: String in p.hand:
				var card: CardDef = catalog.get_card(cid)
				if card == null or not card.is_ready() or _play_phase(card) != "ROLL":
					continue
				if hero_card != null and not card.plays_for_color(hero_card.color):
					continue
				if hero_card != null and not JsonUtil.as_bool(FirstTag.play_verdict(catalog, card, hero_card, stat_card(h))["ok"]):
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
		var h: HeroState = s.hero(r.ball_id)
		if h == null or h.is_ko():
			continue
		var by_team: int = causes.get(r.ball_id, -1)
		_apply_result(s, h, r, by_team)
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
		st.revealed = true
		# A wind blows in a direction drawn now and kept (GDD 6, 2026-10-26); it goes into the
		# state and the replay with the stage.
		st.wind_dir = s.random_int(6)
		s.event("stage_revealed", {"stage": st.id, "by": h.id, "wind": st.wind_dir})
		fx.on_reveal(s, st, h)


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
	if phase == GameState.PHASE_ROLL:
		# Where everyone stands before the balls fly, for REVERSE_ROLL.
		s.roll_snapshot.clear()
		for h: HeroState in s.heroes:
			s.roll_snapshot[h.id] = {"zone": h.zone, "hex": Hex.to_json(h.hex)}
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
		for id: String in JsonUtil.as_strings(d.get("targets", [])):
			var h: HeroState = s.hero(id)
			if h != null and h.is_on_map():
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
	var fighters: Array = []
	for h: HeroState in members:
		fighters.append(h.id)
	s.event("battle", {"index": index, "power": power.duplicate(), "heroes": fighters})
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
		knockback(s, l, Hex.direction_towards(from.hex, l.hex), kb, best)
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
	if not unblockable:
		amount = maxi(amount + fx.damage_mod(s, h), 0)
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


## The activated hero leaving the map mid-turn leaves its player with Pass only.
func _lost_active(s: GameState, h: HeroState) -> void:
	if s.active.get(h.owner, "") == h.id and not s.only_pass.has(h.owner):
		s.only_pass.append(h.owner)


## Grid knockback: `steps` hexes in direction `dir`. A wall or hero stops it (no damage,
## Marko 2026-11-07); leaving the map is a ring-out.
## Knockback (GDD 10). In the "physics" mode (the game) the hero is not moved here: the
## knockback waits in `pending_knockbacks` for the sim (apply_knockback). On the grid it goes
## hex by hex, stopped by walls and heroes.
## `by_team`: the team whose doing it is (a battle's winners, an effect's player), for the
## energy claim variant (end_move).
func knockback(s: GameState, h: HeroState, dir: int, steps: int, by_team: int = -1) -> void:
	if steps <= 0 or not h.is_on_map() or h.has_status("immune_kb"):
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
			st.terrain_until_turn = s.turn + 1
			s.event("stage_claimed", {"stage": st.id, "player": claimer})


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


## `n` energy of `slot` into `st`, up to the goal (more is lost).
func _put_energy(s: GameState, slot: int, st: StageState, n: int) -> void:
	if st == null or n <= 0:
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
			if st.progress[slot] < s.settings.stage_goal:
				continue
			if _claim_blocked(s, slot, st):
				s.event("claim_blocked", {"stage": st.id, "player": slot})
				continue
			st.claimed_by = slot
			st.terrain_until_turn = s.turn + 1
			s.event("stage_claimed", {"stage": st.id, "player": slot, "energy": st.progress[slot]})
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

## The card whose stats the hero uses: its own, or the top evolution's.
func stat_card(h: HeroState) -> CardDef:
	if not h.evolutions.is_empty():
		var evo: CardDef = catalog.get_card(h.evolutions[h.evolutions.size() - 1])
		if evo != null:
			return evo
	return catalog.get_card(h.card_id)


## One current stat: "hp" (max), "dmg", "pwr", "rng" or "kb": the flat value plus what
## passive effects in play add. Never below 0 (a Debuff core can pull a small stat under).
func stat(s: GameState, h: HeroState, key: String) -> int:
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
		if e != null:
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
	return _play(s, m.player, m.str_arg("card"), m.str_arg("hero"), false, null, m.str_arg("replace"))


## FREE_PLAY: a card from the hand goes on `on` without paying its cost (colour and context
## rules do not apply; the card's own limits and phase lock do).
func play_free(s: GameState, slot: int, cid: String, on: HeroState) -> String:
	return _play(s, slot, cid, on.id, true, on)


## Why play_free would refuse `cid` on `on` ("" when it would go), tried on a copy.
func free_play_error(s: GameState, slot: int, cid: String, on: HeroState) -> String:
	var copy: GameState = GameState.from_dict(s.to_dict())
	return play_free(copy, slot, cid, copy.hero(on.id))


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
		var v: Dictionary = FirstTag.play_verdict(catalog, card, catalog.get_card(h.card_id), stat_card(h))
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
	if cost > p.energy:
		return "not enough energy (%d, costs %d)" % [p.energy, cost]
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
			_drop_unfit_equipment(s, target)
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
			s.event("assist", {"card": cid, "player": slot})
			_note_played(s, slot, cid, "", {})
		"Action":
			if card.bonus.is_empty() and card.effects.is_empty():
				return "card effects are not ready yet"
			var extra: int = _cost_damage(card)
			if extra > 0 and target.hp <= extra:
				return "cannot pay %d damage" % extra
			# An Action whose effect has nothing to work on (no hex for its wall, no core in reach)
			# is not played: it stays in the hand and costs nothing.
			var blocked: String = _play_blocker(s, slot, target, card)
			if not blocked.is_empty():
				return blocked
			_take_from_hand(p, cid)
			for key: String in card.bonus:
				target.add_bonus(target.phase_bonus, key, card.bonus[key])
			p.graveyard.append(cid)
			s.event("action", {"card": cid, "hero": target.id})
			_note_played(s, slot, cid, target.id, card.bonus)
		_:
			return "%s cards cannot be played" % card.type
	p.energy -= cost
	_run_play_effects(s, slot, target, card)
	return ""


## A card played in the battle being fought, for the combo offer: who, which hero (an Assist has none)
## and the stat bonus it put on the hero (undone when a combo replaces it).
func _note_played(s: GameState, slot: int, cid: String, hero: String, bonus: Dictionary) -> void:
	if s.phase != GameState.PHASE_BATTLE or s.battle_index < 0 or s.battle_index >= s.battles.size():
		return
	var b: Dictionary = s.battles[s.battle_index]
	var played: Array = JsonUtil.as_array(b.get("played", []))
	played.append({"player": slot, "card": cid, "hero": hero, "bonus": bonus.duplicate(), "used": false})
	b["played"] = played


## Combo (Marko and the card author, 2026-11-07): when the second card of a combo's pair is played in a
## battle for another of the player's heroes in it (an Assist counts without a hero), the player may pay
## the combo's extra energy on top of the card's cost and both cards become the combo. The decision, or
## {} when no combo is on offer (the play then goes as usual). The card is tried on a copy first, so an
## illegal play is refused the usual way.
func _combo_offer(s: GameState, m: Move) -> Dictionary:
	if s.phase != GameState.PHASE_BATTLE or s.battle_index < 0 or s.battle_index >= s.battles.size():
		return {}
	var cid: String = m.str_arg("card")
	var card: CardDef = catalog.get_card(cid)
	if card == null or (card.type != "Action" and card.type != "Assist"):
		return {}
	var mine: Array[HeroState] = card_context_heroes(s, m.player)
	if mine.size() < 2:
		return {}
	var played: Array = JsonUtil.as_array(s.battles[s.battle_index].get("played", []))
	var combos: Array = []
	for combo: CardDef in catalog.of_type("Combo"):
		if combo.ingredients.size() != 2 or not combo.ingredients.has(cid) or not combo.is_ready():
			continue
		var other: String = combo.ingredients[1] if combo.ingredients[0] == cid else combo.ingredients[0]
		if other == cid:
			continue
		for rec: Variant in played:
			var r: Dictionary = JsonUtil.as_dict(rec)
			if JsonUtil.as_int(r.get("player", -1), -1) == m.player and str(r.get("card", "")) == other and not JsonUtil.as_bool(r.get("used", false)):
				combos.append({"id": combo.id, "with": other, "with_hero": str(r.get("hero", "")), "extra": combo.extra_cost})
				break
	if combos.is_empty():
		return {}
	# The card as it would be played: its hero and its cost, from a copy.
	var copy: GameState = GameState.from_dict(s.to_dict())
	var before: int = copy.player(m.player).energy
	if not _play_card(copy, m).is_empty():
		return {}
	var cost: int = before - copy.player(m.player).energy
	var hero: String = ""
	for i: int in range(copy.log.size() - 1, -1, -1):
		var e: Dictionary = copy.log[i]
		if (str(e.get("type", "")) == "action" or str(e.get("type", "")) == "assist") and str(e.get("card", "")) == cid:
			hero = str(e.get("hero", ""))
			break
	var options: Array = []
	for o: Variant in combos:
		var c: Dictionary = JsonUtil.as_dict(o)
		var with_hero: String = str(c.get("with_hero", ""))
		# Two different heroes of the player in this battle (an Assist has no hero and pairs with any).
		if not hero.is_empty() and not with_hero.is_empty() and with_hero == hero:
			continue
		if s.player(m.player).energy < cost + JsonUtil.as_int(c.get("extra", 0)):
			continue
		options.append(c)
	if options.is_empty():
		return {}
	return {"type": DECISION_COMBO, "player": m.player, "card": cid, "hero": hero, "cost": cost,
		"replace": m.str_arg("replace"), "combos": options}


## The combo is paid: the second card leaves the hand without resolving, the first card's stat bonus
## comes off its hero and its battle effects still waiting are dropped, and the combo's effects run for
## the player with the second card's hero (the first one's for an Assist) in this battle.
func _accept_combo(s: GameState, slot: int, d: Dictionary, option: Dictionary) -> String:
	var p: PlayerState = s.player(slot)
	var cid: String = str(d.get("card", ""))
	var combo: CardDef = catalog.get_card(str(option.get("id", "")))
	if combo == null or not p.hand.has(cid):
		return "that combo cannot be made now"
	var total: int = JsonUtil.as_int(d.get("cost", 0)) + combo.extra_cost
	if p.energy < total:
		return "not enough energy (%d, costs %d)" % [p.energy, total]
	var b: Dictionary = s.battles[s.battle_index]
	var played: Array = JsonUtil.as_array(b.get("played", []))
	var first: Dictionary = {}
	for rec: Variant in played:
		var r: Dictionary = JsonUtil.as_dict(rec)
		if JsonUtil.as_int(r.get("player", -1), -1) == slot and str(r.get("card", "")) == str(option.get("with", "")) and not JsonUtil.as_bool(r.get("used", false)):
			first = r
			break
	if first.is_empty():
		return "the other card of the combo is no longer in this battle"
	p.energy -= total
	_take_from_hand(p, cid)
	p.graveyard.append(cid)
	first["used"] = true
	var first_hero: HeroState = s.hero(str(first.get("hero", "")))
	if first_hero != null:
		var bonus: Dictionary = JsonUtil.as_dict(first.get("bonus", {}))
		for k: Variant in bonus:
			first_hero.add_bonus(first_hero.phase_bonus, str(k), -JsonUtil.as_int(bonus[k]))
	var kept: Array[Dictionary] = []
	for x: Dictionary in s.deferred:
		var ctx: Dictionary = JsonUtil.as_dict(x.get("ctx", {}))
		if JsonUtil.as_int(x.get("player", -1), -1) == slot and str(ctx.get("card", "")) == str(first.get("card", "")):
			continue
		kept.append(x)
	s.deferred = kept
	var hero: String = str(d.get("hero", ""))
	if hero.is_empty():
		hero = str(first.get("hero", ""))
	s.event("combo", {"combo": combo.id, "cards": [str(first.get("card", "")), cid], "heroes": [str(first.get("hero", "")), str(d.get("hero", ""))], "player": slot, "extra": combo.extra_cost})
	var h: HeroState = s.hero(hero)
	for k: String in combo.bonus:
		if h != null:
			h.add_bonus(h.phase_bonus, k, combo.bonus[k])
	_run_play_effects(s, slot, h, combo, s.battle_index)
	return ""


## Why the first effect an Action runs as it is played cannot start ("" when it can).
func _play_blocker(s: GameState, slot: int, target: HeroState, card: CardDef) -> String:
	var ctx: Dictionary = {"player": slot, "hero": target.id if target != null else "", "card": card.id, "stage": ""}
	for e: FxEffect in card.effects:
		if e.when == "PASSIVE" or e.when == "REVEAL" or e.cond == "WIN":
			continue
		if not fx.cond_ok(s, ctx, e):
			continue
		return fx.first_error(s, ctx, e)
	return ""


## Effects that happen as the card is played: PLAY ones, and phase ones on an Action
## (its WHEN only says when it may be played). "If you win" ones wait for the battle.
func _run_play_effects(s: GameState, slot: int, target: HeroState, card: CardDef, battle: int = -1) -> void:
	var ctx: Dictionary = {"player": slot, "hero": target.id if target != null else "", "card": card.id, "stage": ""}
	if battle >= 0:
		ctx["battle"] = battle
	for e: FxEffect in card.effects:
		if e.when == "PASSIVE" or e.when == "REVEAL":
			continue
		if card.type != "Action" and card.type != "Combo" and e.when != "PLAY":
			continue
		if e.optional and card.type != "Action":
			continue
		if not fx.cond_ok(s, ctx, e):
			continue
		if e.cond == "WIN" and not e.arms_on_play():
			s.deferred.append({"player": slot, "hero": ctx["hero"], "fx": e.line, "ctx": ctx})
			continue
		var err: String = fx.run(s, ctx, e)
		if not err.is_empty():
			s.event("fx_skipped", {"card": card.id, "why": err})
	# A core the card took off comes back now, after the card's own choices.
	_queue_core_returns(s)


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


## Energy a card costs this player now: discounts never go below 1 (GDD 10). `hero` is the hero
## the card is played for (a colorless card's own-cost bonus); without one, the cheapest of the
## heroes it could go to now, so the hand shows the price the player can get.
func card_cost(s: GameState, p: PlayerState, card: CardDef, hero: HeroState = null) -> int:
	var mod: int = fx.cost_mod(s, p, card)
	if hero == null:
		hero = _cheapest_for(s, p, card, playable_heroes(s, p.slot, card))
	mod += fx.own_cost(s, p, card, hero)
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
		if JsonUtil.as_bool(FirstTag.play_verdict(catalog, card, hc, stat_card(h))["ok"]):
			out.append(h)
	return out


## Of these heroes, the one the card costs least for (its colour bonus); null when none.
func _cheapest_for(s: GameState, p: PlayerState, card: CardDef, heroes: Array[HeroState]) -> HeroState:
	var best: HeroState = null
	var best_cost: int = 0
	for h: HeroState in heroes:
		var c: int = fx.own_cost(s, p, card, h)
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
	_drop_unfit_equipment(s, h)


## Equipment whose first tag the hero no longer satisfies (an evolution came or went) falls
## into the graveyard (GDD 10, 2026-10-26).
func _drop_unfit_equipment(s: GameState, h: HeroState) -> void:
	for cid: String in h.equipment.duplicate():
		var c: CardDef = catalog.get_card(cid)
		if c == null:
			continue
		var v: Dictionary = FirstTag.play_verdict(catalog, c, catalog.get_card(h.card_id), stat_card(h))
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
		var card: CardDef = catalog.get_card(st.card_id)
		if card == null or card.terrain == Terrain.Type.NONE:
			continue
		tm.set_patch(st.center, card.terrain, s.map(), maxi(0, st.wind_dir))
	return tm
