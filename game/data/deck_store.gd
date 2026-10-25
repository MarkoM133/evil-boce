class_name DeckStore
extends RefCounted
## Saved decks: the shared folder's `decks/<name>.json` (written by the web app's deck builder;
## format in docs/deck-code.md) and decks imported from a code in the game, which stay on this
## computer (`user://decks/`, GDD 7: "spremljeni uvezeni kodovi").

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


## Saves an imported deck on this computer; returns the path, or "" when it could not.
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
