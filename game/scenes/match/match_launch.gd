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
	var settings := MatchSettings.new()
	settings.map_size = GameSettings.map_size()
	settings.manual_setup = false
	return {
		"settings": settings,
		"decks": [
			engine_deck(catalog, DeckCode.random_deck(catalog, rng), "Player 1", rng),
			engine_deck(catalog, DeckCode.random_deck(catalog, rng), "Bot", rng),
		],
		"bots": PackedInt32Array([1]),
		"seed": rng.randi(),
	}


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
