class_name Palette
extends RefCounted
## UI and table colours, the same as the web app's (css/style.css: the logo's black, compass
## red, "BOĆE" white and straw-hat yellow). Colour only where it means something.

const BG := Color("000000")
## Behind the 3D table: a warm near-black, so the table reads as a lit wooden surface.
const TABLE_BG := Color("15120f")
const PANEL := Color(0.078, 0.078, 0.078, 0.94)
const PANEL_SOLID := Color("141414")
const SURFACE_2 := Color("1e1e1e")
const FG := Color("f3efe7")
const MUTED := Color("8d8a85")
const DIM := Color("5a5650")
const LINE := Color("2b2b2b")
const BUTTON := Color("1e1e1e")
const BUTTON_HOVER := Color("2a2a2a")
const ACCENT := Color("e3120b")
const ACCENT_HOVER := Color("ff2a1f")
const ACCENT_DEEP := Color("6e0b07")
const GOLD := Color("f4b62a")
const HEAL := Color("7ee08a")
const HP := Color("23b14d")

const TEAM_COLORS: Array[Color] = [Color("2f6bff"), Color("e3120b")]
const TEAM_NAMES: Array[String] = ["Blue", "Red"]

const HERO_COLORS: Dictionary[String, Color] = {
	"Red": Color("e3120b"),
	"Cyan": Color("22c7dd"),
	"Blue": Color("2f6bff"),
	"Green": Color("23b14d"),
	"Purple": Color("c43bd6"),
	"Yellow": Color("e8c21a"),
}
const DEFAULT_ACCENT := Color("2a2622")


static func team(i: int) -> Color:
	return TEAM_COLORS[clampi(i, 0, TEAM_COLORS.size() - 1)]


static func hero(color_name: String) -> Color:
	return HERO_COLORS.get(color_name, Color("6b6b6b"))


## HP bar colour: green, straw when low, red when nearly gone.
static func hp(frac: float) -> Color:
	if frac > 0.4:
		return HP
	return GOLD if frac > 0.2 else ACCENT
