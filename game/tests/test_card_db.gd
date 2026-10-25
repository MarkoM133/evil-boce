extends GutTest

const SAMPLE: String = """{
  "version": 7,
  "cards": [
    {"id": "OP1-001", "name": "Luffy", "type": "Hero", "color": "Cyan", "wt": 2,
     "stats": {"hp": 8, "rng": 4}, "sprite": "sprites/OP1-001.png"},
    {"id": "OP1-005", "name": "Kaido", "type": "Hero", "color": "Blue", "wt": 3.0,
     "stats": {"hp": 12, "rng": 3}, "bakuganColor": "#123456", "bakuganColor2": "#761976"},
    {"id": "OP1-009", "name": "Observation Haki", "type": "Action"},
    {"id": "OP1-099", "name": "Gone", "type": "Hero", "deleted": true}
  ]
}"""


func test_parse_heroes() -> void:
	var db := CardDb.new()
	db.root_dir = "C:/data-root"
	db.parse(SAMPLE)
	assert_true(db.is_ok())
	assert_eq(db.version, 7)
	assert_eq(db.card_count, 3)
	assert_eq(db.heroes.size(), 2)
	var luffy: HeroDef = db.heroes[0]
	assert_eq(luffy.id, "OP1-001")
	assert_eq(luffy.set_code, "OP1")
	assert_eq(luffy.wt, 2)
	assert_eq(luffy.rng, 4)
	assert_eq(luffy.hp, 8)
	assert_eq(luffy.ball_color, Palette.hero("Cyan"))
	assert_eq(luffy.sprite_path, "C:/data-root/data/sprites/OP1-001.png")
	var kaido: HeroDef = db.heroes[1]
	assert_eq(kaido.wt, 3)
	assert_eq(kaido.ball_color, Color("#123456"))
	assert_eq(kaido.ball_accent, Color("#761976"))
	assert_eq(kaido.sprite_path, "")


func test_bad_json() -> void:
	var db := CardDb.new()
	db.parse("not json")
	assert_false(db.is_ok())
	assert_eq(db.heroes.size(), 0)


func test_missing_folder() -> void:
	var db: CardDb = CardDb.load_from("Z:/does/not/exist")
	assert_false(db.is_ok())
