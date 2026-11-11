extends GutTest
## The players' rules for the pause menu's RULES tab (RulesText): Markdown sections as BBCode.

const MD: String = "# Evil Boće – Rules\n\n> DRAFT.\n\n## 1. The game\n\nYou **win** with 3 stages and [EN].\n\n" \
	+ "## 8. Battle\n\n| Stat | Meaning |\n|---|---|\n| **HP** | Hit points. |\n\n- One\n  and more\n- Two **[?]**\n\n1. First\n"


func test_sections_start_at_the_first_heading() -> void:
	var s: Array[Dictionary] = RulesText.sections(MD)
	assert_eq(s.size(), 2)
	assert_eq(str(s[0]["title"]), "1. The game")
	assert_eq(str(s[1]["title"]), "8. Battle")
	assert_false(str(s[0]["bb"]).contains("DRAFT"), "the intro is Card Studio's")


func test_bold_brackets_tables_and_lists() -> void:
	var s: Array[Dictionary] = RulesText.sections(MD)
	var one: String = str(s[0]["bb"])
	assert_true(one.contains("[b][color=#f3efe7]win[/color][/b]"))
	assert_true(one.contains("[lb]EN]"), "a [ of the text stays text")
	var battle: String = str(s[1]["bb"])
	assert_true(battle.contains("[table=2]"))
	assert_false(battle.contains("Meaning"), "the table's first row is its header")
	assert_true(battle.contains("Hit points."))
	assert_true(battle.contains("•  One and more"), "an indented line goes on with its item")
	assert_true(battle.contains("(?)"))
	assert_true(battle.contains("1.  First"))
	assert_true(RulesText.page(s[1]).begins_with("[font=res://ui/fonts/BarlowCondensed-Bold.ttf]"))


func test_no_file_no_sections() -> void:
	assert_eq(RulesText.sections("").size(), 0)
	assert_eq(RulesText.read("res://no/such/folder"), "")
