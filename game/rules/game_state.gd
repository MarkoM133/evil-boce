class_name GameState
extends RefCounted
## The whole match as data: players, heroes, tokens, whose turn it is and what the engine is
## waiting for. Serialises to JSON (save/load, replay, network, scenario tests). No rules
## live here; RulesEngine changes it.

const PHASE_SETUP_STAGES: String = "setup_stages"
const PHASE_SETUP_CORES: String = "setup_cores"
const PHASE_MULLIGAN: String = "mulligan"
const PHASE_DRAW: String = "draw"
const PHASE_SELECT: String = "select"
const PHASE_PREROLL: String = "preroll"
const PHASE_ROLL: String = "roll"
const PHASE_POSTROLL: String = "postroll"
const PHASE_BATTLE: String = "battle"
const PHASE_END: String = "end"
const PHASE_OVER: String = "over"

var settings: MatchSettings = MatchSettings.new()
var turn: int = 0
var phase: String = PHASE_SETUP_STAGES
## Slot that acts first this turn.
var initiative: int = 0
var players: Array[PlayerState] = []
var heroes: Array[HeroState] = []
var cores: Array[CoreState] = []
var stages: Array[StageState] = []
var walls: Array[WallState] = []
var rng_seed: int = 0
var rng_state: int = 0

# --- this turn ---------------------------------------------------------------
## Slot -> activated hero id ("" = none).
var active: Dictionary[int, String] = {}
## Slot -> true for Roll, false for Stay.
var choices: Dictionary[int, bool] = {}
## Slot -> {"dir": [x, z], "power": p}.
var aims: Dictionary[int, Dictionary] = {}
## True while the engine waits for the sim to deliver the RollOutcome; `rolled` once it came.
var awaiting_roll: bool = false
var rolled: bool = false
## Whose turn it is in the current card round, and who has passed in a row.
var to_act: int = 0
var passed: PackedInt32Array = PackedInt32Array()
var round_over: bool = false
## Battles of this turn, in order: {"heroes": [...], "resolved": bool, "winner_team": int, "tie": bool}.
var battles: Array[Dictionary] = []
var battle_index: int = -1
## Decisions the engine waits for: {"type": ..., "player": slot, ...}.
var pending: Array[Dictionary] = []
## Slots that may only Pass until the end of the turn.
var only_pass: PackedInt32Array = PackedInt32Array()
## Hero ids the sim has to throw next (all rollers at first, one hero after ROLL_AGAIN).
var pending_rolls: PackedStringArray = PackedStringArray()
## "hero|card|index" of once-per-turn abilities already used this turn.
var abilities_used: PackedStringArray = PackedStringArray()
## Effects waiting for a battle win: {"player", "hero", "fx", "ctx"}.
var deferred: Array[Dictionary] = []
## Things that last until the end of the turn: {"kind": "cost"|"no_claim"|"dmg_taken", ...}.
var turn_mods: Array[Dictionary] = []
## Slot placing the next stage or core during setup.
var setup_turn: int = 0

var winner: int = -1
## "ko", "stages", "deckout", "surrender", "draw".
var result: String = ""
var log: Array[Dictionary] = []

var _map: HexMap


# --- lookups ------------------------------------------------------------------

func map() -> HexMap:
	if _map == null or _map.size != settings.map_size:
		_map = HexMap.new(settings.map_size)
	return _map


func player(slot: int) -> PlayerState:
	return players[slot] if slot >= 0 and slot < players.size() else null


func hero(id: String) -> HeroState:
	for h: HeroState in heroes:
		if h.id == id:
			return h
	return null


func core(id: String) -> CoreState:
	for c: CoreState in cores:
		if c.id == id:
			return c
	return null


func stage(id: String) -> StageState:
	for s: StageState in stages:
		if s.id == id:
			return s
	return null


func heroes_of(slot: int) -> Array[HeroState]:
	var out: Array[HeroState] = []
	for h: HeroState in heroes:
		if h.owner == slot:
			out.append(h)
	return out


func team_of(slot: int) -> int:
	var p: PlayerState = player(slot)
	return p.team if p != null else slot


func same_team(a: HeroState, b: HeroState) -> bool:
	return team_of(a.owner) == team_of(b.owner)


func footprint(h: HeroState) -> Array[Vector2i]:
	return Hex.spiral(h.hex, 1 if h.big else 0)


