class_name DraftState
extends RefCounted
## The Draft mode (GDD 13, 2026-10-26), pure logic: a snake draft of heroes (A B B A A B, no
## hero on both sides), then four packs of ten cards drawn from the copy pool of both players'
## colours (every deck card as many times as its limit allows, evolutions only of drafted
## heroes). The players open the packs in turn and pick one card in turn; the rest of a pack
## goes to the other player. A card of the other's colour, or over its limit, or past the deck
## size cannot be taken; a player with nothing legal skips. At the end every deck is filled to
## `deck_size` with random legal cards. Whoever runs the draft (the draft screen, the host)
## calls `pick`; `timeout_pick` is the random pick when the move timer runs out.

const PHASE_HEROES: String = "heroes"
const PHASE_PACKS: String = "packs"
const PHASE_DONE: String = "done"
## Who picks a hero, relative to `first` (0 = first, 1 = the other).
const HERO_ORDER: Array[int] = [0, 1, 1, 0, 0, 1]
const PACKS: int = 4
const PACK_SIZE: int = 10

var catalog: CardCatalog
var deck_size: int = 20
## The player who picks the first hero and opens the first pack.
var first: int = 0
var phase: String = PHASE_HEROES
var hero_pool: PackedStringArray = PackedStringArray()
var heroes: Array[PackedStringArray] = [PackedStringArray(), PackedStringArray()]
var hero_picks: int = 0
## The packs still to pick from, each the ids left in it.
var packs: Array[PackedStringArray] = []
var pack_index: int = 0
var pack_turn: int = 0
## Per player: card id -> copies.
var cards: Array[Dictionary] = [{}, {}]
var rng_state: int = 0
var _rng := RandomNumberGenerator.new()


static func start(catalog_: CardCatalog, seed: int, first_: int = 0, deck_size_: int = 20) -> DraftState:
	var d := DraftState.new()
	d.catalog = catalog_
	d.deck_size = deck_size_
	d.first = clampi(first_, 0, 1)
	d._rng.seed = seed
	for h: CardDef in catalog_.of_type("Hero"):
		d.hero_pool.append(h.id)
	d._sort(d.hero_pool)
	d.rng_state = d._rng.state
	return d


## The player whose pick the draft waits for, -1 when it is done.
func waiting_on() -> int:
	match phase:
		PHASE_HEROES:
			return first if HERO_ORDER[hero_picks] == 0 else 1 - first
		PHASE_PACKS:
			return pack_turn
	return -1


func other(slot: int) -> int:
	return 1 - slot


## The ids `slot` may pick right now.
func options(slot: int) -> PackedStringArray:
	if slot != waiting_on():
		return PackedStringArray()
	if phase == PHASE_HEROES:
		return hero_pool.duplicate()
	var out := PackedStringArray()
	for id: String in current_pack():
		if not out.has(id) and _legal(slot, id):
			out.append(id)
	return out


func current_pack() -> PackedStringArray:
	if phase != PHASE_PACKS or pack_index >= packs.size():
		return PackedStringArray()
	return packs[pack_index]


## `slot` takes `id`; "" or why not.
func pick(slot: int, id: String) -> String:
	if phase == PHASE_DONE:
		return "the draft is over"
	if slot != waiting_on():
		return "not your pick"
	if phase == PHASE_HEROES:
		if not hero_pool.has(id):
			return "that hero is not on offer"
		var mine_heroes: PackedStringArray = heroes[slot]
		mine_heroes.append(id)
		heroes[slot] = mine_heroes
		hero_pool.remove_at(hero_pool.find(id))
		hero_picks += 1
		if hero_picks >= HERO_ORDER.size():
			_open_packs()
		return ""
	if not current_pack().has(id):
		return "that card is not in the pack"
	if not _legal(slot, id):
		return _why_not(slot, id)
	var pack: PackedStringArray = packs[pack_index]
	pack.remove_at(pack.find(id))
	packs[pack_index] = pack
	var mine: Dictionary = cards[slot]
	mine[id] = JsonUtil.as_int(mine.get(id, 0)) + 1
	pack_turn = other(slot)
	_advance()
	return ""


