extends GutTest
## The bands in the middle of the match screen: one moment's bands merge into one, BATTLE!
## and the ties stand alone, the loudest names the merged band (playtest 2026-11-01).

const Hud := preload("res://scenes/match/match_hud.gd")


func _b(title: String, left: String = "", right: String = "", hold: float = 0.8) -> Dictionary:
	return {"title": title, "color": Color.RED, "left": left, "right": right, "hold": hold, "lines": PackedStringArray()}


func test_battle_and_ties_stand_alone() -> void:
	assert_true(Hud.stands_alone(_b("BATTLE!", "GIORNO\n3000", "SHANKS\n2500")))
	assert_true(Hud.stands_alone(_b("TIE!")))
	assert_true(Hud.stands_alone(_b("TIE AGAIN!")))
	assert_true(Hud.stands_alone(_b("ROLL PHASE", "TURN 3")))
	assert_false(Hud.stands_alone(_b("KO", "", "SHANKS")))
	assert_false(Hud.stands_alone(_b("GIORNO WINS THE FIGHT!")))


func test_winner_names_the_merged_band() -> void:
	var run: Array[Dictionary] = [_b("SHANKS TAKES 3 DAMAGE", "", "HP 0", 1.6), _b("GIORNO WINS THE FIGHT!", "", "", 2.0),
		_b("KO", "", "SHANKS"), _b("STAGE CLAIMED", "MARKO", "DRESSROSA")]
	var m: Dictionary = Hud.merge_banners(run)
	assert_eq(str(m["title"]), "GIORNO WINS THE FIGHT!")
	assert_eq(Array(JsonUtil.as_strings(m["lines"])), ["SHANKS TAKES 3 DAMAGE · HP 0", "KO · SHANKS", "STAGE CLAIMED · MARKO · DRESSROSA"])
	# Long enough to read the lines, never past three seconds.
	assert_almost_eq(JsonUtil.as_float(m["hold"]), 3.0, 0.001)


func test_ko_over_blows_and_more_lines_are_counted() -> void:
	var run: Array[Dictionary] = [_b("A TAKES 1 DAMAGE", "", "HP 4"), _b("HAKI", "GIORNO", ""), _b("KO", "", "SHANKS"),
		_b("B TAKES 2 DAMAGE", "", "HP 1"), _b("STAGE CLAIMED", "MARKO", "ALABASTA")]
	var m: Dictionary = Hud.merge_banners(run)
	assert_eq(str(m["title"]), "KO")
	assert_eq(str(m["right"]), "SHANKS")
	assert_eq(Array(JsonUtil.as_strings(m["lines"])), ["A TAKES 1 DAMAGE · HP 4", "HAKI · GIORNO", "+2 MORE"])


func test_single_band_stays_itself() -> void:
	var one: Dictionary = _b("RING-OUT", "", "SHANKS")
	assert_eq(Hud.merge_banners([one]), one)
