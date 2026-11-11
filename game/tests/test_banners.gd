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


## The KO announcement (the card over the screen) is not a band to merge: it stands alone, and the
## heroes of one moment share one, after the blows (KO6).
func test_ko_announcements_gather_after_the_blows() -> void:
	var ko_a: Dictionary = _b("KO", "", "ZORO")
	ko_a["ko"] = PackedStringArray(["p0:a"])
	var ko_b: Dictionary = _b("KO", "", "FUGO")
	ko_b["ko"] = PackedStringArray(["p1:b"])
	assert_true(Hud.stands_alone(ko_a))
	var hit_a: Dictionary = _b("ZORO TAKES 9 DAMAGE", "", "HP 0")
	var hit_b: Dictionary = _b("FUGO TAKES 8 DAMAGE", "", "HP 0")
	var out: Array[Dictionary] = Hud.gather_kos([hit_a, ko_a, hit_b, ko_b])
	assert_eq(out.size(), 3)
	assert_eq(str(out[0]["title"]), "ZORO TAKES 9 DAMAGE")
	assert_eq(str(out[1]["title"]), "FUGO TAKES 8 DAMAGE")
	assert_eq(Array(JsonUtil.as_strings(out[2]["ko"])), ["p0:a", "p1:b"])
	assert_eq(Hud.gather_kos([hit_a]).size(), 1, "nothing to gather")


## A stat's colour says up or down and how long (B3b): the shortest bonus on it decides.
func test_a_stat_takes_the_colour_of_its_shortest_bonus() -> void:
	assert_eq(Hud.stat_tint(0, 0, 0).a, 0.0, "nothing moved it: no colour")
	assert_eq(Hud.stat_tint(0, 0, 2), Hud.BONUS_LASTING_UP)
	assert_eq(Hud.stat_tint(0, 0, -1), Hud.BONUS_LASTING_DOWN)
	assert_eq(Hud.stat_tint(0, 1000, 0), Hud.BONUS_TURN_UP)
	assert_eq(Hud.stat_tint(0, -1, 0), Hud.BONUS_TURN_DOWN)
	assert_eq(Hud.stat_tint(-1, 2, 3), Hud.BONUS_PHASE_DOWN, "this phase before this turn and for good")
	assert_eq(Hud.stat_tint(0, 1, -2), Hud.BONUS_TURN_UP, "this turn before for good")


func test_winner_names_the_merged_band() -> void:
	var run: Array[Dictionary] = [_b("SHANKS TAKES 3 DAMAGE", "", "HP 0", 1.6), _b("GIORNO WINS THE FIGHT!", "", "", 2.0),
		_b("KO", "", "SHANKS"), _b("STAGE CLAIMED", "MARKO", "DRESSROSA")]
	var m: Dictionary = Hud.merge_banners(run)
	assert_eq(str(m["title"]), "GIORNO WINS THE FIGHT!")
	assert_eq(Array(JsonUtil.as_strings(m["lines"])), ["SHANKS TAKES 3 DAMAGE · HP 0", "KO · SHANKS", "STAGE CLAIMED · MARKO · DRESSROSA"])
	# The longest part (2 s) plus time per line to read it.
	assert_almost_eq(JsonUtil.as_float(m["hold"]), 2.0 + 3 * Hud.MERGED_LINE_TIME, 0.001)


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


## The battle a band belongs to (the bar above stays on it while the band shows) survives a merge,
## whichever band names the merged one.
func test_merged_band_keeps_its_battle() -> void:
	var hit: Dictionary = _b("A TAKES 1 DAMAGE", "", "HP 4")
	hit["battle"] = {"turn": 3, "index": 1}
	var m: Dictionary = Hud.merge_banners([hit, _b("KO", "", "SHANKS")])
	assert_eq(str(m["title"]), "KO")
	assert_eq(JsonUtil.as_int(JsonUtil.as_dict(m["battle"]).get("index", -1)), 1)


func test_energy_band_reads_as_one_line_when_merged() -> void:
	assert_eq(Hud.line_of(_b("+6 ENERGY", "PLAYER 1", "EGGHEAD · 14/14 · 2 LOST\nDRUM ISLAND · 3/14")),
		"+6 ENERGY · PLAYER 1 · EGGHEAD · 14/14 · 2 LOST DRUM ISLAND · 3/14")
