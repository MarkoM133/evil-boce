class_name MenuLogo
extends Control
## The side strip menu's logo. Left alone for IDLE seconds (no mouse or key), it fades out and
## the last match takes its place in the logo's circle (its battles one after another, else its
## end), slowly zooming in, with a line about it
## under the circle; any mouse move, key or click brings the logo back.
##
## With the animation's layers in the shared folder (`anim_dir`, CardDb.logo_anim_dir) the logo is Evil Bochet's
## grab (ZF2, Marko 2026-11-11/12): the clean logo, his hands rise small and dark behind it, come forward open over
## it, the fingers close on it and pull it back a little, the eyes flash; then the eyes follow the mouse, blink now
## and then and their glow breathes. The grab plays once a run; later visits find him holding it.

const IDLE: float = 8.0
const FADE: float = 0.7
## Each picture zooms from 1 to 1 + ZOOM while it shows.
const ZOOM: float = 0.18
## The circle's radius as a share of half the control's smaller side (the logo's ring).
const RING: float = 0.8
const POINTS: int = 96
const SHOW_TIME: float = 4.0
const BLEND_TIME: float = 0.8

var logo: Texture2D
var shot: Texture2D
## Pictures from the last match's battles; with any, the circle goes through them one after
## another (playtest 2026-10-30: one picture only), cross-fading every SHOW_TIME seconds.
var shots: Array[Texture2D] = []
var caption: String = ""
var _idle: float = 0.0
## 0: the logo, 1: the last match.
var _k: float = 0.0
var _zoom_t: float = 0.0
## The folder of the animation's layers, "" for the still logo.
var anim_dir: String = ""
## The four fingers' knuckles in the 1024 picture (their pivots: each finger layer is that whole finger, skin and
## claw, and turns about the top of it) and how far each turns open.
const KNUCKLES: Array[Vector2] = [Vector2(282, 222), Vector2(445, 95), Vector2(760, 108), Vector2(880, 212)]
const OPEN_DEG: Array[float] = [52.0, 42.0, -42.0, -52.0]
## The eyes' middle in the 1024 picture (they blink about it).
const EYES_AT := Vector2(540, 292)
static var _grab_played: bool = false
## Which run of the animation is the live one: a replay starts a new run and the old one's waits end.
var _run: int = 0
var _root: Control
var _base: TextureRect
var _hands: Control
var _fingers: Array[TextureRect] = []
var _eyes: TextureRect


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	if not anim_dir.is_empty():
		_play.call_deferred()


func _process(delta: float) -> void:
	if _root != null:
		# The last match takes the animated logo's place the same way as the still one's.
		_root.modulate.a = 1.0 - _k
		if _eyes != null:
			_look()
	if shot == null and shots.is_empty():
		return
	_idle += delta
	var was: float = _k
	_k = move_toward(_k, 1.0 if _idle >= IDLE else 0.0, delta / FADE)
	_zoom_t = _zoom_t + delta if _k > 0.0 else 0.0
	if _k != was or _k > 0.0:
		queue_redraw()


func _input(event: InputEvent) -> void:
	# The window gets the odd motion event of no length (focus, other windows); not a move.
	if event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() >= 2.0:
			_idle = 0.0
	elif event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		_idle = 0.0
	# The grab once more (Marko 2026-11-13, while the menu is being worked on): F5, or a click on the logo.
	if anim_dir.is_empty() or _root == null:
		return
	var key := event as InputEventKey
	var click := event as InputEventMouseButton
	var f5: bool = key != null and key.pressed and not key.echo and key.keycode == KEY_F5
	var on_logo: bool = click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT \
			and get_global_rect().has_point(click.position)
	if f5 or on_logo:
		replay()


## The grab from the start: the hands behind the logo again, then the grab, the flash and the eyes.
func replay() -> void:
	if anim_dir.is_empty():
		return
	_run += 1
	if is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_eyes = null
	_fingers.clear()
	_grab_played = false
	_play()


## Screenshots: as if left alone long enough.
func go_idle() -> void:
	_idle = IDLE


