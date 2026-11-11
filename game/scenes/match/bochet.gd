class_name Bochet
extends Node3D
## Evil Bochet, the monster that holds the table (the review of 2026-11-09; chosen with Marko through the
## mockups of 10 and 11 November 2026). Its two hands hold the long edges on the viewer's half and walk
## aside, finger by finger, from the balls, stages and cores that come near; with no room left on top a
## hand holds the rim from outside, its claws over the edge. Its eyes look up from under the near edge,
## turned to the camera and out from the table as far as it takes to see them both, and watch the ball that
## rolls or the hero whose turn it is. Before the first turn it is not there; when the first turn begins
## its eyes open and its hands come up out of the dark onto the edges. A move timer under five seconds
## makes a hand drum on the edge. For now a ball that leaves the table drops into the dark.
##
## It belongs to the viewer: drawn on their side, it changes nothing the rules or the physics see. It is
## built for the blue seat (the near edge at +z) and the whole node turns half round for a viewer on red.
## Settings → Quality and effects switches it off; then the table keeps its slab (Arena.sink_table).

## The hand model (made in Blender: four fingers, 20 bones, its colours in the vertices), in the shared data
## folder (CardDb.data_dir).
const MODEL_PATH: String = "models/bochet_hand.glb"
## The match's home view with Bochet there: a little further out and higher than without him (0.13, 1.32), so
## that his eyes show whole above the cards in hand at the bottom of the screen (Marko 2026-11-11).
const VIEW_NEAR_BIAS: float = 0.16
const VIEW_ZOOM: float = 1.41
const RIM := Color("7d4dff")
const EYE := Color("ffc61a")
const IRIS := Color("fff2a8")
const PUPIL := Color("140a05")
const LID := Color("0b0908")
const BROW := Color("4a2d8a")

## The four finger proxies along the edge, this far apart.
const FINGER_GAP: float = 1.12
## Where along its edge a hand holds, and the stretch it may walk in: fractions of the table's half depth,
## from the middle towards the viewer.
const HOME: float = 0.6
const WALK_FROM: float = 0.42
const WALK_TO: float = 0.86
## A hand keeps CLEAR along the edge from a ball, stage hex or core that lies within NEAR_EDGE of its edge.
const CLEAR: float = 3.0
const NEAR_EDGE: float = 4.6
## Holding the rim from outside, its claws over the edge, a hand keeps RIM_CLEAR along the edge from a ball
## that lies within RIM_REACH of the edge (a stage or core under the claws is fine, Marko 2026-11-10/11).
const RIM_CLEAR: float = 2.6
const RIM_REACH: float = 2.6
## Balls this close to the ends of the table are on a start strip: no hand holds there.
const STRIP_MARGIN: float = 2.5
## At most this far in one roll of the fingers.
const STEP_MOST: float = 2.2
## Out of sight below the table, before the first turn.
const BELOW: float = -8.0
## The eyes under the near edge: this far down; this far out from the edge seen from the home view and
## from a view turned away from it (A2); never further out than the last.
const EYES_DOWN: float = -1.5
const EYES_NEAR: float = 1.5
const EYES_TURNED: float = 3.5
const EYES_FURTHEST: float = 8.0
## A move timer under DRUM_FROM seconds makes a hand drum on the edge, under DRUM_FAST twice as often.
const DRUM_FROM: float = 5.0
const DRUM_FAST: float = 2.0
## A ball off the table drops DROP_DEPTH into the dark in DROP_TIME seconds, and is gone from sight.
const DROP_DEPTH: float = 11.0
const DROP_TIME: float = 0.75

## Faceted and rim-lit, coloured by the model's vertices; whatever hangs below the table fades into the dark.
const SKIN_SHADER: String = """shader_type spatial;
render_mode cull_disabled, depth_draw_always;
uniform vec3 rim : source_color;
uniform float rim_amt = 0.5;
uniform float fade_a = -0.4;
uniform float fade_b = -4.5;
varying float wy;
varying vec3 vcol;
void vertex() {
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	// The file carries the colours sRGB-encoded.
	vcol = pow(COLOR.rgb, vec3(2.2));
}
void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) {
		n = -n;
	}
	NORMAL = n;
	float fade = smoothstep(fade_a, fade_b, wy);
	ALBEDO = vcol * (1.0 - fade);
	ROUGHNESS = 0.75;
	SPECULAR = 0.25 * (1.0 - fade);
	ALPHA = 1.0;
	float lum = dot(vcol, vec3(0.3, 0.6, 0.1));
	float f = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.0);
	EMISSION = (rim * f * rim_amt * (1.0 - clamp(lum * 2.0, 0.0, 1.0)) + vcol * 0.25) * (1.0 - fade);
}
"""

