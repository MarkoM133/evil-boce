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
## The energy claim variant: energy already in a stage, and energy about to go in, against a
## claimed stage (it can still be lost half by half, or never reach the goal).
const HELD: float = 0.75
const BANKED: float = 0.6

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
		# Roll offers of one stop wait together: the bot answers its own whenever it sits.
		if str(d.get("type", "")) == RulesEngine.DECISION_ROLL_OFFER:
			var i: int = engine.roll_offer_index(s, slot)
			return _decide(engine, s, slot, s.pending[i]) if i >= 0 else null
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
		GameState.PHASE_START:
			if not s.active.has(slot):
				var m: Move = _select(engine, s, slot)
				var h: HeroState = s.hero(m.str_arg("hero"))
				if h != null:
					m.data["roll"] = _wants_roll(engine, s, h)
				return m
		GameState.PHASE_ROLL:
			if s.choices.get(slot, false) and not s.aims.has(slot) and s.active_hero(slot) != null:
				return _aim(engine, s, s.active_hero(slot), positions, tuning)
		GameState.PHASE_PREROLL, GameState.PHASE_POSTROLL, GameState.PHASE_BATTLE:
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
		if s.settings.energy_claims():
			score += sign * _energy_value(engine, s, p)
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


## The energy claim variant: what a player's energy in the stages is worth (a claimed stage is
## 30; energy in a stage still has to be held there, so a little less), plus the energy it has
## now when one of its heroes stands on an open stage, which goes in at the End phase unless a
## card spends it. That makes a card worth playing only when it does more than the energy would.
func _energy_value(engine: RulesEngine, s: GameState, p: PlayerState) -> float:
	var goal: float = maxf(float(s.settings.stage_goal), 1.0)
	var v: float = 0.0
	for st: StageState in s.stages:
		if not st.is_claimed():
			v += st.progress_of(p.slot) / goal * 30.0 * HELD
	if p.energy > 0 and not engine.energy_stages(s, p.slot).is_empty():
		v += p.energy / goal * 30.0 * BANKED
	return v


## The state after `m`, or null when the engine refuses it.
func _try(engine: RulesEngine, s: GameState, m: Move) -> GameState:
	var trial: GameState = GameState.from_dict(s.to_dict())
	return trial if engine.apply(trial, m).is_empty() else null


# =====================================================================================
# Decisions
# =====================================================================================

func _decide(engine: RulesEngine, s: GameState, slot: int, d: Dictionary) -> Move:
	match str(d.get("type", "")):
		RulesEngine.DECISION_ROLL_OFFER:
			# Hard tries each offered option and keeps one that helps; Easy lets them be.
			if hard():
				var options: Array[Move] = []
				for key: String in JsonUtil.as_strings(d.get("abilities", [])):
					var parts: PackedStringArray = key.split("|")
					if parts.size() == 3:
						options.append(Move.make(Move.USE_ABILITY, slot, {"hero": parts[0], "card": parts[1], "index": parts[2].to_int()}))
				for cid: String in JsonUtil.as_strings(d.get("cards", [])):
					options.append(Move.make(Move.PLAY_CARD, slot, {"card": cid}))
				var base: float = evaluate(engine, s, slot)
				var best: Move = null
				var best_v: float = base
				for m: Move in options:
					var after: GameState = _try(engine, s, m)
					if after != null and evaluate(engine, after, slot) > best_v + 0.5:
						best_v = evaluate(engine, after, slot)
						best = m
				if best != null:
					return best
			return Move.make(Move.PASS, slot)
		RulesEngine.DECISION_DAMAGE:
			return _damage_split(engine, s, slot, d)
		RulesEngine.DECISION_STAGE_ENERGY:
			return _energy_split(engine, s, slot, d)
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