func _draw() -> void:
	var c: Vector2 = size * 0.5
	if logo != null and _k < 1.0 and anim_dir.is_empty():
		var ls: Vector2 = logo.get_size()
		var fit: float = minf(size.x / ls.x, size.y / ls.y)
		draw_texture_rect(logo, Rect2(c - ls * fit * 0.5, ls * fit), false, Color(1, 1, 1, 1.0 - _k))
	var pics: Array[Texture2D] = shots if not shots.is_empty() else ([shot] as Array[Texture2D])
	if pics.is_empty() or pics[0] == null or _k <= 0.0:
		return
	var r: float = minf(size.x, size.y) * 0.5 * RING
	# Which picture now and how far into the fade to the next; each zooms in while it shows.
	var step: float = _zoom_t / SHOW_TIME
	var i: int = int(step) % pics.size()
	var into: float = step - floorf(step)
	var blend: float = clampf((into * SHOW_TIME - (SHOW_TIME - BLEND_TIME)) / BLEND_TIME, 0.0, 1.0) if pics.size() > 1 else 0.0
	_circle(pics[i], c, r, 1.0 + ZOOM * into, _k)
	if blend > 0.0:
		_circle(pics[(i + 1) % pics.size()], c, r, 1.0, _k * blend)
	draw_arc(c, r, 0.0, TAU, POINTS, Color(Palette.ACCENT, _k), 8.0, true)
	if caption != "":
		var font: Font = UiTheme.display_heavy()
		draw_string(font, Vector2(0, c.y + r + 44.0), caption.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 20,
			Color(Palette.FG, _k))


## One picture in the circle: a square from its middle, smaller as `zoom` grows.
func _circle(pic: Texture2D, c: Vector2, r: float, zoom: float, alpha: float) -> void:
	var sz: Vector2 = pic.get_size()
	var side: float = minf(sz.x, sz.y) / zoom
	var uv_half := Vector2(side / sz.x, side / sz.y) * 0.5
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i: int in POINTS:
		var d := Vector2.from_angle(TAU * i / POINTS)
		pts.append(c + d * r)
		uvs.append(Vector2(0.5, 0.5) + d * uv_half)
	var colors := PackedColorArray()
	colors.resize(POINTS)
	colors.fill(Color(1, 1, 1, alpha))
	draw_polygon(pts, colors, uvs, pic)


# --- the grab animation --------------------------------------------------------------------------------

