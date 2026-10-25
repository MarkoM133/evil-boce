class_name CardDb
extends RefCounted
## Reads cards.json and images straight from the shared data folder. Loaded when a match or
## the sandbox starts, kept until it ends.

var root_dir: String = ""
var version: int = 0
var card_count: int = 0
var heroes: Array[HeroDef] = []
var error: String = ""

var _textures: Dictionary[String, Texture2D] = {}


## `root` is the shared folder (the one with data/, decks/, ...).
static func load_from(root: String) -> CardDb:
	var db := CardDb.new()
	db.root_dir = root
	var path: String = db.data_dir().path_join("cards.json")
	if not FileAccess.file_exists(path):
		db.error = "cards.json not found in %s" % db.data_dir()
		return db
	db.parse(FileAccess.get_file_as_string(path))
	return db


func data_dir() -> String:
	return root_dir.path_join("data")


func parse(text: String) -> void:
	heroes.clear()
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		error = "cards.json is not valid JSON (line %d)" % json.get_error_line()
		return
	var doc: Dictionary = json.data
	version = JsonUtil.as_int(doc.get("version", 0))
	var cards: Array = JsonUtil.as_array(doc.get("cards", []))
	card_count = 0
	for c: Variant in cards:
		if not c is Dictionary:
			continue
		var card: Dictionary = c
		if JsonUtil.as_bool(card.get("deleted", false)):
			continue
		card_count += 1
		if str(card.get("type", "")) == "Hero":
			heroes.append(HeroDef.from_card(card, data_dir()))
	heroes.sort_custom(func(a: HeroDef, b: HeroDef) -> bool: return a.id < b.id)


func is_ok() -> bool:
	return error.is_empty()


func sprite(hero: HeroDef) -> Texture2D:
	return texture(hero.sprite_path)


func emblem(set_code: String) -> Texture2D:
	return texture(data_dir().path_join("branding/emblem-%s.png" % set_code))


func logo() -> Texture2D:
	return texture(data_dir().path_join("branding/evil-boce-logo.png"))


## Loads an image file from disk once; null if it is missing.
func texture(abs_path: String) -> Texture2D:
	if abs_path.is_empty():
		return null
	if _textures.has(abs_path):
		return _textures[abs_path]
	var tex: Texture2D = null
	if FileAccess.file_exists(abs_path):
		var img: Image = Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	_textures[abs_path] = tex
	return tex
