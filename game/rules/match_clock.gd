class_name MatchClock
extends RefCounted
## The move timer (GDD 8, 2026-10-26): pure helpers for whoever runs the clock (the match scene
## locally, the host online). Nothing here keeps time. `waiting_on` says whose move the game
## waits for, `wait_key` what it waits for (the clock of a player restarts when its key
## changes), `timeout_move` the safe move made for a player whose time ran out: a card round
## passes, a Start pick confirms the marked hero (else a random one, staying when it may),
## a mulligan keeps, a roll offer declines, a missed aim is a missed roll, a placement goes on
## a random legal hex, and a decision takes the gentlest option.


## Slots whose move the game waits for right now (surrendered players never, KO players
## still answer decisions).
static func waiting_on(engine: RulesEngine, s: GameState) -> PackedInt32Array:
	var out := PackedInt32Array()
	if s.is_over():
		return out
	for p: PlayerState in s.players:
		if not p.surrendered and not wait_key(engine, s, p.slot).is_empty():
			out.append(p.slot)
	return out


## What the game waits for from `slot`, "" when nothing. The text changes whenever the wait
## does, so a clock keyed on it restarts for every new move asked of the player.
static func wait_key(engine: RulesEngine, s: GameState, slot: int) -> String:
	var p: PlayerState = s.player(slot)
	if p == null or p.surrendered or s.is_over():
		return ""
	if not s.pending.is_empty():
		var d: Dictionary = s.pending[0]
		if str(d.get("type", "")) == RulesEngine.DECISION_ROLL_OFFER:
			return "offer|%d|%d" % [s.turn, s.log.size()] if engine.roll_offer_index(s, slot) >= 0 else ""
		if JsonUtil.as_int(d.get("player", -1), -1) != slot:
			return ""
		return "decision|%s|%d|%d" % [str(d.get("type", "")), s.log.size(), s.pending.size()]
	match s.phase:
		GameState.PHASE_SETUP_STAGES, GameState.PHASE_SETUP_CORES:
			return "setup|%s|%d" % [s.phase, s.log.size()] if s.setup_turn == slot else ""
		GameState.PHASE_MULLIGAN:
			return "mulligan" if not p.mulligan_done else ""
		GameState.PHASE_START:
			return "start|%d" % s.turn if not s.active.has(slot) else ""
		GameState.PHASE_ROLL:
			if s.awaiting_roll or not s.choices.get(slot, false) or s.aims.has(slot) or s.active_hero(slot) == null:
				return ""
			return "aim|%d|%d" % [s.turn, s.log.size()]
		GameState.PHASE_PREROLL, GameState.PHASE_POSTROLL, GameState.PHASE_BATTLE:
			if s.round_over or s.to_act != slot:
				return ""
			return "card|%d|%s|%d|%d|%d" % [s.turn, s.phase, s.battle_index, s.log.size(), s.passed.size()]
	return ""


## The safe move for `slot` when its time ran out, or null when nothing is waited for. `hint`
## may carry the Start pick the player marked but did not confirm ({"hero", "roll"}).
static func timeout_move(engine: RulesEngine, s: GameState, slot: int, rng: RandomNumberGenerator,
		hint: Dictionary = {}) -> Move:
	var key: String = wait_key(engine, s, slot)
	if key.is_empty():
		return null
	if key.begins_with("offer|") or key.begins_with("card|"):
		return Move.make(Move.PASS, slot)
	if key.begins_with("mulligan"):
		return Move.make(Move.MULLIGAN, slot, {"keep": true})
	if key.begins_with("start|"):
		return _select(engine, s, slot, rng, hint)
	if key.begins_with("aim|"):
		return Move.make(Move.AIM, slot, {"skip": true})
	if key.begins_with("setup|"):
		return _place(engine, s, slot, rng)
	return _decide(engine, s, slot, rng)


## The marked hero when it still may act, else a random one that may; it rolls when it must
## (start zone) or was marked to, and stays otherwise.
static func _select(engine: RulesEngine, s: GameState, slot: int, rng: RandomNumberGenerator, hint: Dictionary) -> Move:
	var options: Array[HeroState] = engine.selectable_heroes(s, slot)
	if options.is_empty():
		return Move.make(Move.SELECT, slot, {"hero": ""})
	var marked: HeroState = s.hero(str(hint.get("hero", "")))
	var h: HeroState = marked if marked != null and options.has(marked) else options[rng.randi_range(0, options.size() - 1)]
	var roll: bool = h.zone == HeroState.ZONE_STRIP or (h == marked and JsonUtil.as_bool(hint.get("roll", false)))
	return Move.make(Move.SELECT, slot, {"hero": h.id, "roll": roll})


## The next stage or core of the player on a random hex it may take.
static func _place(engine: RulesEngine, s: GameState, slot: int, rng: RandomNumberGenerator) -> Move:
	var cells: Array[Vector2i] = s.map().cells()
	if s.phase == GameState.PHASE_SETUP_STAGES:
		for st: StageState in s.stages:
			if st.owner != slot or st.placed:
				continue
			var legal: Array[Vector2i] = cells.filter(func(a: Vector2i) -> bool: return engine.stage_placement_error(s, st, a).is_empty())
			if legal.is_empty():
				return null
			return Move.make(Move.PLACE_STAGE, slot, {"stage": st.id, "hex": Hex.to_json(legal[rng.randi_range(0, legal.size() - 1)])})
		return null
	for c: CoreState in s.cores:
		if c.owner != slot or c.place != CoreState.UNPLACED:
			continue
		var legal: Array[Vector2i] = cells.filter(func(a: Vector2i) -> bool: return engine.core_placement_error(s, c, a).is_empty())
		if legal.is_empty():
			return null
		return Move.make(Move.PLACE_CORE, slot, {"core": c.id, "hex": Hex.to_json(legal[rng.randi_range(0, legal.size() - 1)])})
	return null


## The gentlest answer to the pending decision: damage to the deck, a core back on a random
## hex it may take, the first branch or a random option of a card's choice.
static func _decide(engine: RulesEngine, s: GameState, slot: int, rng: RandomNumberGenerator) -> Move:
	var d: Dictionary = s.pending[0]
	match str(d.get("type", "")):
		RulesEngine.DECISION_DAMAGE:
			return Move.make(Move.DAMAGE_TO, slot, {"target": "deck"})
		RulesEngine.DECISION_RETURN_CORE:
			var c: CoreState = s.core(str(d.get("core", "")))
			if c == null:
				return null
			var legal: Array[Vector2i] = s.map().cells().filter(func(a: Vector2i) -> bool: return engine.core_return_error(s, c, a).is_empty())
			if legal.is_empty():
				return null
			return Move.make(Move.RETURN_CORE, slot, {"core": c.id, "hex": Hex.to_json(legal[rng.randi_range(0, legal.size() - 1)])})
		FxRuntime.DECISION_CHOOSE:
			var options: Array = JsonUtil.as_array(d.get("options", []))
			if str(d.get("kind", "")) == "option":
				return Move.make(Move.CHOOSE, slot, {"value": 0})
			if options.is_empty():
				return null
			return Move.make(Move.CHOOSE, slot, {"value": options[rng.randi_range(0, options.size() - 1)]})
	return null
