class_name GameSettings
extends RefCounted
## Player settings in user://settings.cfg. The data folder can also be given on the command
## line as `-- --data=<path>`.

const PATH: String = "user://settings.cfg"
const MAP_SIZES: Array[int] = [15, 17, 23]

static var _cfg: ConfigFile
## Tests set this to work on a fresh, unsaved config instead of the player's file.
static var in_memory: bool = false


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


## The sideboard last built for a saved deck (Best of 3), by the deck's name.
static func sideboard(deck_name: String) -> Dictionary:
	return JsonUtil.as_dict(_config().get_value("sideboard", deck_name, {})) if not deck_name.is_empty() else {}


static func set_sideboard(deck_name: String, side: Dictionary) -> void:
	if not deck_name.is_empty():
		set_value("sideboard", deck_name, side)


## Where the web app lives (WebApp opens its pages).
static func web_app_url() -> String:
	var u: String = str(_config().get_value("web", "url", "")).strip_edges()
	return u if not u.is_empty() else WebApp.DEFAULT_URL


static func set_web_app_url(u: String) -> void:
	set_value("web", "url", u.strip_edges())


## Match rules last used for a mode ("local", "online"): Standard with the remembered changes.
## Only the changes are stored, so a later Standard still shows through the rest.
static func match_rules(mode: String) -> MatchSettings:
	var d: Dictionary = MatchSettings.standard().to_dict()
	d.merge(JsonUtil.as_dict(_config().get_value("match_rules", mode, {})), true)
	var s: MatchSettings = MatchSettings.from_dict(d)
	if s.map_size != MatchSettings.MAP_RANDOM and not MAP_SIZES.has(s.map_size):
		s.map_size = MatchSettings.standard().map_size
	return s


static func set_match_rules(mode: String, s: MatchSettings) -> void:
	var std: Dictionary = MatchSettings.standard().to_dict()
	var diff: Dictionary = {}
	var now: Dictionary = s.to_dict()
	for k: Variant in now:
		if now[k] != std.get(k):
			diff[k] = now[k]
	set_value("match_rules", mode, diff)


static func save() -> void:
	if not in_memory:
		_config().save(PATH)


## Tests: start from an empty config that is never written to disk.
static func use_memory() -> void:
	in_memory = true
	_cfg = ConfigFile.new()


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


# --- display, sound and keys (Settings screen) ------------------------------------------------

const QUALITIES: Array[String] = ["low", "medium", "high"]
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]
## 0 = no limit.
const FPS_LIMITS: Array[int] = [0, 60, 120, 144, 240]
## Sound buses; Music and Effects send to Master and are made on first use.
const BUSES: Array[String] = ["Master", "Music", "Effects"]
## Rebindable keys: action -> default key.
const DEFAULT_KEYS: Dictionary[String, Key] = {"pass": KEY_SPACE, "menu": KEY_ESCAPE, "card_zoom": KEY_ALT,
	"battle_cam": KEY_C, "hold": KEY_CTRL, "beams": KEY_B}
## The card-zoom key: held (the card shows while it is down) or pressed (on, then off).
const ZOOM_MODES: Array[String] = ["hold", "press"]


static func zoom_mode() -> String:
	var v: String = str(_config().get_value("keys", "zoom_mode", "hold"))
	return v if ZOOM_MODES.has(v) else "hold"


static var _display_applied: bool = false


static func fullscreen() -> bool:
	return JsonUtil.as_bool(_config().get_value("display", "fullscreen", false))


static func resolution() -> Vector2i:
	var v: Variant = _config().get_value("display", "resolution", Vector2i(1600, 900))
	return v if v is Vector2i else Vector2i(1600, 900)


static func vsync() -> bool:
	return JsonUtil.as_bool(_config().get_value("display", "vsync", true))


static func max_fps() -> int:
	return JsonUtil.as_int(_config().get_value("display", "max_fps", 0))


## Size of the whole interface (menus and HUD) against the 1600 × 900 design: 0.8 … 1.1.
const UI_SCALES: Array[float] = [0.8, 0.9, 1.0, 1.1]


static func ui_scale() -> float:
	var v: float = JsonUtil.as_float(_config().get_value("display", "ui_scale", 1.0), 1.0)
	return clampf(v, 0.7, 1.3)


static func quality() -> String:
	var q: String = str(_config().get_value("display", "quality", "medium"))
	return q if QUALITIES.has(q) else "medium"


## 0..1, linear.
static func volume(bus: String) -> float:
	return clampf(JsonUtil.as_float(_config().get_value("sound", bus.to_lower(), 0.8)), 0.0, 1.0)


static func set_value(section: String, key_: String, value: Variant) -> void:
	_config().set_value(section, key_, value)
	save()


## Hit-stop and slow motion (GDD 11 juice); both on unless switched off in Settings.
const EFFECTS: Array[String] = ["hit_stop", "slow_mo"]


static func effect(name: String) -> bool:
	return JsonUtil.as_bool(_config().get_value("effects", name, true))


static func key(action: String) -> Key:
	var fallback: Key = DEFAULT_KEYS.get(action, KEY_NONE)
	var k: int = JsonUtil.as_int(_config().get_value("keys", action, int(fallback)), int(fallback))
	return k as Key


static func set_key(action: String, k: Key) -> void:
	set_value("keys", action, int(k))


static func reset_keys() -> void:
	for action: String in DEFAULT_KEYS:
		set_key(action, DEFAULT_KEYS[action])