static var _skin_shader: Shader


## One hand on a long edge: side -1 the left one, +1 the right one, in the blue seat's view.
class Hand extends Node3D:
	var side: float = 1.0
	## Four proxies the walk moves: a lifted tip (each one's child) lifts that finger, a finger ahead of the
	## hand swings it ahead. The bones follow them every frame (Bochet._pose).
	var fingers: Array[Node3D] = []
	var body: Node3D
	var turn: Node3D
	var pitch: Node3D
	var skel: Skeleton3D
	## 1: off the top, holding the rim from outside (and so it waits below the table before the first turn).
	var hang: float = 0.0
	## With hang: the fingers stand straight up, the hand flat against the table's side.
	var straight: float = 0.0
	## Where along the edge it holds, and where it would rather hold.
	var at_z: float = 0.0
	var home_z: float = 0.0
	## Walking, sliding, drumming, letting go or coming back: nothing else starts meanwhile.
	var busy: bool = false
	## Holding the rim from outside (or on its way there).
	var hanging: bool = false
	## Let go of the edge, down in the dark.
	var sunk: bool = false
	## What is moving it now (Bochet._tw), so that a jump (a replay going back) can stop it all.
	var tweens: Array[Tween] = []


var _arena: Arena
var _cam: OrbitCamera
var _model_path: String = ""
var _skin_mat: ShaderMaterial
## Half the table's size (x across, z along).
var _ext := Vector2.ZERO
var _hands: Array[Hand] = []
var _eyes: Node3D
var _lids: Node3D
var _irises: Array[Node3D] = []
var _pupils: Array[Node3D] = []
## On the table (from the first turn on), and still on its way up.
var _shown: bool = false
var _entering: bool = false
var _ticked: bool = false
var _entry: Tween
var _drum_wait: float = 0.0
## The eyes: where they look (in their own plane), how wide the pupils are, the blink, and shut (1).
var _look := Vector2(0, 0.18)
var _wide: float = 0.22
var _blink_in: float = 1.7
var _blink: float = 0.0
var closed: float = 1.0
var _eyes_placed: bool = false
## Balls off the table, dropping into the dark: id -> seconds since they left it.
var _drops: Dictionary[String, float] = {}


## Bochet for this table, seen from the red seat or the blue one; null when its model is not in the data
## folder (the table then keeps its slab).
static func make(data_dir: String, arena: Arena, cam: OrbitCamera, red_seat: bool) -> Bochet:
	var path: String = data_dir.path_join(MODEL_PATH)
	if not FileAccess.file_exists(path):
		return null
	var b := Bochet.new()
	b.name = "Bochet"
	b._arena = arena
	b._cam = cam
	b._model_path = path
	b.rotation.y = PI if red_seat else 0.0
	return b


func _ready() -> void:
	_ext = _arena.extent() * 0.5
	for side: float in [-1.0, 1.0]:
		var h: Hand = _make_hand(side)
		add_child(h)
		_hands.append(h)
	_eyes = _make_eyes()
	add_child(_eyes)
	_snap(false)


## Every frame, from the match: the state, the balls, and the seconds left on a move timer of a player at
## this screen (INF when none runs).
func tick(delta: float, state: GameState, bodies: Dictionary[String, BallBody], clock_left: float) -> void:
	var want: bool = state.turn >= 1
	if want != _shown:
		# The first turn beginning in front of the viewer brings it up; a match carried on, a replay jumping
		# or a guest joining finds it there (or not) at once.
		if want and _ticked:
			_enter()
		else:
			_snap(want)
	_ticked = true
	if not _shown:
		return
	for h: Hand in _hands:
		_pose(h)
	_place_eyes(delta)
	_drive_eyes(delta, state, bodies)
	if _entering:
		return
	for h: Hand in _hands:
		_keep_clear(h, state, bodies)
	_drum(delta, clock_left)


# --- the hands -------------------------------------------------------------------------------------

