class_name Sound
extends Node
## Sound effects and music from the shared folder (Marko 2026-11-15): `data/audio/sfx/` and `data/audio/music/`.
## A file's name says what it is for: `ko.ogg`, and `ko_2.ogg`, `ko_3.ogg`… for variations, one picked at random
## (ogg, wav or mp3). Nothing to register: a missing file is silence. `data/audio/sounds.json` may tune a sound:
## {"sfx": {"ko": {"volume": -3, "pitch": 0.05, "cooldown": 0.1}}} (volume in dB, pitch as a random spread).
## Music: `music/menu.*` in the menu, `music/match_<set>.*` in a match (the set of the first hero, e.g.
## match_op1), else `music/match.*`; several files with the same start are a playlist picked at random.
## The game's buses are Effects and Music (Settings → Sound); the files never go in git.

const EXTS: Array[String] = ["ogg", "wav", "mp3"]
const VOICES: int = 14
const FADE: float = 0.8
## The softest a sound gets for a weak hit (a share of full volume; Marko 2026-11-15: gentle bumps were not heard).
const SOFTEST: float = 0.35
## What a sound does by default; sounds.json overrides it per key.
const DEFAULTS: Dictionary = {
	"bump_ball": {"cooldown": 0.04, "pitch": 0.08},
	"bump_wall": {"cooldown": 0.06, "pitch": 0.08},
	"launch": {"pitch": 0.06},
	"ui_click": {"volume": -6.0, "cooldown": 0.03, "pitch": 0.04},
	"ui_hover": {"volume": -14.0, "cooldown": 0.05},
	"card": {"pitch": 0.05},
	"draw": {"cooldown": 0.08, "pitch": 0.06},
	"energy": {"cooldown": 0.12, "pitch": 0.05},
	"damage": {"cooldown": 0.08, "pitch": 0.05},
	"timer_tick": {"volume": -4.0},
}
## Rules events (the match log) and the sound each one plays.
const LOG_SOUNDS: Dictionary = {
	"damage": "damage", "hand_damage": "damage", "heal": "heal", "ko": "ko",
	"stage_energy": "energy", "energy": "energy", "stage_claimed": "claim", "stage_revealed": "reveal",
	"action": "card", "assist": "card", "equipped": "equip", "evolved": "evolve", "draw": "draw",
	"combo": "combo", "token": "token", "tokens_gone": "token_gone", "triggered": "ability", "ability": "ability",
	"core_activated": "core", "core_trap": "core", "battle": "battle", "duel": "battle", "turn_end": "turn",
	"match_start": "match_start",
}
## At most this many log sounds at once (a replay jumping ahead would be a wall of noise).
const LOG_BURST: int = 4

static var _node: Sound
## Tests: read sounds from this folder's data/audio instead of the shared folder.
static var root_override: String = ""

var _dir: String = ""
var _files: Dictionary = {}
var _streams: Dictionary = {}
var _tune: Dictionary = {}
var _last: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _music: Array[AudioStreamPlayer] = []
var _music_on: int = 0
var _music_key: String = "-"
var _pending: Array = []


## The one Sound node, made and hung on the root on first use.
static func instance(tree: SceneTree) -> Sound:
	if _node == null or not is_instance_valid(_node):
		_node = Sound.new()
		_node.name = "Sound"
		_node.process_mode = Node.PROCESS_MODE_ALWAYS
		_node._scan()
		tree.root.add_child.call_deferred(_node)
	return _node


## Plays `key` (strength 0..1 makes it softer, down to SOFTEST of full). Nothing happens without a file for it.
static func play(tree: SceneTree, key: String, strength: float = 1.0) -> void:
	if tree == null:
		return
	instance(tree)._play(key, strength)


## Plays the music for `key` (menu, match_op1…), looping; "" stops. The same key again keeps it going.
static func music(tree: SceneTree, key: String) -> void:
	if tree == null:
		return
	instance(tree)._music_to(key)


## The sounds for new match log entries (`me`: the viewer's seat, for winning and losing).
static func from_log(tree: SceneTree, entries: Array[Dictionary], me: int) -> void:
	if tree == null or entries.is_empty():
		return
	for key: String in log_keys(entries, me):
		play(tree, key)


## Which sounds those entries make, each once, at most LOG_BURST.
static func log_keys(entries: Array[Dictionary], me: int) -> Array[String]:
	var keys: Array[String] = []
	for e: Dictionary in entries:
		var t: String = str(e.get("type", ""))
		var key: String = ""
		if t == "match_end":
			var w: int = JsonUtil.as_int(e.get("winner", -1)) if e.has("winner") else -1
			key = "tie" if w < 0 else ("win" if w == me else "lose")
		else:
			key = str(LOG_SOUNDS.get(t, ""))
		if not key.is_empty() and not keys.has(key):
			keys.append(key)
	return keys.slice(0, LOG_BURST)


