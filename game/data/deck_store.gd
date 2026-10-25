class_name DeckStore
extends RefCounted
## Saved decks from the shared folder (`decks/<name>.json`, written by the web app's deck
## builder; format in docs/deck-code.md).


## [{"name": String, "heroes": PackedStringArray, "cards": Dictionary}], sorted by name.
static func load_all(root: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir: String = root.path_join("decks")
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f: String in DirAccess.get_files_at(dir):
		if not f.ends_with(".json"):
			continue
		var d: Dictionary = JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f))))
		var heroes: PackedStringArray = JsonUtil.as_strings(d.get("heroes", []))
		if heroes.is_empty():
			continue
		out.append({
			"name": str(d.get("name", f.get_basename())),
			"heroes": heroes,
			"cards": JsonUtil.as_dict(d.get("cards", {})),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	return out
