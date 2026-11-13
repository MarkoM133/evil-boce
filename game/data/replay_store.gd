class_name ReplayStore
extends RefCounted
## Match records on disk. Replays and saves are local (user://, GDD 2: each player keeps and
## deletes their own); the stats summary goes to the shared folder's stats/ for the Balance tab.

const REPLAY_DIR: String = "user://replays"
const SAVE_DIR: String = "user://saves"
## The match in progress, written after every move so a crash or quit can be resumed.
const CURRENT_SAVE: String = "user://saves/current.json"
## The online match this computer hosts, kept apart from the local one (Online › Continue).
const CURRENT_ONLINE: String = "user://saves/current_online.json"
## Headers of the replays already read, by file name: {"at": its modified time, "size": its bytes, "header"}.
## A replay is some 2 MB of JSON and its header a few fields of it: without this every list parsed every replay
## again (code review 2026-11-13: the main menu and Online each stood still for over a second with 13 replays).
const HEADERS: String = "user://replay_headers.json"

static var _headers: Dictionary = {}
static var _headers_read: bool = false
static var _headers_dirty: bool = false


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
		var h: Dictionary = header_of(path)
		if h.is_empty():
			continue
		h["path"] = path
		out.append(h)
	_keep_headers(DirAccess.get_files_at(REPLAY_DIR))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["created"]) > str(b["created"]))
	return out


## A replay's header (MatchRecord.header_from_dict), {} when the file is no record: from HEADERS while the file
## is the one it was read from (same time and size), else read from the file and remembered.
static func header_of(path: String) -> Dictionary:
	if not _headers_read:
		_headers_read = true
		_headers = _read_json(HEADERS)
	var name: String = path.get_file()
	var at: int = FileAccess.get_modified_time(path)
	var size: int = _size(path)
	var known: Dictionary = JsonUtil.as_dict(_headers.get(name, {}))
	if not known.is_empty() and JsonUtil.as_int(known.get("at", -1), -1) == at and JsonUtil.as_int(known.get("size", -1), -1) == size:
		var h: Dictionary = JsonUtil.as_dict(known.get("header", {})).duplicate(true)
		# Back from JSON: the numbers and the names as the header has them.
		for key: String in ["turns", "frames", "cards_version"]:
			h[key] = JsonUtil.as_int(h.get(key, 0))
		h["winner"] = JsonUtil.as_int(h.get("winner", -1), -1)
		h["names"] = JsonUtil.as_strings(h.get("names", []))
		return h
	var d: Dictionary = _read_json(path)
	if d.is_empty():
		return {}
	var fresh: Dictionary = MatchRecord.header_from_dict(d)
	_headers[name] = {"at": at, "size": size, "header": fresh.duplicate(true)}
	_headers_dirty = true
	return fresh


## Writes HEADERS when a header was read anew; `files` (the replay folder as it is) drops those of replays gone.
static func _keep_headers(files: PackedStringArray = PackedStringArray()) -> void:
	if not files.is_empty():
		for name: Variant in _headers.keys():
			if not files.has(str(name)):
				_headers.erase(name)
				_headers_dirty = true
	if _headers_dirty:
		_headers_dirty = false
		_write_json(HEADERS, _headers)


static func _size(path: String) -> int:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else -1


static func load_record(path: String) -> MatchRecord:
	var d: Dictionary = _read_json(path)
	return MatchRecord.from_dict(d) if not d.is_empty() else null


static func delete(path: String) -> bool:
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


## Whether a replay's header is a finished match `me` played against another person: a seat of
## theirs, no bot at the table, and not two local seats ("Player 2"). Replays do not say "online".
static func is_match_against_someone(h: Dictionary, me: String) -> bool:
	var names: PackedStringArray = JsonUtil.as_strings(h.get("names", []))
	if not JsonUtil.as_bool(h.get("finished", false)) or names.size() != 2 or not names.has(me) or str(h.get("result", "")) == "":
		return false
	for b: Variant in JsonUtil.as_array(h.get("bots", [])):
		if JsonUtil.as_bool(b):
			return false
	for n: String in names:
		if n != me and n.begins_with("Player "):
			return false
	return names[0] != names[1]


