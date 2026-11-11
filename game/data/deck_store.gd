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
	var base: String = slug(name)
	var path: String = dir.path_join(base + ".json")
	var n: int = 2
	while FileAccess.file_exists(path):
		path = dir.path_join("%s-%d.json" % [base, n])
		n += 1
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify({
		"name": name.strip_edges(),
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
	return out if not out.is_empty() else "deck"


const ACCENTS: Dictionary[String, String] = {
	"č": "c", "ć": "c", "ž": "z", "š": "s", "đ": "d", "Č": "C", "Ć": "C", "Ž": "Z", "Š": "S", "Đ": "D",
	"á": "a", "à": "a", "â": "a", "ä": "a", "ã": "a", "å": "a", "é": "e", "è": "e", "ê": "e", "ë": "e",
	"í": "i", "ì": "i", "î": "i", "ï": "i", "ó": "o", "ò": "o", "ô": "o", "ö": "o", "õ": "o",
	"ú": "u", "ù": "u", "û": "u", "ü": "u", "ñ": "n", "ç": "c", "ý": "y",
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
	return (safe if not safe.is_empty() else "deck") + ".json"


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
