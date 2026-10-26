class_name FxRuntime
extends RefCounted
## Runs FxEffects against a GameState: triggered effects at phase start, optional abilities,
## Action cards as they are played, deferred "if you win" effects, stage reveals, and the
## passive modifiers the engine asks about (stats, damage taken, card cost).
##
## A running effect that needs a choice pushes a "choose" decision onto state.pending with
## everything it needs to carry on (the fx line, the action index, the choices so far), so a
## saved state resumes cleanly. Context `ctx`: {"player": slot, "hero": self hero id or "",
## "card": card id, "stage": stage id or ""}.

const DECISION_CHOOSE: String = "choose"

var engine: RulesEngine


func _init(engine_: RulesEngine) -> void:
	engine = engine_


# =====================================================================================
# Sources: every card in play that can carry effects
# =====================================================================================

## {"card": CardDef, "hero": HeroState or null, "player": slot, "stage": StageState or null}
func sources(s: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var order: PackedInt32Array = PackedInt32Array()
	var slot: int = s.initiative
	for _i: int in s.players.size():
		order.append(slot)
		slot = (slot + 1) % s.players.size()
	for sl: int in order:
		for h: HeroState in s.heroes_of(sl):
			if h.is_ko():
				continue
			var card: CardDef = engine.stat_card(h)
			if card != null:
				out.append({"card": card, "hero": h, "player": sl, "stage": null})
			for eid: String in h.equipment:
				var e: CardDef = engine.catalog.get_card(eid)
				if e != null:
					out.append({"card": e, "hero": h, "player": sl, "stage": null})
		for aid: String in s.player(sl).assists:
			var a: CardDef = engine.catalog.get_card(aid)
			if a != null:
				out.append({"card": a, "hero": null, "player": sl, "stage": null})
	for st: StageState in s.stages:
		if st.placed and st.revealed and not st.is_claimed():
			var c: CardDef = engine.catalog.get_card(st.card_id)
			if c != null:
				out.append({"card": c, "hero": null, "player": -1, "stage": st})
	return out


static func _ctx_of(src: Dictionary) -> Dictionary:
	var h: HeroState = src["hero"]
	var st: StageState = src["stage"]
	var card: CardDef = src["card"]
	return {"player": src["player"], "hero": h.id if h != null else "", "card": card.id, "stage": st.id if st != null else ""}


# =====================================================================================
# Triggers and abilities
# =====================================================================================

## Fires every non-optional effect whose WHEN is this phase (heroes, equipment, assists).
func fire_phase(s: GameState, phase: String) -> void:
	var when: String = phase.to_upper()
	for src: Dictionary in sources(s):
		var card: CardDef = src["card"]
		if src["stage"] != null:
			continue
		# An assist's Battle effect is about "your Hero" in a battle: it fires per battle.
		if when == "BATTLE" and src["hero"] == null:
			continue
		for e: FxEffect in card.effects_when(when):
			if e.optional:
				continue
			var ctx: Dictionary = _ctx_of(src)
			if not cond_ok(s, ctx, e):
				continue
			if e.cond == "WIN":
				s.deferred.append({"player": ctx["player"], "hero": ctx["hero"], "fx": e.line, "ctx": ctx})
				continue
			run(s, ctx, e)


## A battle starts: assists' Battle effects run with "your Hero" = that player's hero in it.
func fire_battle(s: GameState) -> void:
	if s.battle_index < 0 or s.battle_index >= s.battles.size():
		return
	var ids: PackedStringArray = JsonUtil.as_strings(s.battles[s.battle_index].get("heroes", []))
	for src: Dictionary in sources(s):
		if src["hero"] != null or src["stage"] != null:
			continue
		var slot: int = JsonUtil.as_int(src["player"])
		var mine: HeroState = null
		for id: String in ids:
			var h: HeroState = s.hero(id)
			if h != null and h.owner == slot:
				mine = h
				break
		if mine == null:
			continue
		var card: CardDef = src["card"]
		for e: FxEffect in card.effects_when("BATTLE"):
			if e.optional:
				continue
			var ctx: Dictionary = {"player": slot, "hero": mine.id, "card": card.id, "stage": ""}
			if cond_ok(s, ctx, e):
				run(s, ctx, e)


## The winner's "after winning, may deal no DMG" ability (HOLD_HIT), if it has one.
func hold_hit_effect(s: GameState, h: HeroState) -> FxEffect:
	var card: CardDef = engine.stat_card(h)
	if card == null:
		return null
	for e: FxEffect in card.effects:
		if e.when == "BATTLE" and e.cond == "WIN" and e.has_verb("HOLD_HIT"):
			return e
	return null


## Asks the winner's owner whether to hold the hit (a "choose" decision).
func offer_hold_hit(s: GameState, h: HeroState) -> void:
	var e: FxEffect = FxEffect.parse_line("BATTLE: CHOOSE ME [NOOP] [HOLD_HIT SELF]")
	run(s, {"player": h.owner, "hero": h.id, "card": h.card_id, "stage": ""}, e)


## Optional abilities `slot` could use now: [{"hero", "card", "index", "effect": FxEffect}].
func usable_abilities(s: GameState, slot: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var when: String = s.phase.to_upper()
	for src: Dictionary in sources(s):
		if src["player"] != slot or src["stage"] != null:
			continue
		var card: CardDef = src["card"]
		var h: HeroState = src["hero"]
		for i: int in card.effects.size():
			var e: FxEffect = card.effects[i]
			if not e.optional or e.when != when or e.cond == "WIN":
				continue
			var key: String = "%s|%s|%d" % [h.id if h != null else "", card.id, i]
			if e.once and s.abilities_used.has(key):
				continue
			var ctx: Dictionary = _ctx_of(src)
			if not cond_ok(s, ctx, e):
				continue
			out.append({"hero": h.id if h != null else "", "card": card.id, "index": i, "effect": e, "key": key})
	return out


## Runs one optional ability; "" or why not.
func use_ability(s: GameState, slot: int, hero_id: String, card_id: String, index: int) -> String:
	for a: Dictionary in usable_abilities(s, slot):
		if str(a["hero"]) == hero_id and str(a["card"]) == card_id and JsonUtil.as_int(a["index"]) == index:
			var e: FxEffect = a["effect"]
			if e.once:
				s.abilities_used.append(str(a["key"]))
			var ctx: Dictionary = {"player": slot, "hero": hero_id, "card": card_id, "stage": ""}
			s.event("ability", {"hero": hero_id, "card": card_id, "index": index})
			return run(s, ctx, e)
	return "that ability cannot be used now"


## A stage just turned face up.
func on_reveal(s: GameState, st: StageState, by: HeroState) -> void:
	var card: CardDef = engine.catalog.get_card(st.card_id)
	if card == null:
		return
	var ctx: Dictionary = {"player": by.owner, "hero": by.id, "card": card.id, "stage": st.id}
	for e: FxEffect in card.effects_when("REVEAL"):
		run(s, ctx, e)


## After a battle: deferred "if you win" effects of the winners run, the losers' are dropped.
func on_battle_done(s: GameState, winners: Array[HeroState], members: Array[HeroState]) -> void:
	var keep: Array[Dictionary] = []
	for d: Dictionary in s.deferred:
		var h: HeroState = s.hero(str(d.get("hero", "")))
		if h == null or not members.has(h):
			keep.append(d)
			continue
		if winners.has(h):
			var e: FxEffect = FxEffect.parse_line(str(d.get("fx", "")))
			if e != null:
				e.cond = ""
				run(s, JsonUtil.as_dict(d.get("ctx", {})), e)
	s.deferred = keep


func cond_ok(s: GameState, ctx: Dictionary, e: FxEffect) -> bool:
	match e.cond:
		"", "WIN":
			return true
		"ACTIVATED":
			var hero_id: String = str(ctx.get("hero", ""))
			return not hero_id.is_empty() and s.active.get(JsonUtil.as_int(ctx.get("player", -1)), "") == hero_id
		"OPP_EQUIPPED":
			# In a battle only the heroes in it count, else every enemy on the map.
			var team: int = s.team_of(JsonUtil.as_int(ctx.get("player", 0)))
			var in_battle := PackedStringArray()
			if s.phase == GameState.PHASE_BATTLE and s.battle_index >= 0 and s.battle_index < s.battles.size():
				in_battle = JsonUtil.as_strings(s.battles[s.battle_index].get("heroes", []))
			for h: HeroState in s.heroes:
				if s.team_of(h.owner) == team or not h.is_on_map():
					continue
				if not in_battle.is_empty() and not in_battle.has(h.id):
					continue
				for eid: String in h.equipment:
					var c: CardDef = engine.catalog.get_card(eid)
					if c != null and c.has_trait(e.cond_arg.trim_prefix("{").trim_suffix("}")):
						return true
			return false
		"COPIES":
			# This card played this many times by the player in this phase (this one included).
			var n: int = 0
			for ev: Dictionary in s.log:
				if JsonUtil.as_int(ev.get("turn", -1)) == s.turn and str(ev.get("phase", "")) == s.phase \
						and str(ev.get("type", "")) == "action" and str(ev.get("card", "")) == str(ctx.get("card", "")) \
						and JsonUtil.as_int(ev.get("player", -1)) == JsonUtil.as_int(ctx.get("player", -2)):
					n += 1
			return n >= maxi(e.cond_arg.to_int(), 1)
	return false


# =====================================================================================
# Passive modifiers
# =====================================================================================

## Stat bonus `key` that passive effects in play give hero `h`.
func passive_stat(s: GameState, h: HeroState, key: String) -> int:
	var total: int = 0
	for src: Dictionary in sources(s):
		var card: CardDef = src["card"]
		var ctx: Dictionary = _ctx_of(src)
		for e: FxEffect in card.effects_when("PASSIVE"):
			if not cond_ok(s, ctx, e):
				continue
			for a: Dictionary in e.actions:
				if str(a["verb"]) != "BUFF":
					continue
				var args: PackedStringArray = a["args"]
				if args[0].to_lower() != key:
					continue
				if not _passive_applies(s, src, str(a["target"]), h):
					continue
				total += args[1].to_int() * _per(s, src, h, args)
	return total


## Damage-taken change for `h`: passive DAMAGE_MOD plus this turn's.
func damage_mod(s: GameState, h: HeroState) -> int:
	var total: int = 0
	for src: Dictionary in sources(s):
		var card: CardDef = src["card"]
		var ctx: Dictionary = _ctx_of(src)
		for e: FxEffect in card.effects_when("PASSIVE"):
			if not cond_ok(s, ctx, e):
				continue
			for a: Dictionary in e.actions:
				if str(a["verb"]) == "DAMAGE_MOD" and _passive_applies(s, src, str(a["target"]), h):
					var args: PackedStringArray = a["args"]
					total += args[0].to_int()
	for m: Dictionary in s.turn_mods:
		if str(m.get("kind", "")) == "dmg_taken" and str(m.get("hero", "")) == h.id:
			total += JsonUtil.as_int(m.get("amount", 0))
	return total


## Cost change for player `p` playing `card` now.
func cost_mod(s: GameState, p: PlayerState, card: CardDef) -> int:
	var total: int = 0
	for src: Dictionary in sources(s):
		var src_card: CardDef = src["card"]
		var ctx: Dictionary = _ctx_of(src)
		for e: FxEffect in src_card.effects_when("PASSIVE"):
			if not cond_ok(s, ctx, e):
				continue
			for a: Dictionary in e.actions:
				if str(a["verb"]) != "COST":
					continue
				var args: PackedStringArray = a["args"]
				var mine: bool = JsonUtil.as_int(src["player"]) == p.slot
				if (str(a["target"]) == "ME") != mine:
					continue
				if _cost_filter_ok(args, card):
					total += args[0].to_int()
	for m: Dictionary in s.turn_mods:
		if str(m.get("kind", "")) != "cost" or JsonUtil.as_int(m.get("player", -1)) != p.slot:
			continue
		if _cost_filter_ok(JsonUtil.as_strings(m.get("args", [])), card):
			total += JsonUtil.as_int(m.get("amount", 0))
	return total


static func _cost_filter_ok(args: PackedStringArray, card: CardDef) -> bool:
	for i: int in range(1, args.size()):
		var f: String = args[i]
		if f == "TURN":
			continue
		if f.begins_with("{"):
			if not card.has_trait(f.trim_prefix("{").trim_suffix("}")):
				return false
		elif FxEffect.WHENS.has(f):
			var ok: bool = false
			for e: FxEffect in card.effects:
				if e.when == f:
					ok = true
			if not ok:
				return false
	return true


## Does a passive action with this target reach hero `h`?
func _passive_applies(s: GameState, src: Dictionary, target: String, h: HeroState) -> bool:
	var owner: HeroState = src["hero"]
	var st: StageState = src["stage"]
	var slot: int = JsonUtil.as_int(src["player"])
	match target:
		"SELF", "EQUIPPED":
			return owner == h
		"ALL_FRIENDLY":
			return slot >= 0 and s.team_of(h.owner) == s.team_of(slot)
		"ALL_ENEMY":
			return slot >= 0 and s.team_of(h.owner) != s.team_of(slot)
		"ALL_FRIENDLY_IN_RANGE":
			return owner != null and owner != h and s.same_team(owner, h) and _in_range_flat(s, owner, h)
		"ALL_OTHER_IN_RANGE":
			return owner != null and owner != h and _in_range_flat(s, owner, h)
		"EACH_HERO", "ALL_HEROES":
			if st != null:
				return h.is_on_map() and st.covers(h.hex)
			return true
	return false


## Range from flat stats (card + equipment), so passives never ask about passives.
func _in_range_flat(s: GameState, a: HeroState, b: HeroState) -> bool:
	if not a.is_on_map() or not b.is_on_map():
		return false
	var gap: int = Hex.distance(a.hex, b.hex) - (1 if a.big else 0) - (1 if b.big else 0)
	return gap <= engine.stat_flat(s, a, "rng")


## Multiplier from "PER <COUNTER> [arg]" at the end of a BUFF; 1 without PER.
func _per(s: GameState, src: Dictionary, h: HeroState, args: PackedStringArray) -> int:
	var i: int = args.find("PER")
	if i < 0:
		return 1
	var counter: String = args[i + 1] if i + 1 < args.size() else ""
	var arg: String = args[i + 2] if i + 2 < args.size() else ""
	match counter:
		"TRAIT_EQUIPPED":
			var n: int = 0
			for eid: String in h.equipment:
				var c: CardDef = engine.catalog.get_card(eid)
				if c != null and c.has_trait(arg.trim_prefix("{").trim_suffix("}")):
					n += 1
			return n
		"CORES":
			return h.cores.size()
		"MISSING_HP":
			var step: int = maxi(arg.to_int(), 1)
			@warning_ignore("integer_division")
			var n: int = (engine.stat_flat(s, h, "hp") - h.hp) / step
			return maxi(n, 0)
		"ENERGY":
			return s.player(h.owner).energy
		"LOW_HP_FRIENDLY":
			var limit: int = arg.to_int()
			var n: int = 0
			for o: HeroState in s.heroes_of(h.owner):
				if not o.is_ko() and o.hp <= limit:
					n += 1
			return n
		"COUNT":
			# How many things the effect's earlier action did (e.g. cores deactivated).
			return JsonUtil.as_int(src.get("count", 0))
	return 1


# =====================================================================================
# Running an effect
# =====================================================================================

## Runs the effect's actions from `start`. `chosen` maps action index -> the player's answer.
## Returns "" when done or waiting on a choice, or an error (nothing changed) for a bad target.
func run(s: GameState, ctx: Dictionary, e: FxEffect, start: int = 0, chosen: Dictionary = {}) -> String:
	for i: int in range(start, e.actions.size()):
		var a: Dictionary = e.actions[i]
		var answer: Variant = chosen.get(str(i), null)
		var need: Dictionary = _needed_choice(s, ctx, e, a, answer)
		if not need.is_empty():
			if need.has("error"):
				return str(need["error"])
			need["type"] = DECISION_CHOOSE
			need["resume"] = {"ctx": ctx, "fx": e.line, "action": i, "chosen": chosen.duplicate()}
			s.pending.append(need)
			return ""
		var err: String = _do(s, ctx, e, a, answer)
		if not err.is_empty():
			return err
		if s.is_over():
			return ""
	return ""


## Continues an effect after a `choose` answer.
func resume(s: GameState, decision: Dictionary, value: Variant) -> String:
	var r: Dictionary = JsonUtil.as_dict(decision.get("resume", {}))
	var e: FxEffect = FxEffect.parse_line(str(r.get("fx", "")))
	if e == null:
		return "cannot resume effect"
	var options: Array = JsonUtil.as_array(decision.get("options", []))
	var picked: Variant = null
	if str(decision.get("kind", "")) == "option":
		# Branches are answered by index.
		var i: int = JsonUtil.as_int(value, -1)
		if i >= 0 and i < options.size():
			picked = i
	else:
		for o: Variant in options:
			if _same_option(o, value):
				picked = o
	if picked == null:
		return "pick one of the offered options"
	var chosen: Dictionary = JsonUtil.as_dict(r.get("chosen", {})).duplicate()
	var index: int = JsonUtil.as_int(r.get("action", 0))
	chosen[str(index)] = picked
	return run(s, JsonUtil.as_dict(r.get("ctx", {})), e, index, chosen)


## Loose equality: JSON numbers arrive as floats, hexes as [q, r].
static func _same_option(a: Variant, b: Variant) -> bool:
	if a is Array and b is Array:
		var x: Array = a
		var y: Array = b
		if x.size() != y.size():
			return false
		for i: int in x.size():
			if not _same_option(x[i], y[i]):
				return false
		return true
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(JsonUtil.as_float(a), JsonUtil.as_float(b))
	return str(a) == str(b)


## The choice action `a` still needs: {} when none, {"error": ...} when it cannot be done,
## else a decision {"player", "kind", "options", "prompt"}.
func _needed_choice(s: GameState, ctx: Dictionary, e: FxEffect, a: Dictionary, answer: Variant) -> Dictionary:
	if answer != null:
		return {}
	var verb: String = str(a["verb"])
	var target: String = str(a["target"])
	var args: PackedStringArray = a["args"]
	var me: HeroState = s.hero(str(ctx.get("hero", "")))
	var player: int = JsonUtil.as_int(ctx.get("player", 0))
	match verb:
		"DAMAGE", "HEAL", "KNOCKBACK", "STATUS", "REMOVE_EVO", "BUFF", "DAMAGE_MOD":
			if target == "ENEMY" or target == "FRIENDLY":
				var options: Array = _hero_options(s, ctx, e, target)
				if options.is_empty():
					return {"error": "no hero to target"}
				if options.size() == 1:
					return {}
				return {"player": player, "kind": "hero", "options": options, "prompt": "Choose a hero for %s" % verb.to_lower()}
		"MOVE":
			if target != "SELF":
				# A group move runs as one MOVE_ID per hero (see _do).
				return {}
			if me == null:
				return {"error": "move needs a hero"}
			var hexes: Array = _move_options(s, me, args[0].to_int())
			if hexes.is_empty():
				return {"error": "nowhere to move"}
			return {"player": player, "kind": "hex", "options": hexes, "prompt": "Move %s up to %s" % [me.id, args[0]]}
		"MOVE_ID":
			var who: HeroState = s.hero(args[0])
			if who == null or not who.is_on_map():
				return {}
			# "may": the hero's own hex means it stays.
			var hexes: Array = [Hex.to_json(who.hex)]
			hexes.append_array(_move_options(s, who, args[1].to_int()))
			return {"player": who.owner, "kind": "hex", "options": hexes, "prompt": "Move %s up to %s (or click it to stay)" % [who.id, args[1]]}
		"PICK_CORE":
			var cores: Array = _core_options(s, ctx, e, false)
			if cores.is_empty():
				return {"error": "no core in reach"}
			if cores.size() == 1:
				return {}
			return {"player": player, "kind": "core", "options": cores, "prompt": "Choose a core"}
		"MOVE_CORE":
			var c: CoreState = s.core(str(ctx.get("core", "")))
			if c == null or c.place != CoreState.ON_FIELD:
				return {"error": "no core to move"}
			var hexes: Array = []
			for cell: Vector2i in Hex.spiral(c.hex, args[0].to_int()):
				if cell != c.hex and s.map().contains(cell) and engine.core_move_error(s, c, cell).is_empty():
					hexes.append(Hex.to_json(cell))
			if hexes.is_empty():
				return {"error": "the core cannot move"}
			return {"player": player, "kind": "hex", "options": hexes, "prompt": "Move the core up to %s" % args[0]}
		"FREE_PLAY":
			var options: Array = _free_play_options(s, player, args)
			if options.is_empty():
				return {"error": "no card to play for free"}
			return {"player": player, "kind": "card", "options": options, "prompt": "Play a card for free"}
		"SWAP":
			var options: Array = _hero_options(s, ctx, e, "FRIENDLY")
			if args.has("ENGAGED"):
				options = options.filter(func(id: Variant) -> bool: return _engaged(s, s.hero(str(id))))
			if options.is_empty():
				return {"error": "no friendly hero to swap with"}
			if options.size() == 1:
				return {}
			return {"player": player, "kind": "hero", "options": options, "prompt": "Swap places with"}
		"WALL":
			var hexes: Array = _wall_options(s, ctx, e)
			if hexes.is_empty():
				return {"error": "no room for a wall"}
			return {"player": player, "kind": "hex", "options": hexes, "prompt": "Place the wall"}
		"REVEAL_CORE", "ACTIVATE_CORE":
			var cores: Array = _core_options(s, ctx, e, verb == "REVEAL_CORE")
			if cores.is_empty():
				return {"error": "no core in reach"}
			if cores.size() == 1:
				return {}
			return {"player": player, "kind": "core", "options": cores, "prompt": "Choose a core"}
		"DEACTIVATE_CORE":
			if args.has("UPTO"):
				# "up to n": the player picks how many (0 is allowed).
				var most: int = mini(args[0].to_int(), me.cores.size() if me != null else 0)
				var labels: Array = ["None"]
				for k: int in range(1, most + 1):
					labels.append("%d core%s" % [k, "" if k == 1 else "s"])
				if most == 0:
					return {}
				return {"player": player, "kind": "option", "options": labels, "prompt": "Deactivate how many cores?"}
			if me == null or me.cores.is_empty():
				return {"error": "no core to deactivate"}
			if me.cores.size() == 1:
				return {}
			return {"player": player, "kind": "core", "options": Array(me.cores), "prompt": "Choose a core to deactivate"}
		"DISCARD":
			var who: int = player if target == "ME" else engine.other_slot(s, player)
			var hand: PackedStringArray = s.player(who).hand
			if hand.is_empty():
				return {}
			if hand.size() == 1:
				return {}
			return {"player": who, "kind": "card", "options": Array(hand), "prompt": "Discard a card"}
		"CHOOSE":
			var who: int = player if target == "ME" else engine.other_slot(s, player)
			var labels: Array = []
			for branch: Variant in JsonUtil.as_array(a.get("branches", [])):
				var parts := PackedStringArray()
				for b: Variant in JsonUtil.as_array(branch):
					parts.append(FxEffect.describe(JsonUtil.as_dict(b)))
				labels.append(", ".join(parts))
			return {"player": who, "kind": "option", "options": labels, "prompt": "Choose one"}
	return {}


## Performs action `a` (choices already made).
func _do(s: GameState, ctx: Dictionary, e: FxEffect, a: Dictionary, answer: Variant) -> String:
	var verb: String = str(a["verb"])
	var target: String = str(a["target"])
	var args: PackedStringArray = a["args"]
	var me: HeroState = s.hero(str(ctx.get("hero", "")))
	var player: int = JsonUtil.as_int(ctx.get("player", 0))
	match verb:
		"BUFF":
			if e.when == "PASSIVE":
				return ""
			var amount: int = args[1].to_int()
			var turn: bool = args.has("TURN")
			for h: HeroState in _targets(s, ctx, e, target, answer):
				var n: int = amount * _per(s, {"hero": me, "stage": null, "player": player, "count": ctx.get("count", 0)}, h, args)
				if e.when == "REVEAL":
					# A stage's reveal bonus lasts while the hero stays on the stage.
					_stage_buff(s, str(ctx.get("stage", "")), h, args[0], n)
					continue
				h.add_bonus(h.turn_bonus if turn else h.phase_bonus, args[0].to_lower(), n)
				engine.clamp_hp(s, h)
			s.event("fx_buff", {"card": ctx.get("card", ""), "stat": args[0], "amount": amount})
		"DAMAGE":
			var n: int = engine.stat(s, me, "dmg") if args[0] == "DMG" and me != null else args[0].to_int()
			# TRUE: "this damage cannot be blocked" (no damage modifiers).
			var unblockable: bool = args.has("TRUE")
			for h: HeroState in _targets(s, ctx, e, target, answer):
				engine.hero_damage(s, h, n, unblockable)
		"HEAL":
			for h: HeroState in _targets(s, ctx, e, target, answer):
				engine.heal(s, h, args[0].to_int())
				s.event("heal", {"hero": h.id, "amount": args[0].to_int(), "hp": h.hp})
		"MOVE":
			if target != "SELF":
				var sub := FxEffect.new()
				sub.when = e.when
				for h: HeroState in _targets(s, ctx, e, target, answer):
					if h.is_on_map():
						sub.actions.append({"verb": "MOVE_ID", "target": "", "args": PackedStringArray([h.id, args[0]])})
				if sub.actions.is_empty():
					return ""
				sub.line = sub.to_fx()
				return run(s, ctx, sub)
			if me == null:
				return "move needs a hero"
			var hex: Vector2i = JsonUtil.as_hex(answer)
			if not s.is_free(hex, me.big, me):
				return "that hex is taken"
			me.hex = hex
			s.event("moved", {"hero": me.id, "hex": Hex.to_json(hex), "by": "fx"})
		"MOVE_ID":
			var who: HeroState = s.hero(args[0])
			if who == null or answer == null:
				return ""
			var to: Vector2i = JsonUtil.as_hex(answer)
			if to != who.hex:
				who.hex = to
				s.event("moved", {"hero": who.id, "hex": Hex.to_json(to), "by": "fx"})
		"RECYCLE":
			var p: PlayerState = s.player(player if target == "ME" else engine.other_slot(s, player))
			var mode: String = args[1] if args.size() > 1 else "TOP"
			for _i: int in args[0].to_int():
				if p.graveyard.is_empty():
					break
				var cid: String = p.graveyard[p.graveyard.size() - 1]
				p.graveyard.remove_at(p.graveyard.size() - 1)
				if mode == "TOP":
					p.deck.insert(0, cid)
				else:
					p.deck.append(cid)
				s.event("recycled", {"player": p.slot, "card": cid, "to": mode.to_lower()})
			if mode == "SHUFFLE":
				engine.shuffle(s, p.deck)
		"PICK_CORE":
			ctx["core"] = str(answer) if answer != null else str(_core_options(s, ctx, e, false)[0])
		"MOVE_CORE":
			var c: CoreState = s.core(str(ctx.get("core", "")))
			if c == null:
				return "no core picked"
			c.hex = JsonUtil.as_hex(answer)
			s.event("core_moved", {"core": c.id, "hex": Hex.to_json(c.hex)})
		"TRAP_CORE":
			s.turn_mods.append({"kind": "core_trap", "core": str(ctx.get("core", "")), "player": player, "amount": args[0].to_int()})
		"HOLD_HIT":
			if me != null:
				me.statuses["hold_hit"] = 1
				s.event("hold_hit", {"hero": me.id})
		"NOOP":
			return ""
		"FREE_PLAY":
			if me == null:
				return "no hero to play the card on"
			return engine.play_free(s, player, str(answer), me)
		"SWAP":
			if me == null or not me.is_on_map():
				return "swap needs a hero on the map"
			var others: Array[HeroState] = _targets(s, ctx, e, "FRIENDLY", answer)
			if others.is_empty():
				return "no hero to swap with"
			var other: HeroState = others[0]
			var a_hex: Vector2i = me.hex
			me.hex = other.hex
			other.hex = a_hex
			if not s.is_free(me.hex, me.big, me) or not s.is_free(other.hex, other.big, other):
				other.hex = me.hex
				me.hex = a_hex
				return "they do not fit each other's place"
			s.event("swapped", {"hero": me.id, "with": other.id})
		"DUEL_TOP":
			var st: StageState = s.stage(str(ctx.get("stage", "")))
			if st == null:
				return ""
			var best: int = -1
			var best_cost: int = -1
			var tie: bool = false
			var slots: Array[int] = []
			for h: HeroState in s.heroes_on_stage(st):
				if not slots.has(h.owner):
					slots.append(h.owner)
			for sl: int in slots:
				var p: PlayerState = s.player(sl)
				if p.deck.is_empty():
					continue
				var top: CardDef = engine.catalog.get_card(p.deck[0])
				var cost: int = top.cost if top != null else 0
				s.event("top_card", {"player": sl, "card": p.deck[0], "cost": cost})
				if cost > best_cost:
					best_cost = cost
					best = sl
					tie = false
				elif cost == best_cost:
					tie = true
			if best >= 0 and not tie:
				for h: HeroState in s.heroes_on_stage(st):
					if h.owner == best:
						_stage_buff(s, st.id, h, args[0], args[1].to_int())
		"KNOCKBACK":
			if me == null:
				return "knockback needs a hero"
			var towards: bool = args.size() > 1 and args[1] == "TOWARDS"
			for h: HeroState in _targets(s, ctx, e, target, answer):
				var dir: int = Hex.direction_towards(me.hex, h.hex)
				if towards:
					dir = (dir + 3) % 6
				engine.knockback(s, h, dir, args[0].to_int())
		"STATUS":
			var turns: int = 1 if args.size() < 2 or args[1] == "TURN" else args[1].to_int()
			for h: HeroState in _targets(s, ctx, e, target, answer):
				h.statuses[args[0].to_lower()] = turns
		"DAMAGE_MOD":
			if e.when == "PASSIVE":
				return ""
			for h: HeroState in _targets(s, ctx, e, target, answer):
				s.turn_mods.append({"kind": "dmg_taken", "hero": h.id, "amount": args[0].to_int()})
		"REMOVE_EVO":
			for h: HeroState in _targets(s, ctx, e, target, answer):
				engine.remove_evolution(s, h)
		"WALL":
			var w := WallState.new()
			w.id = "wall:%d" % (s.walls.size() + 1)
			w.hexes.append(JsonUtil.as_hex(answer))
			s.walls.append(w)
			s.event("wall", {"id": w.id, "hex": Hex.to_json(w.hexes[0])})
		"REVEAL_CORE", "ACTIVATE_CORE":
			var cid: String = str(answer) if answer != null else str(_core_options(s, ctx, e, verb == "REVEAL_CORE")[0])
			var c: CoreState = s.core(cid)
			if c == null:
				return "no such core"
			if verb == "REVEAL_CORE":
				c.face_up = true
				s.event("core_revealed", {"core": c.id})
			elif me != null:
				engine.pick_core(s, me, c)
		"DEACTIVATE_CORE":
			if me == null:
				return "no hero"
			if args.has("UPTO"):
				var k: int = mini(JsonUtil.as_int(answer, 0), me.cores.size())
				for _i: int in k:
					engine.deactivate_core(s, me, me.cores[0])
				ctx["count"] = k
				return ""
			if me.cores.is_empty():
				return "no core to deactivate"
			var cid: String = str(answer) if answer != null else me.cores[0]
			engine.deactivate_core(s, me, cid)
			ctx["count"] = 1
		"CHARGE", "DISCHARGE":
			var p: PlayerState = s.player(player if target == "ME" else engine.other_slot(s, player))
			var n: int = args[0].to_int() * (1 if verb == "CHARGE" else -1)
			p.energy = clampi(p.energy + n, 0, s.settings.max_energy)
			s.event("energy", {"player": p.slot, "amount": n, "energy": p.energy})
		"DRAW":
			var p: PlayerState = s.player(player if target == "ME" else engine.other_slot(s, player))
			engine.draw(s, p, args[0].to_int())
		"DISCARD":
			var p: PlayerState = s.player(player if target == "ME" else engine.other_slot(s, player))
			if p.hand.is_empty():
				return ""
			var cid: String = str(answer) if answer != null else p.hand[0]
			if not p.hand.has(cid):
				return "card not in hand"
			p.hand.remove_at(p.hand.find(cid))
			p.graveyard.append(cid)
			s.event("discard", {"player": p.slot, "card": cid})
		"COST":
			if e.when == "PASSIVE":
				return ""
			var who: int = player if target == "ME" else engine.other_slot(s, player)
			s.turn_mods.append({"kind": "cost", "player": who, "amount": args[0].to_int(), "args": Array(args)})
		"NO_CLAIM":
			var who: int = player if target == "ME" else engine.other_slot(s, player)
			s.turn_mods.append({"kind": "no_claim", "player": who})
		"ROLL_AGAIN":
			return engine.roll_again(s, player)
		"REVERSE_ROLL":
			return engine.reverse_roll(s, player)
		"COST_DAMAGE":
			if me == null:
				return "no hero to pay"
			engine.hero_damage(s, me, args[0].to_int())
		"CHOOSE":
			var branches: Array = JsonUtil.as_array(a.get("branches", []))
			var index: int = JsonUtil.as_int(answer, 0)
			if index < 0 or index >= branches.size():
				return "no such option"
			var sub := FxEffect.new()
			sub.when = e.when
			sub.range = e.range
			for b: Variant in JsonUtil.as_array(branches[index]):
				sub.actions.append(JsonUtil.as_dict(b))
			sub.line = sub.to_fx()
			return run(s, ctx, sub)
		_:
			return "unknown verb %s" % verb
	return ""


func _stage_buff(s: GameState, stage_id: String, h: HeroState, stat: String, amount: int) -> void:
	s.stage_buffs.append({"stage": stage_id, "hero": h.id, "stat": stat.to_lower(), "amount": amount})
	s.event("stage_buff", {"stage": stage_id, "hero": h.id, "stat": stat.to_lower(), "amount": amount})


## Cards in hand the player may play for free: cost up to args[0], with the trait if given.
func _free_play_options(s: GameState, slot: int, args: PackedStringArray) -> Array:
	var out: Array = []
	var max_cost: int = args[0].to_int()
	# Filters after the cost: a {Trait} and/or a card type (Zoro: "{Sword} Equipment").
	var wanted_trait: String = ""
	var wanted_type: String = ""
	for i: int in range(1, args.size()):
		if args[i].begins_with("{"):
			wanted_trait = args[i].trim_prefix("{").trim_suffix("}")
		else:
			wanted_type = args[i].capitalize()
	for cid: String in s.player(slot).hand:
		var c: CardDef = engine.catalog.get_card(cid)
		if c == null or not c.is_ready() or c.cost > max_cost:
			continue
		if not wanted_trait.is_empty() and not c.has_trait(wanted_trait):
			continue
		if not wanted_type.is_empty() and c.type != wanted_type:
			continue
		if not out.has(cid):
			out.append(cid)
	return out


## The hero is in a fight: an enemy reaches it or it reaches an enemy.
func _engaged(s: GameState, h: HeroState) -> bool:
	if h == null or not h.is_on_map():
		return false
	for o: HeroState in s.heroes:
		if not s.same_team(o, h) and (engine.in_range(s, o, h) or engine.in_range(s, h, o)):
			return true
	return false


static func _branch_fx(branch: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	for b: Variant in JsonUtil.as_array(branch):
		out.append(FxEffect.action_to_fx(JsonUtil.as_dict(b)))
	return out


# --- targets ----------------------------------------------------------------------------

func _targets(s: GameState, ctx: Dictionary, e: FxEffect, target: String, answer: Variant) -> Array[HeroState]:
	var out: Array[HeroState] = []
	var me: HeroState = s.hero(str(ctx.get("hero", "")))
	var player: int = JsonUtil.as_int(ctx.get("player", 0))
	var st: StageState = s.stage(str(ctx.get("stage", "")))
	match target:
		"SELF", "EQUIPPED":
			if me != null:
				out.append(me)
		"ENEMY", "FRIENDLY":
			var options: Array = _hero_options(s, ctx, e, target)
			var id: String = str(answer) if answer != null else (str(options[0]) if not options.is_empty() else "")
			var h: HeroState = s.hero(id)
			if h != null:
				out.append(h)
		"ALL_FRIENDLY":
			for h: HeroState in s.heroes:
				if not h.is_ko() and s.team_of(h.owner) == s.team_of(player):
					out.append(h)
		"ALL_ENEMY":
			for h: HeroState in s.heroes:
				if not h.is_ko() and s.team_of(h.owner) != s.team_of(player):
					out.append(h)
		"ALL_OTHER_IN_RANGE":
			if me != null:
				for h: HeroState in s.heroes:
					if h != me and engine.in_range(s, me, h):
						out.append(h)
		"ALL_FRIENDLY_IN_RANGE":
			if me != null:
				for h: HeroState in s.heroes:
					if h != me and s.same_team(h, me) and engine.in_range(s, me, h):
						out.append(h)
		"EACH_HERO", "ALL_HEROES":
			for h: HeroState in s.heroes:
				if h.is_on_map() and (st == null or st.covers(h.hex)):
					out.append(h)
		"MOST_HP", "MOST_PWR":
			var best: HeroState = null
			var best_v: int = -1
			var tie: bool = false
			for h: HeroState in s.heroes:
				if not h.is_on_map() or (st != null and not st.covers(h.hex)):
					continue
				var v: int = h.hp if target == "MOST_HP" else engine.stat(s, h, "pwr")
				if v > best_v:
					best_v = v
					best = h
					tie = false
				elif v == best_v:
					tie = true
			if best != null and not tie:
				out.append(best)
	return out


## Ids of heroes a chooser may pick for ENEMY / FRIENDLY (in range when the effect says so).
func _hero_options(s: GameState, ctx: Dictionary, e: FxEffect, target: String) -> Array:
	var out: Array = []
	var me: HeroState = s.hero(str(ctx.get("hero", "")))
	var player: int = JsonUtil.as_int(ctx.get("player", 0))
	for h: HeroState in s.heroes:
		if not h.is_on_map():
			continue
		var enemy: bool = s.team_of(h.owner) != s.team_of(player)
		if (target == "ENEMY") != enemy:
			continue
		if target == "FRIENDLY" and h == me:
			continue
		if e.range and (me == null or not engine.in_range(s, me, h)):
			continue
		out.append(h.id)
	return out


## Hexes a hero may move to: up to `steps` away over free hexes (walls and heroes block).
func _move_options(s: GameState, h: HeroState, steps: int) -> Array:
	var out: Array = []
	if not h.is_on_map():
		return out
	var seen: Dictionary[Vector2i, bool] = {h.hex: true}
	var frontier: Array[Vector2i] = [h.hex]
	for _step: int in steps:
		var next: Array[Vector2i] = []
		for a: Vector2i in frontier:
			for n: Vector2i in Hex.neighbors(a):
				if seen.has(n) or not s.is_free(n, h.big, h):
					continue
				seen[n] = true
				next.append(n)
				out.append(Hex.to_json(n))
		frontier = next
	return out


func _wall_options(s: GameState, ctx: Dictionary, e: FxEffect) -> Array:
	var out: Array = []
	var me: HeroState = s.hero(str(ctx.get("hero", "")))
	for a: Vector2i in s.map().cells():
		if s.stage_at(a) != null or s.wall_at(a) or s.hero_at(a) != null or s.core_at(a) != null:
			continue
		if e.range and (me == null or not engine.reaches_hex(s, me, a)):
			continue
		out.append(Hex.to_json(a))
	return out


func _core_options(s: GameState, ctx: Dictionary, e: FxEffect, face_down_only: bool) -> Array:
	var out: Array = []
	var me: HeroState = s.hero(str(ctx.get("hero", "")))
	for c: CoreState in s.cores:
		if c.place != CoreState.ON_FIELD or (face_down_only and c.face_up):
			continue
		if e.range and (me == null or not engine.reaches_hex(s, me, c.hex)):
			continue
		out.append(c.id)
	return out
