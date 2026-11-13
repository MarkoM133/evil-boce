extends GutTest

const SAMPLE: String = """{
  "version": 7,
  "cards": [
    {"id": "OP1-001", "name": "Luffy", "type": "Hero", "color": "Cyan", "wt": 2,
     "stats": {"hp": 8, "rng": 4}, "sprite": "sprites/OP1-001.png"},
    {"id": "OP1-005", "name": "Kaido", "type": "Hero", "color": "Blue", "wt": 3.0,
     "stats": {"hp": 12, "rng": 3}, "ballColor": "#123456", "ballColor2": "#761976"},
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


## The logo's grab animation (2026-11-13): its layers come from the shared folder's branding/logo-anim, all of them
## or none (the menu keeps the still logo then).
func test_the_logo_animation_needs_all_its_layers() -> void:
	var root: String = ProjectSettings.globalize_path("user://test_logo_anim")
	var dir: String = root.path_join("data").path_join(CardDb.LOGO_ANIM_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var db := CardDb.new()
	db.root_dir = root
	assert_eq(db.logo_anim_dir(), "", "no layers")
	assert_null(db.logo_clean())
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	for f: String in CardDb.LOGO_ANIM_FILES:
		if f != "eyes.png":
			img.save_png(dir.path_join(f))
	assert_eq(db.logo_anim_dir(), "", "one missing")
	img.save_png(dir.path_join("eyes.png"))
	assert_eq(db.logo_anim_dir(), dir)
	assert_not_null(db.logo_clean())
	for f: String in CardDb.LOGO_ANIM_FILES:
		DirAccess.remove_absolute(dir.path_join(f))
