class_name ReplayStore
extends RefCounted
## Match records on disk. Replays and saves are local (user://, GDD 2: each player keeps and
## deletes their own); the stats summary goes to the shared folder's stats/ for the Balance tab.

const REPLAY_DIR: String = "user://replays"
const SAVE_DIR: String = "user://saves"
## The match in progress, written after every move so a crash or quit can be resumed.
const CURRENT_SAVE: String = "user://saves/current.json"


static func replay_path(record: MatchRecord) -> String:
	var stamp: String = record.created.replace(":", "-").replace("T", "_").trim_suffix("Z")
	var who: String = record.title().to_lower().replace(" ", "-")
	who = _safe(who)
	return REPLAY_DIR.path_join("%s_%s.json" % [stamp, who])


## Writes a finished (or any) record as a replay; returns the path.
static func save_replay(record: MatchRecord) -> String:
	var path: String = replay_path(record)
	_write_json(path, record.to_dict())
	return path


## Headers of every replay, newest first: {"path", "created", "title", "heroes", "turns",
## "frames", "finished", "winner", "result", "cards_version", "game_version"}.
static func list_replays() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(REPLAY_DIR):
		return out
	for f: String in DirAccess.get_files_at(REPLAY_DIR):
		if not f.ends_with(".json"):
			continue
		var path: String = REPLAY_DIR.path_join(f)
		var d: Dictionary = _read_json(path)
		if d.is_empty():
			continue
		var h: Dictionary = MatchRecord.header_from_dict(d)
		h["path"] = path
		out.append(h)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["created"]) > str(b["created"]))
	return out


static func load_record(path: String) -> MatchRecord:
	var d: Dictionary = _read_json(path)
	return MatchRecord.from_dict(d) if not d.is_empty() else null


static func delete(path: String) -> bool:
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


# --- the match in progress ---------------------------------------------------------------

static func save_current(record: MatchRecord) -> void:
	_write_json(CURRENT_SAVE, record.to_dict())


static func has_current() -> bool:
	return FileAccess.file_exists(CURRENT_SAVE)


static func load_current() -> MatchRecord:
	return load_record(CURRENT_SAVE) if has_current() else null


static func clear_current() -> void:
	if has_current():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CURRENT_SAVE))


# --- stats ------------------------------------------------------------------------------

## Appends the match summary to <shared root>/stats/ (one file per match); returns the path.
static func write_stats(record: MatchRecord, shared_root: String) -> String:
	var dir: String = shared_root.path_join("stats")
	var stamp: String = record.created.replace(":", "-").replace("T", "_").trim_suffix("Z")
	var path: String = dir.path_join("%s_%s.json" % [stamp, _safe(record.title().to_lower().replace(" ", "-"))])
	_write_json(path, record.summary())
	return path


# --- files ------------------------------------------------------------------------------

static func _write_json(path: String, d: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		return
	f.store_string(JSON.stringify(d))
	f.close()


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))


static func _safe(s: String) -> String:
	var out: String = ""
	for ch: String in s:
		out += ch if ch.is_valid_identifier() or ch == "-" else "_"
	return out.substr(0, 60)


# --- the last match's picture (main menu, Play tile on hover) -----------------------------------

const LAST_SHOT: String = "user://last_match.jpg"
const LAST_INFO: String = "user://last_match.json"


## Keeps a picture of the table from the last match, with a line about it.
static func save_last_shot(img: Image, caption: String) -> void:
	if img == null or img.is_empty():
		return
	if img.get_width() > 960:
		img.resize(960, roundi(960.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.save_jpg(ProjectSettings.globalize_path(LAST_SHOT), 0.85)
	_write_json(LAST_INFO, {"caption": caption, "at": Time.get_datetime_string_from_system(true) + "Z"})


static func last_shot() -> Texture2D:
	if not FileAccess.file_exists(LAST_SHOT):
		return null
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(LAST_SHOT))
	return ImageTexture.create_from_image(img) if img != null and not img.is_empty() else null


static func last_caption() -> String:
	return str(_read_json(LAST_INFO).get("caption", ""))