## A random legal pick for `slot` (the move timer ran out), "" when it has none.
func timeout_pick(slot: int, rng: RandomNumberGenerator) -> String:
	var o: PackedStringArray = options(slot)
	return o[rng.randi_range(0, o.size() - 1)] if not o.is_empty() else ""


## The drafted decks, {name, heroes, cards} per player, once the draft is done.
func decks() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in 2:
		out.append({"name": "Draft", "heroes": PackedStringArray(heroes[i]), "cards": JsonUtil.as_dict(cards[i]).duplicate()})
	return out



## Why `slot` may not take card `id` now ("" when it may), for the draft screen.
func why_not(slot: int, id: String) -> String:
	return _why_not(slot, id)


## Cards `slot` has drafted so far.
func card_count(slot: int) -> int:
	return _count(slot)

# --- inside ------------------------------------------------------------------------------

func _hero_colors(slot: int) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in heroes[slot]:
		var h: CardDef = catalog.get_card(id)
		if h != null and not out.has(h.color):
			out.append(h.color)
	return out


func _hero_names(slot: int) -> PackedStringArray:
	var out := PackedStringArray()
	for id: String in heroes[slot]:
		var h: CardDef = catalog.get_card(id)
		if h != null:
			out.append(h.name)
	return out


func _count(slot: int) -> int:
	var n: int = 0
	for k: Variant in cards[slot]:
		n += JsonUtil.as_int(cards[slot][k])
	return n


func _legal(slot: int, id: String) -> bool:
	return _why_not(slot, id).is_empty()


func _why_not(slot: int, id: String) -> String:
	var c: CardDef = catalog.get_card(id)
	if c == null or not DeckCode.DECK_TYPES.has(c.type):
		return "not a deck card"
	# The first tag rule (FirstTag) with the heroes and Evolution cards drafted so far.
	var hero_defs: Array[CardDef] = []
	for hid: String in heroes[slot]:
		var h: CardDef = catalog.get_card(hid)
		if h != null:
			hero_defs.append(h)
	var v: Dictionary = FirstTag.deck_verdict(catalog, c, hero_defs, FirstTag.evolutions_in(catalog, cards[slot].keys()))
	if not JsonUtil.as_bool(v["ok"]):
		return str(v["why"])
	if JsonUtil.as_int(cards[slot].get(id, 0)) >= DeckCode.LIMITS[c.type]:
		return "you have the most copies allowed"
	if _count(slot) >= deck_size:
		return "your deck is full"
	return ""


## The copy pool of both players' colours, shuffled and dealt into the packs.
func _open_packs() -> void:
	var colors := PackedStringArray()
	var names := PackedStringArray()
	for i: int in 2:
		for col: String in _hero_colors(i):
			if not colors.has(col):
				colors.append(col)
		names.append_array(_hero_names(i))
	var pool := PackedStringArray()
	for t: String in DeckCode.DECK_TYPES:
		for c: CardDef in catalog.of_type(t):
			# Only cards one of the two may take (the first tag rule, any Evolution of their heroes).
			if not _for_someone(c):
				continue
			for _n: int in DeckCode.LIMITS[t]:
				pool.append(c.id)
	_sort(pool)
	_shuffle(pool)
	packs.clear()
	for k: int in PACKS:
		var pack := PackedStringArray()
		while pack.size() < PACK_SIZE and not pool.is_empty():
			pack.append(pool[pool.size() - 1])
			pool.remove_at(pool.size() - 1)
		if not pack.is_empty():
			packs.append(pack)
	phase = PHASE_PACKS
	pack_index = 0
	pack_turn = first
	_advance()


## Whether either player could take `c` (with every Evolution card of its heroes).
func _for_someone(c: CardDef) -> bool:
	for slot: int in 2:
		var hero_defs: Array[CardDef] = []
		for hid: String in heroes[slot]:
			var h: CardDef = catalog.get_card(hid)
			if h != null:
				hero_defs.append(h)
		if JsonUtil.as_bool(FirstTag.deck_verdict(catalog, c, hero_defs, DeckCode.hero_evolutions(catalog, hero_defs))["ok"]):
			return true
	return false