## Reads the folder again (new files dropped in while the game runs). Not "reload": that is the script's own.
static func rescan() -> void:
	if _node != null and is_instance_valid(_node):
		_node._scan()


func _ready() -> void:
	for i: int in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		_players.append(p)
	for i: int in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = -80.0
		add_child(m)
		_music.append(m)
	# Every button clicks.
	get_tree().node_added.connect(_on_node_added)
	for n: Node in get_tree().root.find_children("*", "BaseButton", true, false):
		_on_node_added(n)
	for job: Array in _pending:
		callv(str(job[0]), job.slice(1))
	_pending.clear()


func _scan() -> void:
	_dir = (root_override if not root_override.is_empty() else GameSettings.data_path()).path_join("data").path_join("audio")
	_files.clear()
	_streams.clear()
	for sub: String in ["sfx", "music"]:
		var d: String = _dir.path_join(sub)
		for f: String in DirAccess.get_files_at(d):
			if not EXTS.has(f.get_extension().to_lower()):
				continue
			var key: String = sub + "/" + _key_of(f.get_basename())
			var list: Array = _files.get(key, [])
			list.append(d.path_join(f))
			_files[key] = list
	var tune: Variant = JSON.parse_string(FileAccess.get_file_as_string(_dir.path_join("sounds.json"))) if FileAccess.file_exists(_dir.path_join("sounds.json")) else null
	_tune = JsonUtil.as_dict(JsonUtil.as_dict(tune).get("sfx", {})) if tune is Dictionary else {}


## "ko_2" and "ko-2" are variations of "ko"; the key is lower case.
static func _key_of(base: String) -> String:
	var b: String = base.to_lower()
	var re := RegEx.create_from_string("^(.*?)[_-]\\d+$")
	var m: RegExMatch = re.search(b)
	return m.get_string(1) if m != null else b


func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var s: AudioStream = null
	match path.get_extension().to_lower():
		"ogg":
			s = AudioStreamOggVorbis.load_from_file(path)
		"wav":
			s = AudioStreamWAV.load_from_file(path)
		"mp3":
			s = AudioStreamMP3.load_from_file(path)
	_streams[path] = s
	return s


func _setting(key: String, name: String, fallback: float) -> float:
	var own: Dictionary = JsonUtil.as_dict(_tune.get(key, {}))
	if own.has(name):
		return JsonUtil.as_float(own[name])
	return JsonUtil.as_float(JsonUtil.as_dict(DEFAULTS.get(key, {})).get(name, fallback))


func _play(key: String, strength: float) -> void:
	if not is_inside_tree():
		_pending.append(["_play", key, strength])
		return
	var list: Array = _files.get("sfx/" + key, [])
	if list.is_empty():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - JsonUtil.as_float(_last.get(key, -10.0)) < _setting(key, "cooldown", 0.0):
		return
	_last[key] = now
	var s: AudioStream = _stream(str(list[randi() % list.size()]))
	if s == null:
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = s
	p.volume_db = _setting(key, "volume", 0.0) + linear_to_db(lerpf(SOFTEST, 1.0, clampf(strength, 0.0, 1.0)))
	var spread: float = _setting(key, "pitch", 0.0)
	p.pitch_scale = 1.0 + randf_range(-spread, spread)
	p.play()


func _music_to(key: String) -> void:
	if not is_inside_tree():
		_pending.append(["_music_to", key])
		return
	# match_op1 → match: the set's own music, else the match's.
	var found: String = key
	while not found.is_empty() and not _files.has("music/" + found):
		var cut: int = found.rfind("_")
		found = found.substr(0, cut) if cut > 0 else ""
	if found == _music_key:
		return
	_music_key = found
	var from: AudioStreamPlayer = _music[_music_on]
	var t: Tween = create_tween()
	t.tween_property(from, "volume_db", -80.0, FADE)
	t.tween_callback(from.stop)
	if found.is_empty():
		return
	var list: Array = _files["music/" + found]
	var s: AudioStream = _stream(str(list[randi() % list.size()]))
	if s == null:
		return
	if "loop" in s:
		s.set("loop", true)
	_music_on = 1 - _music_on
	var to: AudioStreamPlayer = _music[_music_on]
	to.stream = s
	to.volume_db = -80.0
	to.play()
	create_tween().tween_property(to, "volume_db", 0.0, FADE)


func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("silent"):
		var b := n as BaseButton
		if not b.pressed.is_connected(_on_click):
			b.pressed.connect(_on_click)


func _on_click() -> void:
	_play("ui_click", 1.0)