func _make_hand(side: float) -> Hand:
	var h := Hand.new()
	h.name = "Hand" + ("Right" if side > 0.0 else "Left")
	h.side = side
	for k: int in 4:
		var fin := Node3D.new()
		fin.position.z = (k - 1.5) * FINGER_GAP
		h.add_child(fin)
		fin.add_child(Node3D.new())
		h.fingers.append(fin)
	h.body = Node3D.new()
	h.add_child(h.body)
	var mirror := Node3D.new()
	mirror.scale = Vector3(side, 1, 1)
	h.body.add_child(mirror)
	h.turn = Node3D.new()
	h.turn.rotation.y = PI * 0.5
	h.turn.position = Vector3(0.3, 1.15, 0)
	mirror.add_child(h.turn)
	# The wrist is 2.7 behind the knuckles: the hand turns about it.
	h.pitch = Node3D.new()
	h.pitch.position = Vector3(0, 0, 2.7)
	h.turn.add_child(h.pitch)
	var unshift := Node3D.new()
	unshift.position = Vector3(0, 0, -2.7)
	h.pitch.add_child(unshift)
	var model: Node3D = _model()
	unshift.add_child(model)
	var skels: Array[Node] = []
	_find(model, "Skeleton3D", skels)
	if not skels.is_empty():
		h.skel = skels[0] as Skeleton3D
	return h


func _model() -> Node3D:
	var doc := GLTFDocument.new()
	var gs := GLTFState.new()
	if doc.append_from_file(_model_path, gs) != OK:
		push_warning("Bochet: cannot read " + _model_path)
		return Node3D.new()
	var model := doc.generate_scene(gs) as Node3D
	if model == null:
		return Node3D.new()
	if _skin_mat == null:
		_skin_mat = _skin()
	var meshes: Array[Node] = []
	_find(model, "MeshInstance3D", meshes)
	for n: Node in meshes:
		var mi := n as MeshInstance3D
		mi.material_override = _skin_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return model


static func _skin() -> ShaderMaterial:
	if _skin_shader == null:
		_skin_shader = Shader.new()
		_skin_shader.code = SKIN_SHADER
	var m := ShaderMaterial.new()
	m.shader = _skin_shader
	m.render_priority = 3
	m.set_shader_parameter("rim", RIM)
	m.set_shader_parameter("rim_amt", 0.55)
	return m


static func _find(n: Node, cls: String, into: Array[Node]) -> void:
	if n.is_class(cls):
		into.append(n)
	for c: Node in n.get_children():
		_find(c, cls, into)


## Turns a bone by `angle` about a model-space axis (x: a positive angle lifts a finger), after an optional
## second turn about another axis (the finger's sideways swing).
static func bone(skel: Skeleton3D, bone_name: String, angle: float, axis: Vector3 = Vector3.RIGHT, angle2: float = 0.0, axis2: Vector3 = Vector3.UP) -> void:
	var i: int = skel.find_bone(bone_name)
	if i < 0:
		return
	var g: Basis = skel.get_bone_global_rest(i).basis.orthonormalized()
	var q := Quaternion(skel.get_bone_rest(i).basis.orthonormalized())
	if angle2 != 0.0:
		q = q * Quaternion((g.inverse() * axis2).normalized(), angle2)
	q = q * Quaternion((g.inverse() * axis).normalized(), angle)
	skel.set_bone_pose_rotation(i, q)


## The hand over its edge, its claws on the table, each finger lifted or swung as its proxy is; or off the
## top towards holding the rim from outside (hang).
func _pose(h: Hand) -> void:
	if h.skel == null:
		return
	if h.hang > 0.001:
		_pose_hang(h)
		return
	h.pitch.rotation.x = 0.0
	h.turn.position = Vector3(0.3, 1.15, 0)
	bone(h.skel, "arm1", 1.15)
	bone(h.skel, "arm2", 0.25)
	for k: int in 4:
		var fin: Node3D = h.fingers[k]
		var tip := fin.get_child(0) as Node3D
		var lift: float = clampf(maxf(-h.side * tip.rotation.z / 0.85, fin.position.y / 0.9 * 0.6), 0.0, 1.0)
		var rel: float = fin.position.z - (k - 1.5) * FINGER_GAP - h.body.position.z
		var i: int = 3 - k
		bone(h.skel, "f%d_1" % i, 0.12 + 0.8 * lift, Vector3.RIGHT, atan(rel / 2.6))
		bone(h.skel, "f%d_2" % i, -0.45 + 0.3 * lift)
		bone(h.skel, "f%d_3" % i, -0.45 + 0.25 * lift)


## Holding the rim from outside: the hand upright against the table's side, palm to it, only the claws
## hooked over; with straight the fingers stand straight up, the hand flat.
func _pose_hang(h: Hand) -> void:
	var k: float = h.hang
	h.pitch.rotation.x = PI * 0.5 * k
	h.turn.position = Vector3(lerpf(0.3, -2.25, k), lerpf(1.15, -3.3, k), 0)
	bone(h.skel, "arm1", lerpf(1.15, 0.1, k))
	bone(h.skel, "arm2", lerpf(0.25, 0.0, k))
	var stf: float = h.straight
	for i: int in 4:
		bone(h.skel, "f%d_1" % i, lerpf(0.12, lerpf(0.0, 0.06, stf), k), Vector3.RIGHT, (i - 1.5) * 0.05 * stf)
		bone(h.skel, "f%d_2" % i, lerpf(-0.45, lerpf(-0.9, 0.0, stf), k))
		bone(h.skel, "f%d_3" % i, lerpf(-0.45, lerpf(-0.65, 0.0, stf), k))