## Moves on past empty packs and players with nothing legal to take; done after the last.
func _advance() -> void:
	var guard: int = 0
	while phase == PHASE_PACKS and guard < 64:
		guard += 1
		if pack_index >= packs.size():
			_finish()
			return
		if current_pack().is_empty():
			pack_index += 1
			pack_turn = first if pack_index % 2 == 0 else other(first)
			continue
		if not options(pack_turn).is_empty():
			return
		if options(other(pack_turn)).is_empty():
			# Nobody can take anything from this pack: the rest of it is thrown away.
			packs[pack_index] = PackedStringArray()
			continue
		pack_turn = other(pack_turn)


## Every deck filled to `deck_size` with random legal cards (GDD 13: skipped picks never
## leave a player short).
func _finish() -> void:
	phase = PHASE_DONE
	for slot: int in 2:
		var guard: int = 0
		while _count(slot) < deck_size and guard < 200:
			guard += 1
			var legal := PackedStringArray()
			for t: String in DeckCode.DECK_TYPES:
				for c: CardDef in catalog.of_type(t):
					if _legal(slot, c.id):
						legal.append(c.id)
			if legal.is_empty():
				break
			var id: String = legal[_rng.randi_range(0, legal.size() - 1)]
			var mine: Dictionary = cards[slot]
			mine[id] = JsonUtil.as_int(mine.get(id, 0)) + 1
	rng_state = _rng.state


func _shuffle(arr: PackedStringArray) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var t: String = arr[i]
		arr[i] = arr[j]
		arr[j] = t
	rng_state = _rng.state


## Catalog order is not promised; a sorted pool keeps the draft the same for the same seed.
static func _sort(arr: PackedStringArray) -> void:
	var a: Array = Array(arr)
	a.sort()
	arr.clear()
	for x: Variant in a:
		arr.append(str(x))


# --- serialisation -------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var ps: Array = []
	for p: PackedStringArray in packs:
		ps.append(Array(p))
	return {"deck_size": deck_size, "first": first, "phase": phase, "hero_pool": Array(hero_pool),
		"heroes": [Array(heroes[0]), Array(heroes[1])], "hero_picks": hero_picks, "packs": ps,
		"pack_index": pack_index, "pack_turn": pack_turn, "cards": [JsonUtil.as_dict(cards[0]).duplicate(), JsonUtil.as_dict(cards[1]).duplicate()],
		"rng_state": rng_state}


static func from_dict(d: Dictionary, catalog_: CardCatalog) -> DraftState:
	var s := DraftState.new()
	s.catalog = catalog_
	s.deck_size = JsonUtil.as_int(d.get("deck_size", 20), 20)
	s.first = JsonUtil.as_int(d.get("first", 0))
	s.phase = str(d.get("phase", PHASE_HEROES))
	s.hero_pool = JsonUtil.as_strings(d.get("hero_pool", []))
	var hs: Array = JsonUtil.as_array(d.get("heroes", []))
	s.heroes = [JsonUtil.as_strings(hs[0] if hs.size() > 0 else []), JsonUtil.as_strings(hs[1] if hs.size() > 1 else [])] as Array[PackedStringArray]
	s.hero_picks = JsonUtil.as_int(d.get("hero_picks", 0))
	s.packs = [] as Array[PackedStringArray]
	for p: Variant in JsonUtil.as_array(d.get("packs", [])):
		s.packs.append(JsonUtil.as_strings(p))
	s.pack_index = JsonUtil.as_int(d.get("pack_index", 0))
	s.pack_turn = JsonUtil.as_int(d.get("pack_turn", 0))
	var cs: Array = JsonUtil.as_array(d.get("cards", []))
	s.cards = [JsonUtil.as_dict(cs[0] if cs.size() > 0 else {}), JsonUtil.as_dict(cs[1] if cs.size() > 1 else {})] as Array[Dictionary]
	s.rng_state = JsonUtil.as_int(d.get("rng_state", 0))
	s._rng.state = s.rng_state
	return s