## Turns a pressed key into the key the scenes match on: the key bound to "menu" reads as
## Escape, the one bound to "pass" as Space, and a default key that was moved elsewhere reads
## as nothing. Other keys pass through unchanged.
static func logical_key(code: Key) -> Key:
	for action: String in DEFAULT_KEYS:
		if code == key(action):
			return DEFAULT_KEYS[action]
	for action: String in DEFAULT_KEYS:
		if code == DEFAULT_KEYS[action]:
			return KEY_NONE
	return code


static func key_name(k: Key) -> String:
	return OS.get_keycode_string(k) if k != KEY_NONE else "—"


## Window, frame rate, sound and quality; the window only on the first call (start-up) or when
## `force` is set (the Settings screen), so going back to the menu does not move it.
static func apply(tree: SceneTree, force: bool = false) -> void:
	if force or not _display_applied:
		_display_applied = true
		if fullscreen():
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var size: Vector2i = resolution()
			var screen: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
			size = Vector2i(mini(size.x, screen.size.x), mini(size.y, screen.size.y))
			DisplayServer.window_set_size(size)
			DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)
	tree.root.content_scale_factor = ui_scale()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync() else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps()
	match quality():
		"low":
			tree.root.msaa_3d = Viewport.MSAA_DISABLED
			tree.root.scaling_3d_scale = 0.75
		"high":
			tree.root.msaa_3d = Viewport.MSAA_4X
			tree.root.scaling_3d_scale = 1.0
		_:
			tree.root.msaa_3d = Viewport.MSAA_2X
			tree.root.scaling_3d_scale = 1.0
	for bus: String in BUSES:
		var i: int = AudioServer.get_bus_index(bus)
		if i < 0:
			AudioServer.add_bus()
			i = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
		var v: float = volume(bus)
		AudioServer.set_bus_mute(i, v <= 0.001)
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))


## Last stages / cores picked (Loadout.to_dict()), per "p1", "p2" or "online".
static func loadout(who: String) -> Dictionary:
	return JsonUtil.as_dict(_config().get_value("loadout", who, {}))


static func set_loadout(who: String, d: Dictionary) -> void:
	set_value("loadout", who, d)


## The saved deck last picked per seat ("p1", "p2", "online"); "" = random.
static func last_deck(who: String) -> String:
	return str(_config().get_value("last_deck", who, ""))


static func set_last_deck(who: String, name: String) -> void:
	set_value("last_deck", who, name)


## Main menu layouts: the hero strip down the left (mockup M3), cinema (M8).
const MENU_LAYOUTS: Array[String] = ["strip", "cinema"]
## What fills the cinema layout's middle: nothing but the logo, cards with the last match and
## what is new (M8 + 5), or the match table with heroes' balls (M8 + 3).
const CINEMA_FILLS: Array[String] = ["empty", "info", "table"]


static func menu_layout() -> String:
	var v: String = str(_config().get_value("display", "menu_layout", "strip"))
	# "table" was a layout of its own before it became a cinema fill; the others are gone.
	if v == "table":
		return "cinema"
	return v if MENU_LAYOUTS.has(v) else "strip"


static func cinema_fill() -> String:
	var v: String = str(_config().get_value("display", "cinema_fill", ""))
	if v == "" and str(_config().get_value("display", "menu_layout", "")) == "table":
		return "table"
	return v if CINEMA_FILLS.has(v) else "info"


## The camera flies to each battle as it starts (Settings → Display).
static func battle_cam_auto() -> bool:
	return JsonUtil.as_bool(_config().get_value("display", "battle_cam", true))


## Card and ability text shows on hover (Settings); the big card (right click / key) always works.
static func hover_text() -> bool:
	return JsonUtil.as_bool(_config().get_value("display", "hover_text", true))


## Auto-pass (GDD 8): the game passes for a player with nothing playable, after a fixed wait,
## unless the Hold key is down. Settings → Interface.
static func auto_pass() -> bool:
	return JsonUtil.as_bool(_config().get_value("display", "auto_pass", true))


# --- interface (Settings → Interface) -----------------------------------------------------------

## Light beams over the heroes a card or a pick points at (the rings always show). Key B.
static func beams() -> bool:
	return JsonUtil.as_bool(_config().get_value("display", "beams", true))


## Banners in the middle: "all" (phases too), "moments" (battles, KOs, ring-outs, claims), "off".
const BANNER_MODES: Array[String] = ["all", "moments", "off"]


static func banners() -> String:
	var v: String = str(_config().get_value("display", "banners", "all"))
	return v if BANNER_MODES.has(v) else "all"


## The splash (logo, press any key) when the game starts.
static func splash() -> bool:
	return JsonUtil.as_bool(_config().get_value("display", "splash", true))


## A small frames-per-second counter in the corner of a match.
static func show_fps() -> bool:
	return JsonUtil.as_bool(_config().get_value("display", "fps", false))


## Range circles: "active" (the activated heroes always, others on hover) or "hover" (only on hover).
const RANGE_MODES: Array[String] = ["active", "hover"]


static func range_mode() -> String:
	var v: String = str(_config().get_value("display", "range", "active"))
	return v if RANGE_MODES.has(v) else "active"


## Animation speed (GDD 11): "normal" or "fast". Banners, knockback, battle camera waits.
const ANIM_SPEEDS: Array[String] = ["normal", "fast"]


static func anim_speed() -> String:
	var v: String = str(_config().get_value("display", "anim_speed", "normal"))
	return v if ANIM_SPEEDS.has(v) else "normal"


## How long timed things last at this animation speed (1 normal, less when fast).
static func anim_scale() -> float:
	return 0.55 if anim_speed() == "fast" else 1.0


## Everything back to its default except the shared folder, the online name, decks and picks.
static func reset_to_defaults() -> void:
	for section: String in ["display", "effects", "sound", "keys"]:
		if _config().has_section(section):
			_config().erase_section(section)
	save()
