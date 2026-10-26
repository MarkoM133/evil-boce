class_name WebApp
extends RefCounted
## The web app (card studio: deck builder, cards, Balance) opened in the browser at one of its
## pages (`#/decks/new`, `#/decks/<slug>`, `#/balance`…). Its address is a setting
## (GitHub Pages unless changed, e.g. to the local server).

const DEFAULT_URL: String = "https://markom133.github.io/evil-boce/"


## The address with a page: "" for the start page, else "decks/new" and the like.
static func url(page: String = "") -> String:
	var base: String = GameSettings.web_app_url()
	if not base.ends_with("/"):
		base += "/"
	return base + ("#/" + page if not page.is_empty() else "")


static func open(page: String = "") -> void:
	OS.shell_open(url(page))


## A small button "TEXT ↗" that opens a page of the web app.
static func link(text: String, page: String, what: String = "") -> Button:
	var b := Button.new()
	b.text = text + "  ↗"
	b.theme_type_variation = &"Ghost"
	b.add_theme_font_size_override("font_size", 15)
	b.tooltip_text = (what + "\n" if not what.is_empty() else "") + "Opens the web app: " + url(page)
	b.pressed.connect(func() -> void: open(page))
	return b