## Each hand keeps off whatever lies under it (Marko 2026-11-10/11): to the nearest free stretch of its
## edge within the walk, finger by finger, never walking past a ball. With no room on top it holds the rim
## from outside, its claws over the edge, where no ball lies by the rim for them to touch; along the outside
## to room on top when it comes free, and back up there. With no such place on the rim either it lets go
## of the edge into the dark, and comes back up the way it came at the start when there is room again.
func _keep_clear(h: Hand, state: GameState, bodies: Dictionary[String, BallBody]) -> void:
	if h.busy:
		return
	var lo: float = _ext.y * WALK_FROM
	var hi: float = _ext.y * WALK_TO
	var blocks: PackedFloat32Array = _blocks(h.side, state, bodies)
	var rim: PackedFloat32Array = _rim_balls(h.side, bodies)
	if h.sunk:
		var up_top: float = free_spot(h.home_z, blocks, lo, hi)
		if up_top != INF:
			_come_back(h, up_top, true)
			return
		var up_rim: float = free_spot(h.at_z, rim, lo, hi, RIM_CLEAR)
		if up_rim != INF:
			_come_back(h, up_rim, false)
		return
	if not h.hanging:
		var go: float = reach_spot(h.at_z, h.home_z, blocks, lo, hi)
		if go != INF:
			if absf(go - h.at_z) > 0.1:
				_walk(h, clampf(go - h.at_z, -STEP_MOST, STEP_MOST))
			return
		# No room on top: onto the outside of the rim where it is, or away into the dark.
		if clear_of(h.at_z, rim, RIM_CLEAR):
			_hang(h)
		else:
			_let_go(h)
		return
	var top: float = free_spot(h.home_z, blocks, lo, hi)
	if top != INF:
		# Room on top again: along the outside to it and up, or round under the table.
		if absf(top - h.at_z) <= 0.1:
			_unhang(h)
		elif path_clear(h.at_z, top, rim, RIM_CLEAR):
			_slide(h, top - h.at_z)
		else:
			_let_go(h)
		return
	if not clear_of(h.at_z, rim, RIM_CLEAR):
		_let_go(h)


## The nearest place to `home` within [lo, hi] at least `clear` from every block, trying upwards first at
## each distance; INF when there is none.
static func free_spot(home: float, blocks: PackedFloat32Array, lo: float, hi: float, clear: float = CLEAR) -> float:
	for i: int in 40:
		for sgn: float in [1.0, -1.0]:
			var c: float = home + sgn * i * 0.4
			if c >= lo and c <= hi and clear_of(c, blocks, clear):
				return c
	return INF


## Where a hand at `at` goes along its edge without passing anything: as near `home` as the free stretch it
## is in allows; out of the way first when something has come onto it; INF when there is no room at all.
static func reach_spot(at: float, home: float, blocks: PackedFloat32Array, lo: float, hi: float, clear: float = CLEAR) -> float:
	if at < lo - 0.01 or at > hi + 0.01 or not clear_of(at, blocks, clear):
		return free_spot(at, blocks, lo, hi, clear)
	var a: float = lo
	var b: float = hi
	for bz: float in blocks:
		if bz <= at:
			a = maxf(a, bz + clear)
		else:
			b = minf(b, bz - clear)
	return clampf(home, a, b)


static func clear_of(z: float, blocks: PackedFloat32Array, clear: float = CLEAR) -> bool:
	for bz: float in blocks:
		if absf(bz - z) < clear:
			return false
	return true


## Nothing within `clear` of the way from a to b.
static func path_clear(a: float, b: float, blocks: PackedFloat32Array, clear: float) -> bool:
	for bz: float in blocks:
		if bz > minf(a, b) - clear and bz < maxf(a, b) + clear:
			return false
	return true


## Where along a hand's edge lies a ball the claws over the rim would touch.
func _rim_balls(side: float, bodies: Dictionary[String, BallBody]) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var edge: float = side * _ext.x
	for b: BallBody in bodies.values():
		if not b.visible or not b.in_play() or b.motion == BallBody.Motion.OUT:
			continue
		var p: Vector3 = to_local(b.global_position)
		if absf(p.x - edge) < RIM_REACH:
			out.append(p.z)
	return out


