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


## A small button "TEXT" with an "opens outside" icon (a box with an arrow out of its corner;
## the ↗ arrow read badly, playtest 2026-10-30) that opens a page of the web app.
static func link(text: String, page: String, what: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.icon = external_icon()
	b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	b.expand_icon = false
	b.theme_type_variation = &"Ghost"
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_constant_override("h_separation", 8)
	b.tooltip_text = (what + "\n" if not what.is_empty() else "") + "Opens the web app: " + url(page)
	b.pressed.connect(func() -> void: open(page))
	return b


static var _external: ImageTexture


## A 14 px "open outside" icon drawn once: an open box and an arrow leaving its top right corner.
static func external_icon() -> Texture2D:
	if _external != null:
		return _external
	var n: int = 14
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Color(1, 1, 1, 0.9)
	# The box: left, bottom and the lower part of the right side, the top only on its left.
	for i: int in range(2, n - 1):
		img.set_pixel(1, i, c)
		img.set_pixel(i - 1, n - 2, c)
	for i: int in range(7, n - 1):
		img.set_pixel(n - 2, i, c)
	for i: int in range(1, 6):
		img.set_pixel(i, 2, c)
	# The arrow: a diagonal from the middle to the corner, and its head.
	for i: int in range(0, 7):
		img.set_pixel(6 + i, 7 - i, c)
		img.set_pixel(6 + i, 8 - i, c)
	for i: int in range(8, n):
		img.set_pixel(i, 0, c)
		img.set_pixel(n - 1, n - 1 - i, c)
	_external = ImageTexture.create_from_image(img)
	return _external