func _layer(parent: Control, file: String, side: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = ImageTexture.create_from_image(Image.load_from_file(anim_dir.path_join(file)))
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.size = Vector2(side, side)
	t.pivot_offset = Vector2(side, side) * 0.5
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t


## True while the menu is still there to animate (it may be left in the middle of the grab) and `run` is still the
## live run (a replay starts another).
func _here(run: int) -> bool:
	return is_inside_tree() and run == _run and is_instance_valid(_root)


func _play() -> void:
	var run: int = _run
	await get_tree().process_frame
	if not is_inside_tree() or run != _run:
		return
	var side: float = minf(size.x, size.y)
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.size = Vector2(side, side)
	_root.position = (size - _root.size) * 0.5
	_root.pivot_offset = _root.size * 0.5
	add_child(_root)
	# The hands: the back of them and four fingers, each turning about its knuckle.
	_hands = Control.new()
	_hands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hands.size = Vector2(side, side)
	_hands.pivot_offset = Vector2(side * 0.5, side * 0.42)
	_root.add_child(_hands)
	_layer(_hands, "body.png", side)
	for k: int in 4:
		var f: TextureRect = _layer(_hands, "finger%d.png" % k, side)
		f.pivot_offset = KNUCKLES[k] * (side / 1024.0)
		f.rotation_degrees = OPEN_DEG[k]
		_fingers.append(f)
	_base = _layer(_root, "base_clean.png", side)
	_eyes = _layer(_root, "eyes.png", side)
	_eyes.modulate.a = 0.0
	_eyes.pivot_offset = EYES_AT * (side / 1024.0)
	# Behind the logo, small (far back) and in shadow.
	_hands.scale = Vector2.ONE * 0.62
	_hands.position.y = side * 0.16
	_hands.modulate = Color(0.25, 0.2, 0.3, 1.0)
	# The clean logo is there at once (the splash's lands on it); the hands wait until the splash is gone.
	_hands.visible = false
	while _here(run) and (not get_tree().root.find_children("*", "Splash", true, false).is_empty() or not is_visible_in_tree()):
		await get_tree().process_frame
	if not _here(run):
		return
	_hands.visible = true
	if _grab_played:
		_held(run)
		return
	_grab_played = true
	await _grab(side, run)
	if _here(run):
		_eyes_alive(run)


## The grab, once a run.
func _grab(side: float, run: int) -> void:
	var breathe: Tween = _base.create_tween().set_loops()
	breathe.tween_property(_base, "scale", Vector2.ONE * 1.012, 1.1).set_trans(Tween.TRANS_SINE)
	breathe.tween_property(_base, "scale", Vector2.ONE, 1.1).set_trans(Tween.TRANS_SINE)
	# A little sooner and quicker on the menu than in the mockup (Marko 2026-11-12).
	await get_tree().create_timer(0.7).timeout
	if not _here(run):
		return
	# The fingers flex a little as the hands rise (a third of the first try, and slower: less wiggling in the dark).
	var flexes: Array[Tween] = []
	for k: int in 4:
		var flex: Tween = _fingers[k].create_tween().set_loops(3)
		flex.tween_property(_fingers[k], "rotation_degrees", OPEN_DEG[k] * 0.92, 0.32).set_trans(Tween.TRANS_SINE)
		flex.tween_property(_fingers[k], "rotation_degrees", OPEN_DEG[k], 0.32).set_trans(Tween.TRANS_SINE)
		flexes.append(flex)
	var t: Tween = _hands.create_tween()
	# Rising behind it until the fingers show over the top...
	t.tween_property(_hands, "position:y", -side * 0.06, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.08)
	# ...forward over it, still open...
	t.tween_callback(func() -> void:
		breathe.kill()
		_base.scale = Vector2.ONE
		for fl: Tween in flexes:
			fl.kill()
		for k: int in 4:
			_fingers[k].rotation_degrees = OPEN_DEG[k]
		_root.move_child(_hands, _root.get_child_count() - 2))
	t.tween_property(_hands, "scale", Vector2.ONE * 1.05, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_hands, "position:y", 0.0, 0.16)
	t.parallel().tween_property(_hands, "modulate", Color.WHITE, 0.16)
	t.tween_interval(0.12)
	# ...and the grip: the fingers snap shut a little past their pose, the logo is pulled back, then they settle.
	for k: int in 4:
		t.parallel().tween_property(_fingers[k], "rotation_degrees", -OPEN_DEG[k] * 0.12, 0.09).set_delay(0.015 * k).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(_base, "scale", Vector2.ONE * 0.985, 0.1)
	t.tween_property(_hands, "scale", Vector2.ONE, 0.1)
	for k: int in 4:
		t.parallel().tween_property(_fingers[k], "rotation_degrees", 0.0, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_base, "scale", Vector2.ONE * 0.99, 0.1)
	await t.finished
	if not _here(run):
		return
	var home: Vector2 = _root.position
	var j: Tween = _root.create_tween()
	for off: Vector2 in [Vector2(4, -2), Vector2(-3, 2), Vector2(1, 1), Vector2.ZERO]:
		j.tween_property(_root, "position", home + off, 0.04)
	await get_tree().create_timer(0.35).timeout
	if not _here(run):
		return
	# The eyes flash open.
	_eyes.modulate = Color(3.0, 2.6, 1.6, 1.0)
	var e: Tween = _eyes.create_tween()
	e.tween_property(_eyes, "modulate", Color.WHITE, 0.35)
	await e.finished


## Later visits to the menu in the same run: he holds the logo already, eyes lit.
func _held(run: int) -> void:
	_root.move_child(_hands, _root.get_child_count() - 2)
	_hands.scale = Vector2.ONE
	_hands.position = Vector2.ZERO
	_hands.modulate = Color.WHITE
	for k: int in 4:
		_fingers[k].rotation_degrees = 0.0
	_eyes.modulate = Color.WHITE
	_eyes_alive(run)


## The eyes once he holds the logo (Marko 2026-11-12): their glow breathes, and they blink now and then
## (sometimes twice); _look has them follow the mouse.
func _eyes_alive(run: int) -> void:
	var glow: Tween = _eyes.create_tween().set_loops()
	glow.tween_property(_eyes, "modulate", Color(1.35, 1.2, 1.0), 1.6).set_trans(Tween.TRANS_SINE)
	glow.tween_property(_eyes, "modulate", Color.WHITE, 1.6).set_trans(Tween.TRANS_SINE)
	while _here(run):
		await get_tree().create_timer(randf_range(2.5, 6.0)).timeout
		if not _here(run):
			return
		for i: int in (2 if randf() < 0.25 else 1):
			var b: Tween = _eyes.create_tween()
			b.tween_property(_eyes, "scale:y", 0.08, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			b.tween_property(_eyes, "scale:y", 1.0, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			await b.finished
			if not _here(run):
				return


## The eyes lean a few pixels toward the mouse.
func _look() -> void:
	var side: float = _root.size.x
	var centre: Vector2 = _root.global_position + _eyes.pivot_offset
	var d: Vector2 = get_global_mouse_position() - centre
	var want: Vector2 = d.normalized() * minf(d.length() / 300.0, 1.0) * side * 0.012
	_eyes.position = _eyes.position.lerp(want, 0.12)
