class_name CardDb
extends RefCounted
## Reads cards.json and images straight from the shared data folder. Loaded when a match or
## the sandbox starts, kept until it ends.

const PLACEHOLDER_TERRAIN: String = "res://data/placeholders/stage_terrain.json"
const PLACEHOLDER_FX: String = "res://data/placeholders/card_fx.json"

var root_dir: String = ""
var version: int = 0
var card_count: int = 0
## Card id -> small image in data/thumbs/ (same name as the full image, as .jpg).
var thumbs: Dictionary[String, String] = {}
var heroes: Array[HeroDef] = []
## Card id -> its standee sprite (heroes and evolutions that have one).
var sprite_paths: Dictionary[String, String] = {}
## Rules-side view of the same cards (placeholder cores and terrain applied).
var catalog: CardCatalog = CardCatalog.new()
var error: String = ""

var _textures: Dictionary[String, Texture2D] = {}
## Core hex tokens cut out of their cards (core_token).
var _tokens: Dictionary[String, Texture2D] = {}


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
	sprite_paths.clear()
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		error = "cards.json is not valid JSON (line %d)" % json.get_error_line()
		return
	var doc: Dictionary = json.data
	version = JsonUtil.as_int(doc.get("version", 0))
	catalog = CardCatalog.from_doc(doc)
	if FileAccess.file_exists(PLACEHOLDER_TERRAIN):
		catalog.apply_terrain_overrides(JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(PLACEHOLDER_TERRAIN))))
	if FileAccess.file_exists(PLACEHOLDER_FX):
		catalog.apply_fx_overrides(JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(PLACEHOLDER_FX))))
	# The traits a first tag may name (GDD 10, 2026-10-26), edited in the web app.
	var traits_path: String = data_dir().path_join("traits.json")
	if FileAccess.file_exists(traits_path):
		var td: Variant = JSON.parse_string(FileAccess.get_file_as_string(traits_path))
		catalog.set_traits(JsonUtil.as_array(JsonUtil.as_dict(td).get("traits", [])))
	# Sets: cards per Draft pack (web app, Card editor › Sets).
	var sets_path: String = data_dir().path_join("sets/sets.json")
	if FileAccess.file_exists(sets_path):
		catalog.set_sets(JsonUtil.as_dict(JSON.parse_string(FileAccess.get_file_as_string(sets_path))))
	var cards: Array = JsonUtil.as_array(doc.get("cards", []))
	card_count = 0
	for c: Variant in cards:
		if not c is Dictionary:
			continue
		var card: Dictionary = c
		if JsonUtil.as_bool(card.get("deleted", false)):
			continue
		card_count += 1
		var image: String = str(card.get("image", ""))
		if not image.is_empty():
			thumbs[str(card.get("id", ""))] = data_dir().path_join("thumbs/%s.jpg" % image.get_file().get_basename())
		var sprite: String = str(card.get("sprite", ""))
		if not sprite.is_empty():
			sprite_paths[str(card.get("id", ""))] = data_dir().path_join(sprite)
		if str(card.get("type", "")) == "Hero":
			heroes.append(HeroDef.from_card(card, data_dir()))
	heroes.sort_custom(func(a: HeroDef, b: HeroDef) -> bool: return a.id < b.id)


func is_ok() -> bool:
	return error.is_empty()


func sprite(hero: HeroDef) -> Texture2D:
	return texture(hero.sprite_path)


## The standee of a hero or an evolution card, or null when it has none.
func sprite_of(card_id: String) -> Texture2D:
	return texture(sprite_paths[card_id]) if sprite_paths.has(card_id) else null


func emblem(set_code: String) -> Texture2D:
	return texture(data_dir().path_join("branding/emblem-%s.png" % set_code))


## The card's large image (data/large/, about 2000 px wide), or null.
func large(card_id: String) -> Texture2D:
	if not thumbs.has(card_id):
		return null
	return texture(thumbs[card_id].replace("/thumbs/", "/large/"))


## The card's small image, or null.
func thumb(card_id: String) -> Texture2D:
	return texture(thumbs[card_id]) if thumbs.has(card_id) else null


## The hex token in the middle of a core card, cut out with the white card around it made
## transparent (Marko 2026-11-02: no white squares in the setup tray); cached.
func core_token(card_id: String) -> Texture2D:
	if _tokens.has(card_id):
		return _tokens[card_id]
	var tex: Texture2D = thumb(card_id)
	if tex == null:
		return null
	var src: Image = tex.get_image()
	if src == null:
		return null
	var sz := Vector2(src.get_width(), src.get_height())
	var img: Image = src.get_region(Rect2i(Vector2i(CORE_HEX.position * sz), Vector2i(CORE_HEX.size * sz)))
	img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	# White reached in a straight line from any edge goes; the token's white letters stay.
	for y: int in h:
		var x: int = 0
		while x < w and _whitish(img.get_pixel(x, y)):
			img.set_pixel(x, y, Color(0, 0, 0, 0))
			x += 1
		x = w - 1
		while x >= 0 and _whitish(img.get_pixel(x, y)):
			img.set_pixel(x, y, Color(0, 0, 0, 0))
			x -= 1
	for x: int in w:
		var y: int = 0
		while y < h and _whitish(img.get_pixel(x, y)):
			img.set_pixel(x, y, Color(0, 0, 0, 0))
			y += 1
		y = h - 1
		while y >= 0 and _whitish(img.get_pixel(x, y)):
			img.set_pixel(x, y, Color(0, 0, 0, 0))
			y -= 1
	var out: Texture2D = ImageTexture.create_from_image(img)
	_tokens[card_id] = out
	return out


static func _whitish(c: Color) -> bool:
	return c.a == 0.0 or (c.r > 0.78 and c.g > 0.78 and c.b > 0.78)


## A core's face-down back, by family (data/cores/<Family> Cardback.png), or null.
## A hidden core's back by its family; `card` null and `placeholder` "?Power" (an online guest's view of
## the other side's face-down core) gives that family's back.
func core_back(card: CardDef, placeholder: String = "") -> Texture2D:
	var family: String = card.core_family() if card != null else placeholder.trim_prefix(NetProtocol.PLACEHOLDER_CARD)
	return texture(data_dir().path_join("cores/%s Cardback.png" % family)) if not family.is_empty() else null


## Where the hex sits on a core image: a 1500 × 2100 page with the token (white rim included)
## right in the middle, measured off the pixels.
const CORE_HEX := Rect2(370.0 / 1500.0, 618.0 / 2100.0, 744.0 / 1500.0, 862.0 / 2100.0)


## A set's Draft pack picture (data/sets/<code>/pack.png), else the default pack, or null.
func pack_image(set_code: String) -> Texture2D:
	var tex: Texture2D = texture(data_dir().path_join("sets/%s/pack.png" % set_code)) if not set_code.is_empty() else null
	return tex if tex != null else texture(data_dir().path_join("sets/default/pack.png"))


## What sits behind the pack while a Draft runs (data/sets/<code>/draft-bg.png, else the default one), or null.
func draft_background(set_code: String) -> Texture2D:
	var tex: Texture2D = texture(data_dir().path_join("sets/%s/draft-bg.png" % set_code)) if not set_code.is_empty() else null
	return tex if tex != null else texture(data_dir().path_join("sets/default/draft-bg.png"))


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