## The newest matches `me` played against someone (headers with "path"), at most `count`. Reads
## newest first and stops early: a replay file is big and this is for a menu.
static func recent_against_someone(me: String, count: int, scan: int = 30) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if count <= 0 or not DirAccess.dir_exists_absolute(REPLAY_DIR):
		return out
	var files: PackedStringArray = DirAccess.get_files_at(REPLAY_DIR)
	files.sort()
	files.reverse()
	for f: String in files.slice(0, scan):
		if not f.ends_with(".json"):
			continue
		var path: String = REPLAY_DIR.path_join(f)
		var h: Dictionary = header_of(path)
		if h.is_empty():
			continue
		if is_match_against_someone(h, me):
			h["path"] = path
			out.append(h)
			if out.size() >= count:
				break
	_keep_headers()
	return out


# --- the match in progress ---------------------------------------------------------------

static func save_current(record: MatchRecord) -> void:
	_write_json(CURRENT_SAVE, record.to_dict())


static func has_current() -> bool:
	return FileAccess.file_exists(CURRENT_SAVE)


static func load_current() -> MatchRecord:
	return load_record(CURRENT_SAVE) if has_current() else null


static func save_current_online(record: MatchRecord) -> void:
	_write_json(CURRENT_ONLINE, record.to_dict())


static func has_current_online() -> bool:
	return FileAccess.file_exists(CURRENT_ONLINE)


static func load_current_online() -> MatchRecord:
	return load_record(CURRENT_ONLINE) if has_current_online() else null


static func clear_current_online() -> void:
	if has_current_online():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CURRENT_ONLINE))


## A saved match from another game version is not offered to continue (online playtest 2026-11-07:
## CONTINUE stayed across versions and crashed the game): both saves are dropped unless they were
## made by `version`.
static func drop_stale(version: String) -> void:
	for path: String in [CURRENT_SAVE, CURRENT_ONLINE]:
		if not FileAccess.file_exists(path):
			continue
		var d: Dictionary = JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
		if str(d.get("game_version", "")) != version:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


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


# --- the last match's battles (main menu idle preview, playtest 2026-10-30) ---------------------

const HIGHLIGHTS: String = "user://highlights"
const HIGHLIGHTS_MAX: int = 8


## A new match starts: the last one's battle pictures go.
static func clear_highlights() -> void:
	var dir := DirAccess.open(HIGHLIGHTS)
	if dir == null:
		return
	for f: String in dir.get_files():
		dir.remove(f)


## A picture of the table right after a battle; the newest HIGHLIGHTS_MAX stay.
static func save_highlight(img: Image) -> void:
	if img == null or img.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(HIGHLIGHTS))
	var names: PackedStringArray = _highlight_files()
	while names.size() >= HIGHLIGHTS_MAX:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(HIGHLIGHTS.path_join(names[0])))
		names.remove_at(0)
	var n: int = Time.get_ticks_usec()
	img.save_jpg(ProjectSettings.globalize_path(HIGHLIGHTS.path_join("%020d.jpg" % n)), 0.85)


static func highlights() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for f: String in _highlight_files():
		var img: Image = Image.load_from_file(ProjectSettings.globalize_path(HIGHLIGHTS.path_join(f)))
		if img != null and not img.is_empty():
			out.append(ImageTexture.create_from_image(img))
	return out


static func _highlight_files() -> PackedStringArray:
	var dir := DirAccess.open(HIGHLIGHTS)
	if dir == null:
		return PackedStringArray()
	var names := PackedStringArray()
	for f: String in dir.get_files():
		if f.ends_with(".jpg"):
			names.append(f)
	names.sort()
	return names
