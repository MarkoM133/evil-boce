class_name HeroDef
extends RefCounted
## The parts of a Hero card the sandbox needs.

var id: String = ""
var name: String = ""
var color_name: String = ""
var set_code: String = ""
var wt: int = 2
var rng: int = 3
var hp: int = 10
var ball_color: Color = Color.WHITE
var ball_accent: Color = Palette.DEFAULT_ACCENT
## Absolute path, empty when the card has no sprite.
var sprite_path: String = ""


## `data_dir` is the folder that holds cards.json.
static func from_card(card: Dictionary, data_dir: String) -> HeroDef:
	var h := HeroDef.new()
	h.id = str(card.get("id", ""))
	h.name = str(card.get("name", h.id))
	h.color_name = str(card.get("color", ""))
	h.set_code = h.id.get_slice("-", 0)
	h.wt = maxi(1, JsonUtil.as_int(card.get("wt", 2), 2))
	var stats: Dictionary = JsonUtil.as_dict(card.get("stats", {}))
	h.rng = JsonUtil.as_int(stats.get("rng", 3), 3)
	h.hp = JsonUtil.as_int(stats.get("hp", 10), 10)
	h.ball_color = _color(card.get("ballColor", card.get("bakuganColor", "")), Palette.hero(h.color_name))
	h.ball_accent = _color(card.get("ballColor2", card.get("bakuganColor2", "")), Palette.DEFAULT_ACCENT)
	var sprite: String = str(card.get("sprite", ""))
	if not sprite.is_empty():
		h.sprite_path = data_dir.path_join(sprite)
	return h


## Generic heroes for when no cards.json is found.
static func test_heroes() -> Array[HeroDef]:
	var out: Array[HeroDef] = []
	var colors: Array[String] = ["Red", "Cyan", "Green", "Purple"]
	for wt: int in [1, 2, 3, 4]:
		var h := HeroDef.new()
		h.id = "TEST-%03d" % wt
		h.name = "Test WT%d" % wt
		h.color_name = colors[wt - 1]
		h.set_code = "TEST"
		h.wt = wt
		h.ball_color = Palette.hero(h.color_name)
		out.append(h)
	return out


static func _color(v: Variant, fallback: Color) -> Color:
	var s: String = str(v) if v != null else ""
	if not s.is_empty() and Color.html_is_valid(s):
		return Color.html(s)
	return fallback
