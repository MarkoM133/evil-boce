class_name SimpleBot
extends RefCounted
## Placeholder opponent for local testing (the real Easy/Hard bots come later, GDD 12). It
## plays legal moves without much thought: enters the map, aims at the nearest enemy or an
## open stage, plays the first card the engine accepts and takes damage on a healthy hero.

var rng := RandomNumberGenerator.new()


func _init(seed_: int) -> void:
	rng.seed = seed_


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
		GameState.PHASE_MULLIGAN:
			if not s.player(slot).mulligan_done:
				return Move.make(Move.MULLIGAN, slot, {"keep": true})
		GameState.PHASE_SELECT:
			if not s.active.has(slot):
				return _select(engine, s, slot)
		GameState.PHASE_PREROLL:
			if not s.choices.has(slot) and s.active_hero(slot) != null:
				return Move.make(Move.CHOICE, slot, {"roll": _wants_roll(s, s.active_hero(slot))})
			return _card_round(engine, s, slot)
		GameState.PHASE_ROLL:
			if s.choices.get(slot, false) and not s.aims.has(slot) and s.active_hero(slot) != null:
				return _aim(engine, s, s.active_hero(slot), positions, tuning)
			if s.rolled:
				return _card_round(engine, s, slot)
		GameState.PHASE_POSTROLL, GameState.PHASE_BATTLE:
			return _card_round(engine, s, slot)
	return null


func _decide(engine: RulesEngine, s: GameState, slot: int, d: Dictionary) -> Move:
	match str(d.get("type", "")):
		RulesEngine.DECISION_DAMAGE:
			var amount: int = JsonUtil.as_int(d.get("amount", 0))
			for id: String in JsonUtil.as_strings(d.get("targets", [])):
				var h: HeroState = s.hero(id)
				if h != null and h.hp > amount + 2:
					return Move.make(Move.DAMAGE_TO, slot, {"target": id})
			return Move.make(Move.DAMAGE_TO, slot, {"target": "deck"})
		RulesEngine.DECISION_RETURN_CORE:
			var c: CoreState = s.core(str(d.get("core", "")))
			var cells: Array[Vector2i] = s.map().cells()
			var start: int = rng.randi_range(0, cells.size() - 1)
			for i: int in cells.size():
				var a: Vector2i = cells[(start + i) % cells.size()]
				if engine.core_return_error(s, c, a).is_empty():
					return Move.make(Move.RETURN_CORE, slot, {"core": c.id, "hex": Hex.to_json(a)})
		FxRuntime.DECISION_CHOOSE:
			# A card effect asks for a hero, hex, core, card or branch: take one at random.
			var options: Array = JsonUtil.as_array(d.get("options", []))
			if options.is_empty():
				return null
			var i: int = rng.randi_range(0, options.size() - 1)
			var value: Variant = i if str(d.get("kind", "")) == "option" else options[i]
			return Move.make(Move.CHOOSE, slot, {"value": value})
	return null


func _select(engine: RulesEngine, s: GameState, slot: int) -> Move:
	var options: Array[HeroState] = engine.selectable_heroes(s, slot)
	if options.is_empty():
		return Move.make(Move.SELECT, slot, {"hero": ""})
	# Get everyone onto the map first, then use whoever is nearest to an enemy.
	for h: HeroState in options:
		if h.zone == HeroState.ZONE_STRIP:
			return Move.make(Move.SELECT, slot, {"hero": h.id})
	var best: HeroState = options[0]
	var best_d: int = 999
	for h: HeroState in options:
		var e: HeroState = _nearest_enemy(s, h)
		if e != null and Hex.distance(h.hex, e.hex) < best_d:
			best_d = Hex.distance(h.hex, e.hex)
			best = h
	return Move.make(Move.SELECT, slot, {"hero": best.id})


func _wants_roll(s: GameState, h: HeroState) -> bool:
	if h.zone != HeroState.ZONE_MAP:
		return true
	var st: StageState = s.stage_at(h.hex)
	return st == null or st.is_claimed()


func _aim(engine: RulesEngine, s: GameState, h: HeroState, positions: Dictionary[String, Vector2],
		tuning: PhysicsTuning) -> Move:
	var from: Vector2 = positions.get(h.id, Vector2.ZERO)
	var target := Vector2.INF
	var stop_short: float = 0.0
	var e: HeroState = _nearest_enemy(s, h)
	if e != null:
		target = s.map().to_world(e.hex)
		stop_short = clampf(engine.stat(s, h, "rng") - 1.0, 0.0, 3.0)
	else:
		var best: float = INF
		for st: StageState in s.stages:
			if st.placed and not st.is_claimed():
				var p: Vector2 = s.map().to_world(st.center)
				if p.distance_to(from) < best:
					best = p.distance_to(from)
					target = p
	if target == Vector2.INF:
		target = Vector2(from.x, 0.0)
	var to: Vector2 = target - from
	var angle: float = rng.randf_range(-0.08, 0.08)
	to = to.rotated(angle)
	var hexes: float = maxf(to.length() / tuning.hex_spacing() - stop_short, 1.0)
	var card: CardDef = engine.catalog.get_card(h.card_id)
	var full: float = tuning.full_power_hexes(card.wt if card != null else 2)
	var power: float = clampf(hexes / full * rng.randf_range(0.9, 1.1), 0.1, 1.0)
	var dir: Vector2 = to.normalized()
	return Move.make(Move.AIM, h.owner, {"dir": [dir.x, dir.y], "power": power})


func _nearest_enemy(s: GameState, h: HeroState) -> HeroState:
	var best: HeroState = null
	for o: HeroState in s.heroes:
		if not o.is_on_map() or s.same_team(o, h):
			continue
		if best == null or (h.is_on_map() and Hex.distance(h.hex, o.hex) < Hex.distance(h.hex, best.hex)):
			best = o
	return best


## Plays the first card from the hand the engine accepts (tried on a copy), else passes.
func _card_round(engine: RulesEngine, s: GameState, slot: int) -> Move:
	if s.round_over or s.to_act != slot or s.awaiting_roll:
		return null
	if s.phase == GameState.PHASE_ROLL and not s.rolled:
		return null
	var hand: PackedStringArray = s.player(slot).hand
	for cid: String in hand:
		var m: Move = Move.make(Move.PLAY_CARD, slot, {"card": cid})
		var trial: GameState = GameState.from_dict(s.to_dict())
		if engine.apply(trial, m).is_empty():
			return m
	return Move.make(Move.PASS, slot)
