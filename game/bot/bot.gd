class_name Bot
extends RefCounted
## The computer opponent (GDD 12). Both levels pick heroes by simple rules and choose a throw by
## trying many on a light model (TerrainPhysics.roll_path: the sim's slow-down and terrain, no
## bounces) and scoring where it ends; Hard also corrects the power for Mud, Ice, hills and
## wind on the way to its target. Easy tries fewer throws, aims sloppily and plays the
## first card that helps; Hard tries more, aims tightly and tries every card, ability and choice
## on a copy of the state (the rules engine without graphics) to keep the best one.

enum Level { EASY, HARD }

const RING_OUT: float = -100.0

var level: Level = Level.EASY
var rng := RandomNumberGenerator.new()


func _init(seed_: int, level_: Level = Level.EASY) -> void:
	rng.seed = seed_
	level = level_


static func level_from(name: String) -> Level:
	return Level.HARD if name.to_lower() == "hard" else Level.EASY


static func level_name(l: Level) -> String:
	return "hard" if l == Level.HARD else "easy"


func hard() -> bool:
	return level == Level.HARD


## The bot's next move for `slot`, or null when it has nothing to do right now.
## `positions` maps hero ids to their world (x, z) position (heroes on a strip have no hex).
func next_move(engine: RulesEngine, s: GameState, slot: int, positions: Dictionary[String, Vector2],
		tuning: PhysicsTuning) -> Move:
	if s.is_over():
		return null
	if not s.pending.is_empty():
		var d: Dictionary = s.pending[0]
		if JsonUtil.as_int(d.get("player", -1), -1) != slot:
			return null
		return _decide(engine, s, slot, d)
	match s.phase:
		GameState.PHASE_SETUP_STAGES, GameState.PHASE_SETUP_CORES:
			if s.setup_turn == slot:
				return _place(engine, s, slot)
		GameState.PHASE_MULLIGAN:
			if not s.player(slot).mulligan_done:
				return Move.make(Move.MULLIGAN, slot, {"keep": _keeps_hand(engine, s, slot)})
		GameState.PHASE_SELECT:
			if not s.active.has(slot):
				return _select(engine, s, slot)
		GameState.PHASE_PREROLL:
			if not s.choices.has(slot) and s.active_hero(slot) != null:
				return Move.make(Move.CHOICE, slot, {"roll": _wants_roll(engine, s, s.active_hero(slot))})
			return _card_round(engine, s, slot)
		GameState.PHASE_ROLL:
			if s.choices.get(slot, false) and not s.aims.has(slot) and s.active_hero(slot) != null:
				return _aim(engine, s, s.active_hero(slot), positions, tuning)
			if s.rolled:
				return _card_round(engine, s, slot)
		GameState.PHASE_POSTROLL, GameState.PHASE_BATTLE:
			return _card_round(engine, s, slot)
	return null


# =====================================================================================
# How good a state is for `slot` (Hard compares these; Easy uses them as "does it help")
# =====================================================================================

func evaluate(engine: RulesEngine, s: GameState, slot: int) -> float:
	var team: int = s.team_of(slot)
	if s.is_over():
		if s.winner < 0:
			return 0.0
		return 1000.0 if s.team_of(s.winner) == team else -1000.0
	var score: float = 0.0
	for h: HeroState in s.heroes:
		var sign: float = 1.0 if s.team_of(h.owner) == team else -1.0
		if h.is_ko():
			score -= sign * 40.0
			continue
		score += sign * (h.hp + h.cores.size() * 4.0 + h.equipment.size() * 3.0 + h.evolutions.size() * 5.0)
	for p: PlayerState in s.players:
		var sign: float = 1.0 if p.team == team else -1.0
		score += sign * (engine.claimed_count(s, p.slot) * 30.0 + mini(p.hand.size(), 8) * 0.5)
		if p.deck.is_empty():
			score -= sign * 3.0
	# The battle being fought now: the Power gap decides it.
	if s.phase == GameState.PHASE_BATTLE and s.battle_index >= 0 and s.battle_index < s.battles.size():
		var mine: int = 0
		var theirs: int = 0
		for id: String in JsonUtil.as_strings(s.battles[s.battle_index].get("heroes", [])):
			var h: HeroState = s.hero(id)
			if h == null or not h.is_on_map():
				continue
			if s.team_of(h.owner) == team:
				mine += engine.stat(s, h, "pwr")
			else:
				theirs += engine.stat(s, h, "pwr")
		if mine > 0 and theirs > 0:
			score += clampf((mine - theirs) / 1000.0, -5.0, 5.0) * 4.0 + (8.0 if mine > theirs else -8.0 if mine < theirs else 0.0)
	return score