## A lost battle's hit (GDD 10, 2026-11-02): at least half lands on a hero, the rest may be cards
## from the hand, one per DMG. The hero takes it while it can afford to; cards go instead when
## the hero would fall or be left low, and the least useful cards go first. Each extra card is
## weighed against the HP it saves: an HP is worth more the fewer are left, a card less when it
## cannot be played (no living hero of its colour) or the hand is full. Hard also picks the hero
## by trying the hit on each (Easy: the one with the most HP).
func _damage_split(engine: RulesEngine, s: GameState, slot: int, d: Dictionary) -> Move:
	var amount: int = JsonUtil.as_int(d.get("amount", 0))
	var min_hero: int = JsonUtil.as_int(d.get("min_hero", RulesEngine.hero_share(amount)))
	var targets: PackedStringArray = JsonUtil.as_strings(d.get("targets", []))
	var p: PlayerState = s.player(slot)
	var target: String = targets[0] if not targets.is_empty() else ""
	if targets.size() > 1:
		if hard():
			var options: Array[Move] = []
			for id: String in targets:
				options.append(Move.make(Move.DAMAGE_TO, slot, {"target": id}))
			target = _best(engine, s, slot, options).str_arg("target")
		else:
			for id: String in targets:
				var h: HeroState = s.hero(id)
				var t: HeroState = s.hero(target)
				if h != null and (t == null or h.hp > t.hp):
					target = id
	var hero: HeroState = s.hero(target)
	var spare: int = mini(amount - min_hero, p.hand.size())
	if hero == null or spare <= 0:
		return Move.make(Move.DAMAGE_TO, slot, {"target": target})
	# The hand, least useful card first.
	var ranked: Array = Array(p.hand)
	var worth: Dictionary = {}
	for cid: String in p.hand:
		worth[cid] = _card_worth(engine, s, slot, cid)
	ranked.sort_custom(func(a: String, b: String) -> bool: return JsonUtil.as_float(worth[a]) < JsonUtil.as_float(worth[b]))
	# Each plan: k cards and amount - k on the hero; the cheapest in HP worth plus card worth wins.
	var best_k: int = 0
	var best_cost: float = INF
	var cards_cost: float = 0.0
	for k: int in spare + 1:
		if k > 0:
			cards_cost += JsonUtil.as_float(worth[ranked[k - 1]])
		var cost: float = _hp_cost(hero.hp, amount - k) + cards_cost
		if cost < best_cost - 0.001:
			best_cost = cost
			best_k = k
	var picked: Array = ranked.slice(0, best_k)
	return Move.make(Move.DAMAGE_TO, slot, {"target": target, "cards": picked})


## The energy claim variant's End phase split (both levels): a stage the energy finishes first
## (the one that needs the least), then everything into one stage rather than a little into each:
## the one with the most already in it, the safer one on a tie (fewer enemies close enough to
## hit the hero off it next turn).
func _energy_split(engine: RulesEngine, s: GameState, slot: int, d: Dictionary) -> Move:
	var energy: int = JsonUtil.as_int(d.get("energy", 0))
	var goal: int = JsonUtil.as_int(d.get("goal", s.settings.stage_goal))
	var open: Array[StageState] = []
	for id: String in JsonUtil.as_strings(d.get("stages", [])):
		var st: StageState = s.stage(id)
		if st != null:
			open.append(st)
	var split: Dictionary = {}
	if open.is_empty():
		return Move.make(Move.STAGE_ENERGY, slot, {"split": split})
	var left: int = energy
	var need: Dictionary = {}
	for st: StageState in open:
		need[st.id] = maxi(goal - st.progress_of(slot), 0)
		split[st.id] = 0
	# Finish what can be finished, cheapest first.
	var finishable: Array[StageState] = open.filter(func(st: StageState) -> bool: return JsonUtil.as_int(need[st.id]) > 0)
	finishable.sort_custom(func(a: StageState, b: StageState) -> bool: return JsonUtil.as_int(need[a.id]) < JsonUtil.as_int(need[b.id]))
	for st: StageState in finishable:
		var n: int = JsonUtil.as_int(need[st.id])
		if n <= left:
			split[st.id] = n
			need[st.id] = 0
			left -= n
	# The rest into one stage.
	if left > 0:
		var best: StageState = null
		var best_v: float = -INF
		for st: StageState in open:
			if JsonUtil.as_int(need[st.id]) <= 0:
				continue
			var v: float = st.progress_of(slot) + JsonUtil.as_int(split[st.id]) - _stage_danger(engine, s, slot, st) * 2.0
			if v > best_v:
				best_v = v
				best = st
		if best == null:
			best = open[0]
		split[best.id] = JsonUtil.as_int(split[best.id]) + left
	for k: Variant in split.keys():
		if JsonUtil.as_int(split[k]) == 0:
			split.erase(k)
	return Move.make(Move.STAGE_ENERGY, slot, {"split": split})


## Enemies on the map that could reach `slot`'s heroes on `st` next turn (their range and a throw).
func _stage_danger(engine: RulesEngine, s: GameState, slot: int, st: StageState) -> int:
	var n: int = 0
	for e: HeroState in s.heroes:
		if not e.is_on_map() or s.team_of(e.owner) == s.team_of(slot):
			continue
		if Hex.distance(e.hex, st.center) <= engine.stat(s, e, "rng") + 5:
			n += 1
	return n


## What `dmg` on a hero with `hp` costs the bot: a KO is a disaster, the last HP are dear, the
## first ones cheap (one HP is about one card when the hero is healthy).
func _hp_cost(hp: int, dmg: int) -> float:
	if dmg <= 0:
		return 0.0
	if dmg >= hp:
		return 40.0
	var cost: float = 0.0
	for i: int in dmg:
		var at: int = hp - i
		cost += 3.0 if at <= 3 else (1.8 if at <= 6 else 1.0)
	return cost