## Where along a hand's edge (its z) lies something it must not rest on: balls in play on the table, the
## hexes of placed stages, cores on the field, all within NEAR_EDGE of that edge.
func _blocks(side: float, state: GameState, bodies: Dictionary[String, BallBody]) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var edge: float = side * _ext.x
	for b: BallBody in bodies.values():
		if not b.visible or not b.in_play() or b.motion == BallBody.Motion.OUT:
			continue
		var p: Vector3 = to_local(b.global_position)
		if absf(p.x - edge) < NEAR_EDGE and absf(p.z) < _ext.y - STRIP_MARGIN:
			out.append(p.z)
	for st: StageState in state.stages:
		if not st.placed:
			continue
		for c: Vector2i in st.footprint():
			var at: Vector3 = _on_table(c)
			if absf(at.x - edge) < NEAR_EDGE:
				out.append(at.z)
	for core: CoreState in state.cores:
		if core.place == CoreState.ON_FIELD:
			var cat: Vector3 = _on_table(core.hex)
			if absf(cat.x - edge) < NEAR_EDGE:
				out.append(cat.z)
	return out


func _on_table(a: Vector2i) -> Vector3:
	return to_local(_arena.to_global(_arena.hex_center(a)))


## One roll of the fingers along the edge: each finger in turn lifts, goes dz and taps down; the back of
## the hand glides along under them.
func _walk(h: Hand, dz: float) -> void:
	h.busy = true
	_tw(h, h.body).tween_property(h.body, "position:z", h.body.position.z + dz, 0.38).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var order: Array[Node3D] = []
	order.assign(h.fingers)
	if dz > 0.0:
		order.reverse()
	for i: int in order.size():
		var fin: Node3D = order[i]
		var tip := fin.get_child(0) as Node3D
		var t: Tween = _tw(h, fin)
		t.tween_interval(0.06 * i)
		t.tween_property(tip, "rotation:z", -h.side * 0.6, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(fin, "position:y", 0.3, 0.07)
		t.tween_property(fin, "position:z", fin.position.z + dz, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(tip, "rotation:z", 0.0, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(fin, "position:y", 0.0, 0.05)
	var done: Tween = _tw(h, h)
	done.tween_interval(0.06 * (order.size() - 1) + 0.26)
	done.tween_callback(func() -> void:
		h.at_z += dz
		h.busy = false)


## Along the outside of the rim, the whole hand at once.
func _slide(h: Hand, dz: float) -> void:
	h.busy = true
	var t: Tween = _tw(h, h).set_parallel(true)
	t.tween_property(h.body, "position:z", h.body.position.z + dz, 0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for fin: Node3D in h.fingers:
		t.tween_property(fin, "position:z", fin.position.z + dz, 0.34).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.chain().tween_callback(func() -> void:
		h.at_z += dz
		h.busy = false)


## A tween on `node` (the hand or a part of it) that _snap can stop.
func _tw(h: Hand, node: Node) -> Tween:
	h.tweens = h.tweens.filter(func(t: Tween) -> bool: return t.is_valid())
	var t: Tween = node.create_tween()
	h.tweens.append(t)
	return t


## The whole hand along its edge at once, out of sight.
func _shift(h: Hand, z: float) -> void:
	var dz: float = z - h.at_z
	h.body.position.z += dz
	for fin: Node3D in h.fingers:
		fin.position.z += dz
	h.at_z = z


## Off the top onto the outside of the rim, the claws hooked over the edge.
func _hang(h: Hand) -> void:
	h.busy = true
	h.hanging = true
	var t: Tween = _tw(h, h)
	t.tween_property(h, "hang", 1.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func() -> void: h.busy = false)


## From the rim back over the top into the hold.
func _unhang(h: Hand) -> void:
	h.busy = true
	h.hanging = false
	_cam.shake(0.3, 0.3)
	var t: Tween = _tw(h, h)
	t.tween_property(h, "hang", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func() -> void: h.busy = false)


## Lets go of the edge the chosen way (Marko 2026-11-10): the fingers unhook, the hand stands flat against
## the table's side, and sinks into the dark.
func _let_go(h: Hand) -> void:
	h.busy = true
	h.hanging = true
	h.sunk = true
	var t: Tween = _tw(h, h)
	t.tween_property(h, "hang", 1.0, 0.16)
	t.parallel().tween_property(h, "straight", 1.0, 0.16)
	t.parallel().tween_property(h, "position:y", 1.0, 0.16)
	t.tween_interval(0.1)
	t.tween_property(h, "position:y", BELOW, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void: h.busy = false)


## Back up at z the way the hands come at the start of a match: up beside the table, upright and flat, the
## claws over the edge, and (on_top) over it into the hold; otherwise it stays holding the rim.
func _come_back(h: Hand, z: float, on_top: bool) -> void:
	h.busy = true
	_shift(h, z)
	var t: Tween = _tw(h, h)
	t.tween_property(h, "position:y", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.05)
	t.tween_property(h, "straight", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(h, "position:y", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if on_top:
		t.tween_interval(0.16)
		t.tween_property(h, "hang", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_callback(func() -> void:
		h.sunk = false
		h.hanging = not on_top
		h.busy = false)


## The move timer under DRUM_FROM seconds: the viewer's right hand drums on the edge (Marko 2026-11-11).
func _drum(delta: float, clock_left: float) -> void:
	_drum_wait -= delta
	var every: float = drum_every(clock_left)
	if every <= 0.0 or _drum_wait > 0.0:
		return
	var h: Hand = _hands[1]
	if h.busy or h.hang > 0.01:
		return
	_drum_wait = every
	h.busy = true
	for i: int in h.fingers.size():
		var fin: Node3D = h.fingers[i]
		var tip := fin.get_child(0) as Node3D
		var t: Tween = _tw(h, fin)
		t.tween_interval(0.06 * i)
		t.tween_property(tip, "rotation:z", -h.side * 0.6, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(fin, "position:y", 0.3, 0.07)
		t.tween_property(tip, "rotation:z", 0.0, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(fin, "position:y", 0.0, 0.05)
	var done: Tween = _tw(h, h)
	done.tween_interval(0.06 * (h.fingers.size() - 1) + 0.12)
	done.tween_callback(func() -> void: h.busy = false)


## Seconds between two rolls of the fingers with `left` seconds on the clock; 0 when no drumming.
static func drum_every(left: float) -> float:
	if left > DRUM_FROM or left <= 0.05:
		return 0.0
	return 0.45 if left <= DRUM_FAST else 0.9


# --- coming up ----------------------------------------------------------------------------------------

## At once: on the edges with its eyes open (shown), or out of sight below the table with its eyes shut.
func _snap(shown: bool) -> void:
	if _entry != null and _entry.is_valid():
		_entry.kill()
	_shown = shown
	_entering = false
	closed = 0.0 if shown else 1.0
	_eyes.visible = shown
	_eyes_placed = false
	for h: Hand in _hands:
		for t: Tween in h.tweens:
			if t.is_valid():
				t.kill()
		h.tweens.clear()
		h.position = Vector3(h.side * _ext.x, 0.0 if shown else BELOW, _ext.y * HOME)
		h.hang = 0.0 if shown else 1.0
		h.straight = 0.0 if shown else 1.0
		h.home_z = h.position.z
		h.at_z = h.home_z
		h.body.position.z = 0.0
		for k: int in h.fingers.size():
			var fin: Node3D = h.fingers[k]
			fin.position = Vector3(0, 0, (k - 1.5) * FINGER_GAP)
			(fin.get_child(0) as Node3D).rotation.z = 0.0
		h.busy = false
		h.hanging = not shown
		h.sunk = not shown
		h.visible = shown
		_pose(h)


## The first turn begins: the eyes open; a moment later both hands come up beside the table, upright and
## flat, fold over the edges and close into their hold (entrance P2c, Marko 2026-11-10).
func _enter() -> void:
	_snap(false)
	_shown = true
	_entering = true
	_eyes.visible = true
	_entry = create_tween()
	_entry.tween_property(self, "closed", 0.0, 0.16)
	_entry.tween_interval(0.55)
	_entry.tween_callback(_raise_hands)
	_entry.tween_interval(0.22 + 0.05 + 0.12 + 0.16 + 0.3 + 0.1)
	_entry.tween_callback(func() -> void: _entering = false)


func _raise_hands() -> void:
	for h: Hand in _hands:
		h.visible = true
		h.busy = true
		var t: Tween = _tw(h, h)
		t.tween_property(h, "position:y", 1.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_interval(0.05)
		t.tween_property(h, "straight", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.parallel().tween_property(h, "position:y", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		t.tween_callback(_cam.shake.bind(0.35, 0.3))
		t.tween_interval(0.16)
		t.tween_property(h, "hang", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_callback(_cam.shake.bind(0.35, 0.3))
		t.tween_callback(func() -> void:
			h.sunk = false
			h.hanging = false
			h.busy = false)


# --- the eyes -----------------------------------------------------------------------------------------

## Two flat round eyes in a plane that leans back (the lids node, which also squashes to blink), each with
## an iris and a slit pupil that slide inside it, a slanted lid across the top, lower towards the middle,
## and a thin brow under the lid (the O8 eyes).
func _make_eyes() -> Node3D:
	var root := Node3D.new()
	root.name = "Eyes"
	_lids = Node3D.new()
	_lids.rotation.x = -0.95
	root.add_child(_lids)
	var lo: float = 0.3
	var slope: float = 0.36
	for e: float in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(e * 1.45, 0.1, 0)
		_lids.add_child(eye)
		_flat(eye, disc(Vector2.ZERO, 1.32, 26), Color(EYE, 0.22), -0.03)
		_flat(eye, disc(Vector2.ZERO, 1.0, 26), EYE, 0.0)
		_irises.append(_flat(eye, disc(Vector2.ZERO, 0.6, 20), IRIS, 0.02))
		_pupils.append(_flat(eye, lens(Vector2(0, -0.62), Vector2(0, 0.62), 0.5, 7), PUPIL, 0.04))
		var lid := PackedVector2Array([Vector2(-1.7 * e, lo - slope * 1.7), Vector2(1.7 * e, lo + slope * 1.7),
			Vector2(1.7 * e, 1.9), Vector2(-1.7 * e, 1.9)])
		# Only where the eye is: the part of the eye's round above the line.
		var cut: Array[PackedVector2Array] = Geometry2D.intersect_polygons(disc(Vector2.ZERO, 1.36, 26), lid)
		if not cut.is_empty():
			lid = cut[0]
		_flat(eye, lid, LID, 0.06)
		_flat(eye, PackedVector2Array([Vector2(-1.25 * e, lo - slope * 1.25 - 0.09), Vector2(1.25 * e, lo + slope * 1.25 - 0.09),
			Vector2(1.25 * e, lo + slope * 1.25 + 0.05), Vector2(-1.25 * e, lo - slope * 1.25 + 0.05)]), BROW, 0.07)
	return root


## A flat polygon (a fan from its first point) in the plane of `parent`, `z` in front of it.
static func _flat(parent: Node3D, pts: PackedVector2Array, col: Color, z: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(1, pts.size() - 1):
		st.add_vertex(Vector3(pts[0].x, pts[0].y, 0))
		st.add_vertex(Vector3(pts[i].x, pts[i].y, 0))
		st.add_vertex(Vector3(pts[i + 1].x, pts[i + 1].y, 0))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = col
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position.z = z
	parent.add_child(mi)
	return mi


static func disc(c: Vector2, r: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i: int in n:
		var a: float = TAU * i / n
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


## A lens between a and b: two arcs `depth` deep, one each side.
static func lens(a: Vector2, b: Vector2, depth: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array([a])
	out.append_array(_arc(a, b, depth, n))
	out.append(b)
	out.append_array(_arc(b, a, depth, n))
	return out


static func _arc(a: Vector2, b: Vector2, depth: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	var d: Vector2 = b - a
	var perp: Vector2 = Vector2(d.y, -d.x).normalized()
	for i: int in range(1, n):
		var t: float = float(i) / n
		out.append(a.lerp(b, t) + perp * depth * sin(PI * t))
	return out


## A2 (Marko 2026-11-11): the eyes stay by the viewer's seat and turn to the camera, and stand out from the
## edge as far as it takes for the camera to see both eyes and the mouth's place whole past the table:
## close from the home view, further out as the view turns away. Out at once, back in eased.
func _place_eyes(delta: float) -> void:
	var view: Camera3D = get_viewport().get_camera_3d()
	if view == null:
		return
	var from: Vector3 = to_local(view.global_position)
	var want: float = eyes_out(from)
	while want < EYES_FURTHEST and not eyes_seen(Vector3(_eyes.position.x, EYES_DOWN, _ext.y + want), from, _ext):
		want += 0.2
	var now: float = _eyes.position.z - _ext.y
	if not _eyes_placed or want > now:
		now = want
	else:
		now = lerpf(now, want, clampf(delta * 10.0, 0.0, 1.0))
	_eyes_placed = true
	_eyes.position = Vector3(_eyes.position.x, EYES_DOWN, _ext.y + now)
	var to: Vector3 = from - _eyes.position
	_eyes.rotation.y = atan2(to.x, to.z)
	_lids.rotation.x = -atan2(to.y, Vector2(to.x, to.z).length())


## How far out from the near edge the eyes would stand for a camera at `from` (in Bochet's own space):
## EYES_NEAR seen from the home side, EYES_TURNED as the view turns away from it.
static func eyes_out(from: Vector3) -> float:
	return lerpf(EYES_NEAR, EYES_TURNED, smoothstep(0.15, 0.9, absf(atan2(from.x, from.z))))


## Whether a camera at `from` sees the eyes centred at `at` whole, and the mouth's place under them, past a
## table of half size `ext`: no line from it to the rim of an eye or to the mouth's ends crosses the table
## top, and nothing of the face is under the table.
static func eyes_seen(at: Vector3, from: Vector3, ext: Vector2) -> bool:
	var flat := Vector3(from.x - at.x, 0, from.z - at.z).normalized()
	var right := Vector3(flat.z, 0, -flat.x)
	var el: float = atan2(from.y - at.y, Vector2(from.x - at.x, from.z - at.z).length())
	var up: Vector3 = Vector3.UP * cos(el) - flat * sin(el)
	var face: Array[Vector3] = [up * -1.25 + right * 3.2, up * -1.25 - right * 3.2, up * -2.45]
	for fp: Vector3 in face:
		var mp: Vector3 = at + fp
		if from.y <= mp.y or _over_table(mp, from, ext):
			return false
		if absf(mp.x) < ext.x and absf(mp.z) < ext.y:
			return false
	var rims: Array[Vector3] = [right * -1.35, Vector3.ZERO, right * 1.35, up * 1.35, up * -1.35]
	for e: float in [-1.0, 1.0]:
		for rim: Vector3 in rims:
			var pt: Vector3 = at + right * (e * 1.45) + rim
			if from.y <= pt.y or _over_table(pt, from, ext):
				return false
	return true


## The line from a point below the table top up to the camera crosses the table top.
static func _over_table(pt: Vector3, from: Vector3, ext: Vector2) -> bool:
	var hit: Vector3 = pt.lerp(from, (0.0 - pt.y) / (from.y - pt.y))
	return absf(hit.x) < ext.x + 0.3 and absf(hit.z) < ext.y + 0.3


## Where the eyes look: at a ball that rolls (pupils wide), else at the ball of the hero whose turn it is;
## and they blink now and then.
func _drive_eyes(delta: float, state: GameState, bodies: Dictionary[String, BallBody]) -> void:
	var want := Vector2(0, 0.18)
	var busy: bool = false
	for b: BallBody in bodies.values():
		if b.visible and b.motion == BallBody.Motion.MOVING:
			want = _look_at(b.global_position)
			busy = true
			break
	if not busy:
		var id: String = str(state.active.get(state.to_act, ""))
		if bodies.has(id):
			var wb: BallBody = bodies[id]
			if wb.visible:
				want = _look_at(wb.global_position)
	_look = _look.lerp(want, clampf(delta * 9.0, 0.0, 1.0))
	_wide = lerpf(_wide, 0.5 if busy else 0.22, clampf(delta * 8.0, 0.0, 1.0))
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_in = 2.6
		_blink = 0.2
	_blink = maxf(0.0, _blink - delta)
	var shut: float = 1.0 - absf(_blink - 0.1) / 0.1 if _blink > 0.0 else 0.0
	_lids.scale.y = lerpf(1.0, 0.06, shut) * lerpf(1.0, 0.05, closed)
	for i: int in _irises.size():
		_irises[i].position = Vector3(_look.x * 0.8, _look.y * 0.8, 0.02)
		_pupils[i].position = Vector3(_look.x, _look.y, 0.04)
		_pupils[i].scale.x = _wide


## In the eyes' own plane: sideways is sideways, up is away from the camera.
func _look_at(p: Vector3) -> Vector2:
	var loc: Vector3 = _eyes.global_transform.affine_inverse() * p
	var d := Vector2(loc.x, -loc.z)
	return d.normalized() * 0.4 * clampf(d.length() / 6.0, 0.0, 1.0)


# --- balls off the table ------------------------------------------------------------------------------

## How far a ball's picture has dropped into the dark under the table (0 or less): off the table it falls
## DROP_DEPTH in DROP_TIME; back on the table (the rules put it on its strip) it is there at once. Only the
## picture: the ball itself lies where the physics has it.
func drop(id: String, pos: Vector3, delta: float) -> float:
	if _arena.area_at(_arena.to_local(pos)) != BallWorld.Area.VOID:
		_drops.erase(id)
		return 0.0
	var t: float = _drops.get(id, 0.0)
	t = minf(t + delta, DROP_TIME)
	_drops[id] = t
	return -DROP_DEPTH * (t / DROP_TIME) * (t / DROP_TIME)


## A ball that has dropped all the way: no longer to be seen.
func dropped(id: String) -> bool:
	var t: float = _drops.get(id, 0.0)
	return t >= DROP_TIME