## The state after `m`, or null when the engine refuses it.
func _try(engine: RulesEngine, s: GameState, m: Move) -> GameState:
	var trial: GameState = GameState.from_dict(s.to_dict())
	return trial if engine.apply(trial, m).is_empty() else null


# =====================================================================================
# Decisions
# =====================================================================================

func _decide(engine: RulesEngine, s: GameState, slot: int, d: Dictionary) -> Move:
	match str(d.get("type", "")):
		RulesEngine.DECISION_DAMAGE:
			var amount: int = JsonUtil.as_int(d.get("amount", 0))
			var options: Array[Move] = [Move.make(Move.DAMAGE_TO, slot, {"target": "deck"})]
			for id: String in JsonUtil.as_strings(d.get("targets", [])):
				options.append(Move.make(Move.DAMAGE_TO, slot, {"target": id}))
			if hard():
				return _best(engine, s, slot, options)
			for id: String in JsonUtil.as_strings(d.get("targets", [])):
				var h: HeroState = s.hero(id)
				if h != null and h.hp > amount + 2:
					return Move.make(Move.DAMAGE_TO, slot, {"target": id})
			return options[0]
		RulesEngine.DECISION_RETURN_CORE:
			var c: CoreState = s.core(str(d.get("core", "")))
			var cells: Array[Vector2i] = s.map().cells()
			var start: int = rng.randi_range(0, cells.size() - 1)
			for i: int in cells.size():
				var a: Vector2i = cells[(start + i) % cells.size()]
				if engine.core_return_error(s, c, a).is_empty():
					return Move.make(Move.RETURN_CORE, slot, {"core": c.id, "hex": Hex.to_json(a)})
		FxRuntime.DECISION_CHOOSE:
			var options: Array = JsonUtil.as_array(d.get("options", []))
			if options.is_empty():
				return null
			var by_index: bool = str(d.get("kind", "")) == "option"
			var moves: Array[Move] = []
			for i: int in options.size():
				moves.append(Move.make(Move.CHOOSE, slot, {"value": i if by_index else options[i]}))
			if hard():
				return _best(engine, s, slot, moves)
			return moves[rng.randi_range(0, moves.size() - 1)]
	return null


## The move whose resulting state evaluates best (refused moves are skipped).
func _best(engine: RulesEngine, s: GameState, slot: int, moves: Array[Move]) -> Move:
	var best: Move = null
	var best_v: float = -INF
	for m: Move in moves:
		var after: GameState = _try(engine, s, m)
		if after == null:
			continue
		var v: float = evaluate(engine, after, slot)
		if v > best_v:
			best_v = v
			best = m
	return best if best != null else moves[0]


func _keeps_hand(engine: RulesEngine, s: GameState, slot: int) -> bool:
	if not hard():
		return true
	# Hard sends back a hand with nothing to play in the first turns.
	var cheap: int = 0
	for cid: String in s.player(slot).hand:
		var c: CardDef = engine.catalog.get_card(cid)
		if c != null and c.cost <= 2 and c.is_ready():
			cheap += 1
	return cheap >= 2


## Setup: Easy puts things anywhere legal; Hard puts its stages on its own side of the middle
## and its cores as close to the middle as the rules allow (they are in the opponent's half).
func _place(engine: RulesEngine, s: GameState, slot: int) -> Move:
	var cells: Array[Vector2i] = s.map().cells()
	var team: int = s.team_of(slot)
	var n: int = s.settings.map_size
	var mine := func(a: Vector2i) -> float:
		var row: int = s.row_of(a)
		return float(row) if team == 0 else float(n - 1 - row)
	if s.phase == GameState.PHASE_SETUP_STAGES:
		for st: StageState in s.stages:
			if st.owner != slot or st.placed:
				continue
			var legal: Array[Vector2i] = []
			for a: Vector2i in cells:
				if engine.stage_placement_error(s, st, a).is_empty():
					legal.append(a)
			if legal.is_empty():
				return null
			if hard():
				legal.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return mine.call(a) > mine.call(b))
				return Move.make(Move.PLACE_STAGE, slot, {"stage": st.id, "hex": Hex.to_json(legal[rng.randi_range(0, mini(3, legal.size() - 1))])})
			return Move.make(Move.PLACE_STAGE, slot, {"stage": st.id, "hex": Hex.to_json(legal[rng.randi_range(0, legal.size() - 1)])})
		return null
	for c: CoreState in s.cores:
		if c.owner != slot or c.place != CoreState.UNPLACED:
			continue
		var legal: Array[Vector2i] = []
		for a: Vector2i in cells:
			if engine.core_placement_error(s, c, a).is_empty():
				legal.append(a)
		if legal.is_empty():
			return null
		if hard():
			legal.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return mine.call(a) > mine.call(b))
			return Move.make(Move.PLACE_CORE, slot, {"core": c.id, "hex": Hex.to_json(legal[rng.randi_range(0, mini(3, legal.size() - 1))])})
		return Move.make(Move.PLACE_CORE, slot, {"core": c.id, "hex": Hex.to_json(legal[rng.randi_range(0, legal.size() - 1)])})
	return null


