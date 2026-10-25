class_name MatchLaunch
extends RefCounted
## Hands the match setup to the match scene: {"settings": MatchSettings, "decks": [engine deck
## dicts], "bots": PackedInt32Array, "seed": int}. Engine decks carry "stages" and "cores" too.

const STAGES_PER_PLAYER: int = 3
const CORES_PER_PLAYER: int = 6

static var config: Dictionary = {}


## The pending config (cleared), or a default one: two random decks, slot 1 played by the bot.
static func take(catalog: CardCatalog) -> Dictionary:
	if not config.is_empty():
		var c: Dictionary = config
		config = {}
		return c
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var settings: MatchSettings = MatchSettings.standard()
	settings.map_size = GameSettings.map_size()
	return {
		"settings": settings,
		"decks": [
			engine_deck(catalog, DeckCode.random_deck(catalog, rng), "Player 1", rng),
			engine_deck(catalog, DeckCode.random_deck(catalog, rng), "Bot", rng),
		],
		"bots": PackedInt32Array([1]),
		"seed": rng.randi(),
	}


## A match from a record: `replay` watches it, otherwise it carries on from frame `frame`
## (-1 = the last one) with the same seats (bots stay bots).
static func from_record(record: MatchRecord, frame: int = -1, replay: bool = false) -> Dictionary:
	var bots := PackedInt32Array()
	for p: Dictionary in record.players:
		if JsonUtil.as_bool(p.get("bot", false)):
			bots.append(JsonUtil.as_int(p.get("slot", 0)))
	var c: Dictionary = {
		"settings": MatchSettings.from_dict(record.settings),
		"decks": record.decks,
		"bots": bots,
		"seed": record.seed,
		"frame": frame,
	}
	c["replay" if replay else "resume"] = record
	return c


## A saved or random deck plus 3 random stages and the 6 cores, as RulesEngine.start_match wants.
static func engine_deck(catalog: CardCatalog, deck: Dictionary, player_name: String,
		rng: RandomNumberGenerator) -> Dictionary:
	var stages: Array[CardDef] = catalog.of_type("Stage")
	var picked := PackedStringArray()
	while picked.size() < STAGES_PER_PLAYER and not stages.is_empty():
		var st: CardDef = stages.pop_at(rng.randi_range(0, stages.size() - 1))
		picked.append(st.id)
	var cores := PackedStringArray()
	for c: CardDef in catalog.of_type("Core"):
		if cores.size() < CORES_PER_PLAYER:
			cores.append(c.id)
	return {
		"name": player_name,
		"deck_name": str(deck.get("name", "")),
		"heroes": JsonUtil.as_strings(deck.get("heroes", [])),
		"cards": JsonUtil.as_dict(deck.get("cards", {})),
		"stages": picked,
		"cores": cores,
	}