## How much the bot minds losing `cid` from its hand, in HP: nothing for a card no living hero of
## its colour can play, less for a dear one or when the hand is full, more for a cheap one that
## will be played soon (Hard looks at the cost and the colour; Easy only at the colour).
func _card_worth(engine: RulesEngine, s: GameState, slot: int, cid: String) -> float:
	var c: CardDef = engine.catalog.get_card(cid)
	if c == null or not c.is_ready():
		return 0.2
	var playable: bool = c.color == "None"
	for h: HeroState in s.heroes_of(slot):
		if h.is_ko():
			continue
		var hc: CardDef = engine.catalog.get_card(h.card_id)
		if hc != null and (hc.color == c.color or c.has_bonus_for(hc.color)):
			playable = true
	if not playable:
		return 0.2
	if not hard():
		return 1.2
	var w: float = 1.4
	if c.cost >= 4:
		w -= 0.4
	elif c.cost <= 1:
		w += 0.3
	if s.player(slot).hand.size() >= 7:
		w -= 0.4
	return w


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
				# Stay claims want the hero picked (and staying); with energy claims it puts its
				# energy in anyway, so another hero gets the move.
				v += -15.0 if s.settings.energy_claims() else 25.0
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
		if s.settings.energy_claims():
			var goal: float = maxf(float(s.settings.stage_goal), 1.0)
			v += st.progress_of(h.owner) / goal * 15.0
			for o: HeroState in s.heroes_on_stage(st):
				if o == h:
					continue
				if s.same_team(o, h):
					# Two heroes on one stage put in no more energy than one.
					v -= 10.0
				else:
					# Standing on it stops the other side's energy going in.
					v += st.progress_of(o.owner) / goal * 15.0
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
			if after == null or _reckless(engine, s, after, slot):
				continue
			var gain: float = evaluate(engine, after, slot) - now
			if gain > best_gain:
				best_gain = gain
				best = m
		return best if best != null else Move.make(Move.PASS, slot)
	# Easy: the first thing in hand that helps right away.
	for m: Move in options:
		var after: GameState = _try(engine, s, m)
		if after != null and not _reckless(engine, s, after, slot) and evaluate(engine, after, slot) > now:
			return m
	return Move.make(Move.PASS, slot)


## A move that costs the bot's own heroes HP ("as an additional cost, take 3 DMG") only to pile
## Power onto a battle it already wins, or that leaves the hero on less than 5 HP
## (playtest 2026-10-30: Easy took Big Mom from 12 to 3 HP to deal 2 DMG).
func _reckless(engine: RulesEngine, s: GameState, after: GameState, slot: int) -> bool:
	var low: bool = false
	var harm: int = 0
	for h: HeroState in s.heroes_of(slot):
		var a: HeroState = after.hero(h.id)
		if a == null or a.hp >= h.hp:
			continue
		harm += h.hp - a.hp
		if a.hp < 5:
			low = true
	if harm <= 0:
		return false
	return low or _battle_gap(engine, s, slot) > 0


## The Power lead of `slot`'s side in the battle being fought (0 outside a battle).
func _battle_gap(engine: RulesEngine, s: GameState, slot: int) -> int:
	if s.phase != GameState.PHASE_BATTLE or s.battle_index < 0 or s.battle_index >= s.battles.size():
		return 0
	var gap: int = 0
	for id: String in JsonUtil.as_strings(s.battles[s.battle_index].get("heroes", [])):
		var h: HeroState = s.hero(id)
		if h == null or not h.is_on_map():
			continue
		gap += engine.stat(s, h, "pwr") * (1 if s.team_of(h.owner) == s.team_of(slot) else -1)
	return gap


# =====================================================================================
# Draft (GDD 13)
# =====================================================================================

## A draft pick with some sense, for bots. Heroes: the strongest card, with a nod to colours
## already drafted (more cards to share between them). Cards: an evolution of a drafted hero
## first, then a card for one of its own heroes by name, then General, then a trait card;
## among equals the cost closer to 3 (a curve), and equipment or an assist a little ahead.
static func draft_pick(catalog: CardCatalog, draft: DraftState, slot: int, rng_: RandomNumberGenerator) -> String:
	var options: PackedStringArray = draft.options(slot)
	if options.is_empty():
		return ""
	var best: String = ""
	var best_score: float = -INF
	for id: String in options:
		var c: CardDef = catalog.get_card(id)
		if c == null:
			continue
		var score: float = rng_.randf() * 0.5
		if draft.phase == DraftState.PHASE_HEROES:
			score += c.hp + c.dmg * 2.0 + c.pwr / 1000.0 + c.rng + c.kb
			for hid: String in draft.heroes[slot]:
				var h: CardDef = catalog.get_card(hid)
				if h != null and (h.color == c.color or c.has_bonus_for(h.color)):
					score += 3.0
		else:
			var kind: String = str(FirstTag.kind_of(catalog, c)["kind"])
			if c.type == "Evolution":
				score += 10.0
			elif kind == FirstTag.HEROES:
				score += 6.0
			elif kind == FirstTag.GENERAL:
				score += 4.0
			else:
				score += 3.0
			score -= absf(c.cost - 3.0) * 0.5
			if c.type == "Equipment" or c.type == "Assist":
				score += 0.5
		if score > best_score:
			best_score = score
			best = id
	return best
