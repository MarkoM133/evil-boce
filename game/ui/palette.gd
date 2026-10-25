class_name Palette
extends RefCounted
## UI and table colours (GDD 11: dark, flat, colour only where it means something).

const BG := Color("15120f")
const PANEL := Color(0.094, 0.078, 0.067, 0.88)
const PANEL_SOLID := Color("1d1814")
const FG := Color("f1e9dc")
const MUTED := Color("a99a86")
const LINE := Color("3b322a")
const BUTTON := Color("2d2620")
const BUTTON_HOVER := Color("3a3029")
const ACCENT := Color("d8322a")
const GOLD := Color("ffd23f")
const HEAL := Color("7ee08a")

const TEAM_COLORS: Array[Color] = [Color("2f7bff"), Color("d8322a")]
const TEAM_NAMES: Array[String] = ["Blue", "Red"]

const HERO_COLORS: Dictionary[String, Color] = {
	"Red": Color("e23b2e"),
	"Cyan": Color("35c9d6"),
	"Blue": Color("3c7df0"),
	"Green": Color("4fb858"),
	"Purple": Color("9a5bd6"),
	"Yellow": Color("f2c330"),
}
const DEFAULT_ACCENT := Color("2a2622")


static func team(i: int) -> Color:
	return TEAM_COLORS[clampi(i, 0, TEAM_COLORS.size() - 1)]


static func hero(color_name: String) -> Color:
	return HERO_COLORS.get(color_name, Color("b8ab98"))