## GDD 12: nearest to an enemy, most HP, the one on a stage; everyone has to enter the map first.
func _select(engine: RulesEngine, s: GameState, slot: int) -> Move:
	var options: Array[HeroState] = engine.selectable_heroes(s, slot)
	if options.is_empty():
		return Move.make(Move.SELECT, slot, {"hero": ""})
	var best: HeroState = options[0]
	var best_v: float = -INF
	for h: HeroState in options:
		var v: float = h.hp * 0.5
		if h.zone == HeroState.ZONE_STRIP:
			v += 20.0
		else:
			var st: StageState = s.stage_at(h.hex)
			if st != null and not st.is_claimed() and _enemies_on(s, st, h).is_empty():
				v += 25.0
			var e: HeroState = _nearest_enemy(s, h)
			if e != null:
				var gap: int = Hex.distance(h.hex, e.hex)
				if gap <= engine.stat(s, h, "rng") + 4:
					v += 10.0 if engine.stat(s, h, "pwr") >= engine.stat(s, e, "pwr") else -5.0
		if not hard():
			v += rng.randf_range(0.0, 15.0)
		if v > best_v:
			best_v = v
			best = h
	return Move.make(Move.SELECT, slot, {"hero": best.id})


## Stay to claim an open stage it stands on alone; otherwise roll.
func _wants_roll(engine: RulesEngine, s: GameState, h: HeroState) -> bool:
	if h.zone != HeroState.ZONE_MAP:
		return true
	var st: StageState = s.stage_at(h.hex)
	if st == null or st.is_claimed():
		return true
	if not _enemies_on(s, st, h).is_empty():
		return true
	if hard():
		# Stay only if no stronger enemy can reach it this turn.
		for e: HeroState in s.heroes:
			if e.is_on_map() and not s.same_team(e, h) and engine.in_range(s, e, h) \
					and engine.stat(s, e, "pwr") > engine.stat(s, h, "pwr"):
				return true
	return false


func _enemies_on(s: GameState, st: StageState, h: HeroState) -> Array[HeroState]:
	var out: Array[HeroState] = []
	for o: HeroState in s.heroes_on_stage(st):
		if not s.same_team(o, h):
			out.append(o)
	return out


func _nearest_enemy(s: GameState, h: HeroState) -> HeroState:
	var best: HeroState = null
	for o: HeroState in s.heroes:
		if not o.is_on_map() or s.same_team(o, h):
			continue
		if best == null or (h.is_on_map() and Hex.distance(h.hex, o.hex) < Hex.distance(h.hex, best.hex)):
			best = o
	return best


# =====================================================================================
# Throwing: try many throws on the analytic model, keep the best, then aim with noise
# =====================================================================================

func _aim(engine: RulesEngine, s: GameState, h: HeroState, positions: Dictionary[String, Vector2],
		tuning: PhysicsTuning) -> Move:
	var from: Vector2 = positions.get(h.id, s.map().to_world(h.hex))
	var card: CardDef = engine.catalog.get_card(h.card_id)
	var full: float = tuning.full_power_hexes(card.wt if card != null else 2) * tuning.hex_spacing()
	var targets: Array[Vector2] = _targets(s, h)
	var tries: int = 50 if hard() else 20
	var wt: int = card.wt if card != null else 2
	# The ground in force (Ice, Mud, hills, wind): throws are previewed over it.
	var tm: TerrainMap = engine.terrain(s)
	var m: HexMap = s.map()
	var best_dir := Vector2(0, -1 if s.team_of(h.owner) == 0 else 1)
	var best_power: float = 0.5
	var best_v: float = -INF
	for _i: int in tries:
		var dir: Vector2
		var dist: float
		var aimed: bool = not targets.is_empty() and rng.randf() < 0.75
		if aimed:
			var t: Vector2 = targets[rng.randi_range(0, targets.size() - 1)]
			dir = (t - from).normalized()
			dist = from.distance_to(t) * rng.randf_range(0.8, 1.1)
		else:
			dir = Vector2.from_angle(rng.randf_range(0.0, TAU))
			dist = full * rng.randf_range(0.15, 1.0)
		var power: float = clampf(dist / full, 0.05, 1.0)
		var path: PackedVector2Array = TerrainPhysics.roll_path(tm, m, tuning, wt, from, dir, power)
		if aimed and hard() and not tm.is_empty():
			# Mud stops short, Ice and a tailwind carry on: Hard corrects the power to the target
			# (on plain ground the distance grows with the power, so a ratio is close enough).
			for _k: int in 2:
				var went: float = from.distance_to(path[path.size() - 1])
				if went < 0.05 or absf(went - dist) < 0.3:
					break
				power = clampf(power * dist / went, 0.05, 1.0)
				path = TerrainPhysics.roll_path(tm, m, tuning, wt, from, dir, power)
		var v: float = _score_path(engine, s, h, path)
		if v > best_v:
			best_v = v
			best_dir = dir
			best_power = power
	# The hand is never perfect: Easy misses more.
	var spread: float = 0.04 if hard() else 0.15
	var dir_out: Vector2 = best_dir.rotated(rng.randf_range(-spread, spread))
	var power_out: float = clampf(best_power * rng.randf_range(1.0 - spread, 1.0 + spread), 0.05, 1.0)
	return Move.make(Move.AIM, h.owner, {"dir": [dir_out.x, dir_out.y], "power": power_out})