## Hero on the map whose footprint covers `a`.
func hero_at(a: Vector2i, except: HeroState = null) -> HeroState:
	for h: HeroState in heroes:
		if h == except or not h.is_on_map():
			continue
		if Hex.distance(a, h.hex) <= (1 if h.big else 0):
			return h
	return null


func stage_at(a: Vector2i) -> StageState:
	for s: StageState in stages:
		if s.covers(a):
			return s
	return null


func wall_at(a: Vector2i) -> bool:
	for w: WallState in walls:
		if w.covers(a):
			return true
	return false


func core_at(a: Vector2i) -> CoreState:
	for c: CoreState in cores:
		if c.place == CoreState.ON_FIELD and c.hex == a:
			return c
	return null


## A hero of that size could rest centred on `a`: on the map, no wall or other hero there.
func is_free(a: Vector2i, big: bool, except: HeroState = null) -> bool:
	for cell: Vector2i in Hex.spiral(a, 1 if big else 0):
		if not map().contains(cell) or wall_at(cell) or hero_at(cell, except) != null:
			return false
	return true


## Row of the hex in the N x N offset layout: 0 is the far edge (team 1), N-1 the near (team 0).
func row_of(a: Vector2i) -> int:
	return Hex.axial_to_offset(a).y


## Half of the map in front of a team's strip; the middle row of an odd map is nobody's.
func in_half_of_team(a: Vector2i, team: int) -> bool:
	var n: int = settings.map_size
	var row: int = row_of(a)
	var mid: float = (n - 1) * 0.5
	return float(row) > mid if team == 0 else float(row) < mid


@warning_ignore("integer_division")
func in_middle_third(a: Vector2i) -> bool:
	var n: int = settings.map_size
	var row: int = row_of(a)
	return row >= n / 3 and row < n - n / 3


## Heroes whose centre is on this stage.
func heroes_on_stage(s: StageState) -> Array[HeroState]:
	var out: Array[HeroState] = []
	for h: HeroState in heroes:
		if h.is_on_map() and s.covers(h.hex):
			out.append(h)
	return out


func slots() -> PackedInt32Array:
	var out := PackedInt32Array()
	for p: PlayerState in players:
		out.append(p.slot)
	return out


func active_hero(slot: int) -> HeroState:
	return hero(str(active.get(slot, "")))


func is_over() -> bool:
	return phase == PHASE_OVER


func event(type: String, fields: Dictionary = {}) -> void:
	var e: Dictionary = {"turn": turn, "phase": phase, "type": type}
	for k: Variant in fields:
		e[k] = fields[k]
	log.append(e)


