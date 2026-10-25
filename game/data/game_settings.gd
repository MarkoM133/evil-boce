class_name GameSettings
extends RefCounted
## Player settings in user://settings.cfg. The data folder can also be given on the command
## line as `-- --data=<path>`.

const PATH: String = "user://settings.cfg"
const MAP_SIZES: Array[int] = [15, 17, 23]

static var _cfg: ConfigFile


static func data_path() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--data="):
			return arg.trim_prefix("--data=").replace("\\", "/")
	var p: String = str(_config().get_value("data", "path", ""))
	if p.is_empty():
		p = default_data_path()
	return p.replace("\\", "/")


static func default_data_path() -> String:
	var home: String = OS.get_environment("USERPROFILE").replace("\\", "/")
	return home.path_join("Documents/Other/TTS_Custom/EvilBoce")


static func set_data_path(p: String) -> void:
	_config().set_value("data", "path", p)
	save()


static func map_size() -> int:
	var n: int = JsonUtil.as_int(_config().get_value("sandbox", "map_size", 23), 23)
	return n if MAP_SIZES.has(n) else 23


static func set_map_size(n: int) -> void:
	_config().set_value("sandbox", "map_size", n)
	save()


static func save() -> void:
	_config().save(PATH)


static func _config() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		if FileAccess.file_exists(PATH):
			_cfg.load(PATH)
	return _cfg


## Online: the player's nickname and the last host address, kept between sessions.
static func player_name() -> String:
	var n: String = str(_config().get_value("online", "name", ""))
	return n if not n.is_empty() else OS.get_environment("USERNAME")


static func set_player_name(n: String) -> void:
	_config().set_value("online", "name", n.strip_edges())
	save()


static func last_host() -> String:
	return str(_config().get_value("online", "host", ""))


static func set_last_host(address: String) -> void:
	_config().set_value("online", "host", address.strip_edges())
	save()