## Places worth throwing towards: enemies (stopping short by the hero's range), open stages, cores.
func _targets(s: GameState, h: HeroState) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for e: HeroState in s.heroes:
		if e.is_on_map() and not s.same_team(e, h):
			out.append(s.map().to_world(e.hex))
	for st: StageState in s.stages:
		if st.placed and not st.is_claimed():
			out.append(s.map().to_world(st.center))
	for c: CoreState in s.cores:
		if c.place == CoreState.ON_FIELD:
			out.append(s.map().to_world(c.hex))
	return out


## How good a throw is that rolls along `path` (TerrainPhysics.roll_path: terrain counted,
## other balls not): ring-out, cores picked on the way, where it stops.
func _score_path(engine: RulesEngine, s: GameState, h: HeroState, path: PackedVector2Array) -> float:
	var m: HexMap = s.map()
	var entered: bool = m.contains(m.from_world(path[0]))
	var picked: int = 0
	var free_slots: int = s.settings.core_slots - h.cores.size()
	var seen := {}
	for p: Vector2 in path:
		var a: Vector2i = m.from_world(p)
		if m.contains(a):
			entered = true
			var c: CoreState = s.core_at(a)
			if c != null and not seen.has(c.id) and picked < free_slots:
				seen[c.id] = true
				picked += 1
		elif entered:
			return RING_OUT
	var end: Vector2i = m.from_world(path[path.size() - 1])
	if not m.contains(end):
		# Still on its strip: a wasted throw, but not a ring-out.
		return -30.0
	var v: float = picked * 8.0
	if s.hero_at(end, h) != null:
		v -= 5.0
	var st: StageState = s.stage_at(end)
	if st != null and not st.is_claimed():
		v += 25.0 if not st.revealed else 20.0
	var my_rng: int = engine.stat(s, h, "rng")
	var my_pwr: int = engine.stat(s, h, "pwr")
	var near: int = 999
	for e: HeroState in s.heroes:
		if not e.is_on_map() or s.same_team(e, h):
			continue
		var gap: int = Hex.distance(end, e.hex) - (1 if h.big else 0) - (1 if e.big else 0)
		near = mini(near, gap)
		var e_pwr: int = engine.stat(s, e, "pwr")
		if gap <= my_rng:
			v += 15.0 if my_pwr >= e_pwr else -8.0
		if gap <= engine.stat(s, e, "rng") and e_pwr > my_pwr:
			v -= 12.0
	# Otherwise move towards the action rather than away from it.
	if near < 999:
		v -= near * 0.3
	return v


# =====================================================================================
# Cards and abilities
# =====================================================================================

func _card_round(engine: RulesEngine, s: GameState, slot: int) -> Move:
	if s.round_over or s.to_act != slot or s.awaiting_roll:
		return null
	if s.phase == GameState.PHASE_ROLL and not s.rolled:
		return null
	var options: Array[Move] = []
	var seen := {}
	for cid: String in s.player(slot).hand:
		if seen.has(cid):
			continue
		seen[cid] = true
		options.append(Move.make(Move.PLAY_CARD, slot, {"card": cid}))
	for a: Dictionary in engine.fx.usable_abilities(s, slot):
		options.append(Move.make(Move.USE_ABILITY, slot, {"hero": a["hero"], "card": a["card"], "index": a["index"]}))
	var now: float = evaluate(engine, s, slot)
	if hard():
		var best: Move = null
		var best_gain: float = 0.5
		for m: Move in options:
			var after: GameState = _try(engine, s, m)
			if after == null:
				continue
			var gain: float = evaluate(engine, after, slot) - now
			if gain > best_gain:
				best_gain = gain
				best = m
		return best if best != null else Move.make(Move.PASS, slot)
	# Easy: the first thing in hand that helps right away.
	for m: Move in options:
		var after: GameState = _try(engine, s, m)
		if after != null and evaluate(engine, after, slot) > now:
			return m
	return Move.make(Move.PASS, slot)
