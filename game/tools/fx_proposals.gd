extends SceneTree
## Writes data/fx-proposals.json into the shared folder for the web app's Effect tab: for every
## card with text, what the game reads from it (fx lines), the sentences it does not understand,
## a proposed fx (the hand-written placeholder when there is one), and errors in an existing
## `fx` field. Run it after a Publish (GDD 14: Claude Code proposes fx, Marko confirms). Card Studio drafts are read
## too (2026-11-23), over a published card with the same id, so a set's fx can be confirmed before it is published.
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
	var doc_in: Dictionary = JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(db.data_dir().path_join("cards.json"))))
	var list: Array = JsonUtil.as_array(doc_in.get("cards", []))
	var drafted: Dictionary = {}
	var drafts_path: String = db.data_dir().path_join("editor/drafts.json")
	if FileAccess.file_exists(drafts_path):
		var drafts: Dictionary = JsonUtil.as_dict(JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(drafts_path))).get("cards", {}))
		var by_id: Dictionary = {}
		for i: int in list.size():
			by_id[str(JsonUtil.as_dict(list[i]).get("id", ""))] = i
		for key: Variant in drafts:
			var rec: Dictionary = JsonUtil.as_dict(drafts[key])
			var id: String = str(rec.get("id", key))
			# A draft holds only what changed: over the published card when there is one.
			var merged: Dictionary = JsonUtil.as_dict(list[by_id[id]]).duplicate() if by_id.has(id) else {}
			for k: Variant in rec:
				merged[k] = rec[k]
			merged["id"] = id
			if merged.has("text"):
				merged["text"] = _words(str(merged["text"]))
			if str(merged.get("type", "")).is_empty() or JsonUtil.as_bool(merged.get("deleted", false)):
				continue
			drafted[id] = true
			if by_id.has(id):
				list[by_id[id]] = merged
			else:
				list.append(merged)
	doc_in["cards"] = list
	var raw: CardCatalog = CardCatalog.from_doc(doc_in, false)
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
		if drafted.has(str(id)):
			# Read from the draft: the text the Card Studio shows now, not the published one. The text goes along, so
			# the app sees when the draft changed after this was read.
			entry["draft"] = true
			entry["text"] = c.text
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
	print("%s: %d cards with text (%d from drafts), %d ready from text or fx, %d need an fx" % [path, total, drafted.size(), ready, total - ready])
	quit()


## A draft's text as Publish writes it (js/card-text.js toWords): [EN] is "Energy", bold marks go.
static func _words(text: String) -> String:
	var words: Dictionary = {"HP": "HP", "DMG": "DMG", "PWR": "Power", "RNG": "Range", "KB": "Knockback", "EN": "Energy"}
	var out: String = text
	var start: RegEx = RegEx.create_from_string("(?im)^\\[RNG\\]\\s*")
	out = start.sub(out, "[Range] ", true)
	var tok: RegEx = RegEx.create_from_string("\\[(HP|DMG|PWR|RNG|KB|EN)\\]")
	var m: RegExMatch = tok.search(out)
	while m != null:
		var before: String = out.substr(m.get_start() - 1, 1) if m.get_start() > 0 else ""
		var word: String = (" " if not before.is_empty() and before.strip_edges() != "" else "") + str(words[m.get_string(1)])
		out = out.substr(0, m.get_start()) + word + out.substr(m.get_end())
		m = tok.search(out, m.get_start() + word.length())
	return out.replace("**", "")
