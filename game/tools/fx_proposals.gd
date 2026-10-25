extends SceneTree
## Writes data/fx-proposals.json into the shared folder for the web app's Effect tab: for every
## card with text, what the game reads from it (fx lines), the sentences it does not understand,
## a proposed fx (the hand-written placeholder when there is one), and errors in an existing
## `fx` field. Run it after a Publish (GDD 14: Claude Code proposes fx, Marko confirms).
## godot_console --headless --path game -s res://tools/fx_proposals.gd [-- --data=<shared folder>]

const OUT: String = "data/fx-proposals.json"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db := CardDb.load_from(GameSettings.data_path())
	if not db.is_ok():
		push_error(db.error)
		quit(1)
		return
	# cards.json as it is: the placeholder fx only show up as proposals, so the app still asks
	# for them to be confirmed into the card data.
	var raw: CardCatalog = CardCatalog.from_json_text(FileAccess.get_file_as_string(db.data_dir().path_join("cards.json")), false)
	var placeholders: Dictionary = {}
	if FileAccess.file_exists(CardDb.PLACEHOLDER_FX):
		placeholders = JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(CardDb.PLACEHOLDER_FX)))
	var cards: Dictionary = {}
	var ready: int = 0
	var total: int = 0
	var ids: Array = raw.cards.keys()
	ids.sort()
	for id: Variant in ids:
		var c: CardDef = raw.cards[str(id)]
		if c.type == "Core" and c.text.is_empty():
			continue
		var parsed: Dictionary = FxTextParser.parse(c)
		var read: String = str(parsed.get("fx", ""))
		var unparsed: PackedStringArray = JsonUtil.as_strings(parsed.get("unparsed", []))
		if c.text.strip_edges().is_empty() and not c.fx_hand_written:
			continue
		total += 1
		# The parser writes the card's own hero as SELF; show the name again.
		var who: String = c.hero if c.type == "Evolution" and not c.hero.is_empty() else c.name
		var sentences: Array = []
		for u: String in unparsed:
			sentences.append(u.replace("SELF", who))
		var entry: Dictionary = {"read": read, "unparsed": sentences}
		var proposal: String = str(placeholders.get(str(id), "")) if placeholders.has(str(id)) else (read if unparsed.is_empty() else "")
		entry["proposal"] = proposal
		if c.fx_hand_written:
			var errors := PackedStringArray()
			for u: String in c.unparsed:
				errors.append(u.trim_prefix("fx: "))
			entry["fxErrors"] = Array(errors)
		# Ready for the game: a valid hand-written fx, or text the parser fully reads.
		var ok: bool = c.is_ready() if c.fx_hand_written else unparsed.is_empty()
		entry["ready"] = ok
		if ok:
			ready += 1
		cards[str(id)] = entry
	var doc: Dictionary = {
		"version": db.version,
		"generated": Time.get_datetime_string_from_system(true) + "Z",
		"game": str(ProjectSettings.get_setting("application/config/version", "")),
		"cards": cards,
	}
	var path: String = db.root_dir.path_join(OUT)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		quit(1)
		return
	f.store_string(JSON.stringify(doc, "  ", false) + "\n")
	f.close()
	print("%s: %d cards with text, %d ready from text or fx, %d need an fx" % [path, total, ready, total - ready])
	quit()