## Deterministic random integer in [0, n), advancing the stored RNG state.
func random_int(n: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	rng.state = rng_state
	var v: int = rng.randi_range(0, n - 1) if n > 1 else 0
	rng_state = rng.state
	return v


func reset_turn_data() -> void:
	active.clear()
	choices.clear()
	aims.clear()
	awaiting_roll = false
	rolled = false
	passed = PackedInt32Array()
	round_over = false
	battles.clear()
	battle_index = -1
	pending.clear()
	only_pass = PackedInt32Array()
	pending_rolls = PackedStringArray()
	abilities_used = PackedStringArray()
	deferred.clear()
	turn_mods.clear()


# --- serialisation ----------------------------------------------------------------

func to_dict() -> Dictionary:
	var ps: Dictionary = {}
	for p: PlayerState in players:
		ps["p%d" % p.slot] = p.to_dict()
	var hs: Dictionary = {}
	for h: HeroState in heroes:
		hs[h.id] = h.to_dict()
	var cs: Dictionary = {}
	for c: CoreState in cores:
		cs[c.id] = c.to_dict()
	var ss: Dictionary = {}
	for s: StageState in stages:
		ss[s.id] = s.to_dict()
	var ws: Array = []
	for w: WallState in walls:
		ws.append(w.to_dict())
	var act: Dictionary = {}
	for k: int in active:
		act[str(k)] = active[k]
	var ch: Dictionary = {}
	for k: int in choices:
		ch[str(k)] = choices[k]
	var am: Dictionary = {}
	for k: int in aims:
		am[str(k)] = aims[k]
	return {
		"settings": settings.to_dict(),
		"turn": turn,
		"phase": phase,
		"initiative": initiative,
		"players": ps,
		"heroes": hs,
		"cores": cs,
		"stages": ss,
		"walls": ws,
		"rng_seed": rng_seed,
		"rng_state": rng_state,
		"active": act,
		"choices": ch,
		"aims": am,
		"awaiting_roll": awaiting_roll,
		"rolled": rolled,
		"to_act": to_act,
		"passed": Array(passed),
		"round_over": round_over,
		"battles": battles.duplicate(true),
		"battle_index": battle_index,
		"pending": pending.duplicate(true),
		"only_pass": Array(only_pass),
		"pending_rolls": Array(pending_rolls),
		"abilities_used": Array(abilities_used),
		"deferred": deferred.duplicate(true),
		"turn_mods": turn_mods.duplicate(true),
		"setup_turn": setup_turn,
		"winner": winner,
		"result": result,
		"log": log.duplicate(true),
	}


static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.settings = MatchSettings.from_dict(JsonUtil.as_dict(d.get("settings", {})))
	s.turn = JsonUtil.as_int(d.get("turn", 0))
	s.phase = str(d.get("phase", PHASE_SETUP_STAGES))
	s.initiative = JsonUtil.as_int(d.get("initiative", 0))
	var ps: Dictionary = JsonUtil.as_dict(d.get("players", {}))
	for k: Variant in ps:
		s.players.append(PlayerState.from_dict(JsonUtil.as_dict(ps[k])))
	s.players.sort_custom(func(a: PlayerState, b: PlayerState) -> bool: return a.slot < b.slot)
	var hs: Dictionary = JsonUtil.as_dict(d.get("heroes", {}))
	for k: Variant in hs:
		s.heroes.append(HeroState.from_dict(JsonUtil.as_dict(hs[k])))
	var cs: Dictionary = JsonUtil.as_dict(d.get("cores", {}))
	for k: Variant in cs:
		s.cores.append(CoreState.from_dict(JsonUtil.as_dict(cs[k])))
	var ss: Dictionary = JsonUtil.as_dict(d.get("stages", {}))
	for k: Variant in ss:
		s.stages.append(StageState.from_dict(JsonUtil.as_dict(ss[k])))
	for w: Variant in JsonUtil.as_array(d.get("walls", [])):
		s.walls.append(WallState.from_dict(JsonUtil.as_dict(w)))
	s.rng_seed = JsonUtil.as_int(d.get("rng_seed", 0))
	s.rng_state = JsonUtil.as_int(d.get("rng_state", 0))
	var act: Dictionary = JsonUtil.as_dict(d.get("active", {}))
	for k: Variant in act:
		s.active[str(k).to_int()] = str(act[k])
	var ch: Dictionary = JsonUtil.as_dict(d.get("choices", {}))
	for k: Variant in ch:
		s.choices[str(k).to_int()] = JsonUtil.as_bool(ch[k])
	var am: Dictionary = JsonUtil.as_dict(d.get("aims", {}))
	for k: Variant in am:
		s.aims[str(k).to_int()] = JsonUtil.as_dict(am[k])
	s.awaiting_roll = JsonUtil.as_bool(d.get("awaiting_roll", false))
	s.rolled = JsonUtil.as_bool(d.get("rolled", false))
	s.to_act = JsonUtil.as_int(d.get("to_act", 0))
	for v: Variant in JsonUtil.as_array(d.get("passed", [])):
		s.passed.append(JsonUtil.as_int(v))
	s.round_over = JsonUtil.as_bool(d.get("round_over", false))
	for b: Variant in JsonUtil.as_array(d.get("battles", [])):
		s.battles.append(JsonUtil.as_dict(b))
	s.battle_index = JsonUtil.as_int(d.get("battle_index", -1), -1)
	for p: Variant in JsonUtil.as_array(d.get("pending", [])):
		s.pending.append(JsonUtil.as_dict(p))
	for v: Variant in JsonUtil.as_array(d.get("only_pass", [])):
		s.only_pass.append(JsonUtil.as_int(v))
	s.pending_rolls = JsonUtil.as_strings(d.get("pending_rolls", []))
	s.abilities_used = JsonUtil.as_strings(d.get("abilities_used", []))
	for x: Variant in JsonUtil.as_array(d.get("deferred", [])):
		s.deferred.append(JsonUtil.as_dict(x))
	for x: Variant in JsonUtil.as_array(d.get("turn_mods", [])):
		s.turn_mods.append(JsonUtil.as_dict(x))
	s.setup_turn = JsonUtil.as_int(d.get("setup_turn", 0))
	s.winner = JsonUtil.as_int(d.get("winner", -1), -1)
	s.result = str(d.get("result", ""))
	for e: Variant in JsonUtil.as_array(d.get("log", [])):
		s.log.append(JsonUtil.as_dict(e))
	return s
