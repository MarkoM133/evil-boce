class_name DeckStore
extends RefCounted
## Saved decks: the shared folder's `decks/<slug>.json` (the web app's deck builder, and since 2026-11-11 the
## decks imported from a code in the game too, so Card Studio and the other player see them; format in
## docs/deck-code.md), and the older imports kept on this computer (`user://decks/`).

const LOCAL_DIR: String = "user://decks"


## [{"name", "heroes": PackedStringArray, "cards": Dictionary, "local": bool, "path",
## "version"}], sorted by name. Shared decks first when two have the same name.
static func load_all(root: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_read_dir(root.path_join("decks"), false, out)
	_read_dir(LOCAL_DIR, true, out)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if str(a["name"]) == str(b["name"]):
			return not JsonUtil.as_bool(a["local"])
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	return out


## Saves an imported deck in the shared folder under `root`, as the web app writes one (its slug as the file name,
## rev 1); returns the path, or "" when it could not. A file of that slug already there is never overwritten:
## the name gets "-2", "-3"…
static func save_shared(root: String, name: String, heroes: PackedStringArray, cards: Dictionary, version: int) -> String:
	var dir: String = root.path_join("decks")
	if root.is_empty() or DirAccess.make_dir_recursive_absolute(dir) != OK:
		return ""
	# A second deck of the same slug gets a name of its own too, "Name (2)", whose slug is its file's: saved from
	# Card Studio under its bare name it would ask to overwrite the first (code review 2026-11-13).
	var plain: String = slug(name)
	var base: String = plain
	var title: String = name.strip_edges()
	var n: int = 2
	while FileAccess.file_exists(dir.path_join(base + ".json")):
		title = "%s (%d)" % [name.strip_edges(), n]
		base = "%s-%d" % [plain.substr(0, 59 - str(n).length()).rstrip("-"), n]
		n += 1
	var path: String = dir.path_join(base + ".json")
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify({
		"name": title,
		"heroes": Array(heroes),
		"cards": cards,
		"catalogVersion": version,
		"rev": 1,
		"updated": Time.get_datetime_string_from_system(true) + "Z",
	}, "  ") + "
")
	f.close()
	return path


## The web app's file name for a deck (js/deck.js slugify): letters without their accents, lower case, anything
## else a single "-", at most 60 characters.
static func slug(name: String) -> String:
	var plain: String = ""
	for ch: String in name:
		plain += ACCENTS.get(ch, ch)
	var out: String = ""
	var dash: bool = false
	for ch: String in plain.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
			dash = false
		elif not dash:
			out += "-"
			dash = true
	out = out.lstrip("-").rstrip("-").substr(0, 60)
	if out.is_empty():
		return "deck"
	# Names no file can have on Windows ("Con", "Aux"…), and "new", Card Studio's address of the empty deck.
	return "deck-" + out if RESERVED.has(out) else out


const RESERVED: Array[String] = ["con", "prn", "aux", "nul", "new", "com1", "com2", "com3", "com4", "com5", "com6", "com7",
	"com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"]


## Every letter of Latin-1 and Latin Extended-A that Unicode takes apart into a plain letter and its marks
## (js/deck.js drops the marks with normalize("NFD")), and đ; made by a script, not by hand.
const ACCENTS: Dictionary[String, String] = {
	"À": "A", "Á": "A", "Â": "A", "Ã": "A", "Ä": "A", "Å": "A", "Ç": "C", "È": "E", "É": "E", "Ê": "E",
	"Ë": "E", "Ì": "I", "Í": "I", "Î": "I", "Ï": "I", "Ñ": "N", "Ò": "O", "Ó": "O", "Ô": "O", "Õ": "O",
	"Ö": "O", "Ù": "U", "Ú": "U", "Û": "U", "Ü": "U", "Ý": "Y", "à": "a", "á": "a", "â": "a", "ã": "a",
	"ä": "a", "å": "a", "ç": "c", "è": "e", "é": "e", "ê": "e", "ë": "e", "ì": "i", "í": "i", "î": "i",
	"ï": "i", "ñ": "n", "ò": "o", "ó": "o", "ô": "o", "õ": "o", "ö": "o", "ù": "u", "ú": "u", "û": "u",
	"ü": "u", "ý": "y", "ÿ": "y", "Ā": "A", "ā": "a", "Ă": "A", "ă": "a", "Ą": "A", "ą": "a", "Ć": "C",
	"ć": "c", "Ĉ": "C", "ĉ": "c", "Ċ": "C", "ċ": "c", "Č": "C", "č": "c", "Ď": "D", "ď": "d", "Ē": "E",
	"ē": "e", "Ĕ": "E", "ĕ": "e", "Ė": "E", "ė": "e", "Ę": "E", "ę": "e", "Ě": "E", "ě": "e", "Ĝ": "G",
	"ĝ": "g", "Ğ": "G", "ğ": "g", "Ġ": "G", "ġ": "g", "Ģ": "G", "ģ": "g", "Ĥ": "H", "ĥ": "h", "Ĩ": "I",
	"ĩ": "i", "Ī": "I", "ī": "i", "Ĭ": "I", "ĭ": "i", "Į": "I", "į": "i", "İ": "I", "Ĵ": "J", "ĵ": "j",
	"Ķ": "K", "ķ": "k", "Ĺ": "L", "ĺ": "l", "Ļ": "L", "ļ": "l", "Ľ": "L", "ľ": "l", "Ń": "N", "ń": "n",
	"Ņ": "N", "ņ": "n", "Ň": "N", "ň": "n", "Ō": "O", "ō": "o", "Ŏ": "O", "ŏ": "o", "Ő": "O", "ő": "o",
	"Ŕ": "R", "ŕ": "r", "Ŗ": "R", "ŗ": "r", "Ř": "R", "ř": "r", "Ś": "S", "ś": "s", "Ŝ": "S", "ŝ": "s",
	"Ş": "S", "ş": "s", "Š": "S", "š": "s", "Ţ": "T", "ţ": "t", "Ť": "T", "ť": "t", "Ũ": "U", "ũ": "u",
	"Ū": "U", "ū": "u", "Ŭ": "U", "ŭ": "u", "Ů": "U", "ů": "u", "Ű": "U", "ű": "u", "Ų": "U", "ų": "u",
	"Ŵ": "W", "ŵ": "w", "Ŷ": "Y", "ŷ": "y", "Ÿ": "Y", "Ź": "Z", "ź": "z", "Ż": "Z", "ż": "z", "Ž": "Z",
	"ž": "z", "đ": "d", "Đ": "D",
}


## Saves an imported deck on this computer (when the shared folder cannot be written); returns the path, or "".
static func save_local(name: String, heroes: PackedStringArray, cards: Dictionary, version: int) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOCAL_DIR))
	var path: String = LOCAL_DIR.path_join(file_name(name))
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify({
		"name": name,
		"heroes": Array(heroes),
		"cards": cards,
		"catalogVersion": version,
		"updated": Time.get_datetime_string_from_system(true) + "Z",
	}, "  "))
	f.close()
	return path


## Removes an imported deck (shared decks are the web app's to delete).
static func delete_local(path: String) -> bool:
	if not path.begins_with(LOCAL_DIR):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


static func local_exists(name: String) -> bool:
	return FileAccess.file_exists(LOCAL_DIR.path_join(file_name(name)))


static func file_name(name: String) -> String:
	var safe: String = name.strip_edges().to_lower()
	for ch: String in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		safe = safe.replace(ch, "-")
	if safe.is_empty():
		safe = "deck"
	return ("deck-" + safe if RESERVED.has(safe) and safe != "new" else safe) + ".json"


static func _read_dir(dir: String, local: bool, out: Array[Dictionary]) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f: String in DirAccess.get_files_at(dir):
		if not f.ends_with(".json"):
			continue
		var path: String = dir.path_join(f)
		var d: Dictionary = JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
		var heroes: PackedStringArray = JsonUtil.as_strings(d.get("heroes", []))
		if heroes.is_empty():
			continue
		out.append({
			"name": str(d.get("name", f.get_basename())),
			"heroes": heroes,
			"cards": JsonUtil.as_dict(d.get("cards", {})),
			"local": local,
			"path": path,
			"version": JsonUtil.as_int(d.get("catalogVersion", 0)),
		})
