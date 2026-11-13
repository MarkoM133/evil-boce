class_name Bochet
extends Node3D
## Evil Bochet, the monster that holds the table (the review of 2026-11-09; chosen with Marko through the
## mockups of 10 and 11 November 2026). Its two hands hold the long edges on the viewer's half and walk
## aside, finger by finger, from the balls, stages and cores that come near; with no room left on top a
## hand holds the rim from outside, its claws over the edge. Its eyes look up from under the near edge,
## turned to the camera and out from the table as far as it takes to see them both, and watch the ball that
## rolls or the hero whose turn it is. Before the first turn it is not there; when the first turn begins
## its eyes open and its hands come up out of the dark onto the edges. A move timer under five seconds
## makes a hand drum on the edge.
##
## A ball that leaves the table is caught: by the hand that holds that edge, which rolls back into an open
## palm under the edge; two that leave close together land in one palm; with both hands busy a third drops
## into the dark; elsewhere a hand comes up from below; over the near end the mouth takes it. When the
## balls have stopped, the hand of the start zone brings each one back, palm down, the ball in its gathered
## fingertips, and holds it over its spot while its player chooses what the ring-out costs (damage is a
## squeeze and a shake). A ball the ring-out knocks out it keeps, and narrows its eyes. A ball that stops in
## a start zone is picked up where it stopped and carried to its spot.
##
## It belongs to the viewer: drawn on their side, it changes nothing the rules or the physics see. It moves
## only the pictures of the balls (BallView); the balls themselves are where the rules put them. It is built
## for the blue seat (the near edge at +z) and the whole node turns half round for a viewer on red.
## Settings → Quality and effects switches it off; then the table keeps its slab (Arena.sink_table).

## A ball its ring-out knocked out has gone into the dark with it: the match hides it now.
signal kept(id: String)

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
const BROW := Color("4a2d8a")
const MOUTH := Color("2a0509")
const TOOTH := Color("f3efe7")

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
## A hand coming up within EYES_ASIDE of the eyes, along the near edge, has them step EYES_ASIDE_TO aside.
const EYES_ASIDE: float = 5.6
const EYES_ASIDE_TO: float = 6.0
## A move timer under DRUM_FROM seconds makes a hand drum on the edge, under DRUM_FAST twice as often.
const DRUM_FROM: float = 5.0
const DRUM_FAST: float = 2.0
## The catching palm waits this far out from where the ball leaves and this far below the table top.
const CATCH_REACH: float = 2.4
const CATCH_DOWN: float = -0.3
## The hand that holds an edge catches a ball that leaves within this distance of it along the edge; further
## off a hand comes up from below.
const CATCH_ALONG: float = 9.0
## A second ball that leaves within this distance of the first lands in the same open palm.
const JOIN_ALONG: float = 2.4
## The returning hand's fingertips in its own space: where it holds the ball.
const TIPS := Vector3(-3.3, -1.8, 0)
## Over its spot the returning hand holds the ball this high while its player chooses (Marko 2026-11-10).
const HOLD_LIFT: float = 1.5
## How far the fingers of a catching palm turn in towards each other in a pinch.
const PINCH_SPLAY: float = 0.22
## The KO hole (KO4–KO6, Marko 2026-11-10): its rim and the dark in it, and the fingers that come up out
## of it (four round the ball, no palm or arm), faceted like the hands.
const HOLE_RIM := Color("5a37a8")
const HOLE_DARK := Color("040203")
const KO_SKIN := Color("1f1535")
const KO_NAIL := Color("e9dcbd")
const KO_NAIL_RIM := Color("ffd9a0")
## A finger of the KO hand, piece by piece: lengths, how far each piece keeps from the ball (its thick
## end), and the open pose (the finger's lean, then the bend at each joint), narrow and as wide as the hole
## has room for.
const WRAP_LENS: Array[float] = [0.8, 0.65, 0.45, 0.5, 0.475]
const WRAP_THICK: Array[float] = [0.47, 0.42, 0.37, 0.29, 0.14]
const WRAP_OPEN: Array[float] = [-0.22, 0.35, 0.4, 0.3, 0.18]
const WRAP_WIDE: Array[float] = [-0.4, 0.16, 0.22, 0.22, 0.14]
## The KO grip slows the game to this for this long, real time (Marko 2026-11-11: "Usporeno"; Settings →
## Slow motion).
const KO_SLOW_SCALE: float = 0.35
const KO_SLOW_TIME: float = 0.4
## Leaving at the end of a match, this much slower than the hands let go during it (Marko 2026-11-11: R4).
const LEAVE_SLOW: float = 1.55
## The eyes and the cards in hand (_drive_dodge): covered this long they go aside, clear this long they
## come back; they keep this many pixels off the cards and this far from the corners of the table.
const DODGE_AFTER: float = 0.3
const DODGE_BACK: float = 0.5
const DODGE_GAP: float = 6.0
const DODGE_CORNER: float = 2.5

enum Stage { CATCHING, UNDER, BACK, KO }

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

## The KO hand's pieces: one colour, faceted, rim-lit; below the table it fades into the dark round it.
const FLAT_SHADER: String = """shader_type spatial;
render_mode depth_draw_always;
uniform vec3 base : source_color;
uniform vec3 rim : source_color;
uniform float rim_amt = 0.6;
varying float wy;
void vertex() {
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
void fragment() {
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) {
		n = -n;
	}
	NORMAL = n;
	float fade = smoothstep(-0.4, -4.5, wy);
	ALBEDO = mix(base, vec3(0.012, 0.009, 0.008), fade);
	ROUGHNESS = 0.75;
	SPECULAR = 0.25;
	ALPHA = 1.0;
	float f = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 3.0);
	EMISSION = (rim * f * rim_amt + base * 0.1) * (1.0 - fade);
}
"""

static var _flat_shader: Shader


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
	## Rolled back over the wrist into an open palm under the edge (1), and that palm closed (close 1).
	var lean: float = 0.0
	var close: float = 0.0
	## Where along the edge it holds, and where it would rather hold.
	var at_z: float = 0.0
	var home_z: float = 0.0
	## Walking, sliding, drumming, letting go or coming back: nothing else starts meanwhile.
	var busy: bool = false
	## Holding the rim from outside (or on its way there).
	var hanging: bool = false
	## Let go of the edge, down in the dark.
	var sunk: bool = false
	## Taken off its edge to catch or bring back a ball: it comes back when that is done.
	var off: bool = false
	## A ball comes at its edge: its fingers are up ("up"), and it may be leaning back for it already.
	var gate: String = ""
	var leaning: bool = false
	var lean_from_z: float = 0.0
	var lean_tween: Tween
	## The balls in its palm, and whether that palm is still open for one more.
	var holding: Array = []
	var open_for: bool = false
	var joiners: int = 0
	## What is moving it now (Bochet._tw), so that a jump (a replay going back) can stop it all.
	var tweens: Array[Tween] = []


## A hand that comes up from below to catch a ball, or brings one back: palm up, or (palm_down) the hand of
## the start zone with the ball in its gathered fingertips.
class Claw extends Node3D:
	## Four proxies: rotation.z -0.7 open, 0.36 closed (Bochet._grip).
	var prox: Array[Node3D] = []
	var spin: Node3D
	var lean: Node3D
	var un: Node3D
	var flip: Node3D
	var tips: Node3D
	var skel: Skeleton3D
	## The fingertips together round what they hold (1), squeezing (more).
	var pinch: float = 0.0
	var palm_down: bool = false
	## Palm down: the fingers out flat, and the arm upright.
	var flat: float = 0.0
	var up: float = 0.0


## A ball whose picture Bochet has: being caught, under the table, or on its way back.
class Held extends RefCounted:
	var id: String = ""
	## Where the picture is, in Bochet's space, and whether it shows.
	var pos := Vector3.ZERO
	var shown: bool = true
	var stage: int = 0
	## Where it left the table, and where it is held.
	var at := Vector3.ZERO
	var hold := Vector3.ZERO
	## The edge hand it took, and the hand that brings it back.
	var hand: Hand
	var claw: Claw
	## Over its spot: where the hand hovers with it, and where it comes up from outside the edge.
	var hover := Vector3.ZERO
	var low := Vector3.ZERO
	## The ball keeps to the fingertips (Bochet._follow).
	var follow: Tween
	## Its ring-out knocked it out: it does not go back.
	var gone: bool = false
	## Its hit points when it left the table: less when it is set down is a squeeze (Bochet._hold_wait).
	var hp0: int = 0
	## Where the rules put the ball itself back (INF until they have): thrown on from there, the picture is
	## its own again.
	var spot := Vector3.INF


var _arena: Arena
var _cam: OrbitCamera
var _model_path: String = ""
var _skin_mat: ShaderMaterial
## Half the table's size (x across, z along).
var _ext := Vector2.ZERO
var _hands: Array[Hand] = []
var _claws: Array[Claw] = []
var _eyes: Node3D
var _lids: Node3D
var _jaw: Node3D
var _mouth: Node3D
var _irises: Array[MeshInstance3D] = []
var _pupils: Array[MeshInstance3D] = []
## On the table (from the first turn on), and still on its way up.
var _shown: bool = false
var _entering: bool = false
var _ticked: bool = false
var _entry: Tween
var _drum_wait: float = 0.0
## The eyes: where they look (in their own plane), how wide the pupils are, the blink, shut (1), narrowed (1).
var _look := Vector2(0, 0.18)
var _wide: float = 0.22
var _blink_in: float = 1.7
var _blink: float = 0.0
var closed: float = 1.0
var squint: float = 0.0
var _eyes_placed: bool = false
## The face aside along the near edge, and lifted (the mouth); how many hands have it aside now.
var face_x: float = 0.0
var face_dy: float = 0.0
var _aside_n: int = 0
## The match's state and balls, as of this frame.
var _state: GameState
var _bodies: Dictionary[String, BallBody] = {}
var _views: Dictionary[String, BallView] = {}
## Balls whose pictures it has.
var _held: Dictionary[String, Held] = {}
## Bringing balls back now.
var _returning: bool = false
## Bumped when it is all reset (_snap): animations under way stop at their next step.
var _gen: int = 0
## Its own tweens (the balls' pictures, the face), so that _snap can stop them.
var _tweens: Array[Tween] = []
## Balls going down a KO hole now, and the holes and hands of those (freed by _snap).
var _dying: Dictionary[String, bool] = {}
var _ko_nodes: Array[Node3D] = []
## The KO grip slows the game a moment (the match sets it from Settings → Slow motion), and whether it
## has the game slowed now (put right if Bochet goes in the middle of it).
var slow_ko: bool = true
var _slowing: bool = false
## Gone at the end of the match (leave): nothing more happens.
var _left: bool = false
## The eyes out of the way of the cards in hand (Marko 2026-11-11, mockup A): where the raised cards cover
## the screen (set_cover), how far along the near edge the eyes have slid aside and where they are going,
## the hand they made room for, and for how long they have been covered or clear.
var _cover := Rect2()
var _dodge_x: float = 0.0
var _dodge_want: float = 0.0
var _cover_used := Rect2()
var _covered_for: float = 0.0
var _clear_for: float = 0.0
## The side they go to the next time (-1 left, 1 right); 0 picks one by chance.
var dodge_side: float = 0.0


## Where the cards in hand cover the screen now, empty while the hand is down (from the match, each frame).
func set_cover(r: Rect2) -> void:
	_cover = r


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


## Every frame, from the match: the state, the balls and their pictures, and the seconds left on a move
## timer of a player at this screen (INF when none runs).
func tick(delta: float, state: GameState, bodies: Dictionary[String, BallBody], views: Dictionary[String, BallView], clock_left: float) -> void:
	_state = state
	_bodies = bodies
	_views = views
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
	for c: Claw in _claws:
		_pose_claw(c)
	_place_eyes(delta)
	_drive_dodge(delta)
	_drive_eyes(delta, state, bodies)
	if _entering or _left:
		return
	_watch()
	for h: Hand in _hands:
		if not h.off:
			_gate(h)
			_keep_clear(h, state, bodies)
	_drum(delta, clock_left)
	_bring_back()


## Whether it has this ball's picture now, where that is, and whether it shows.
func holds(id: String) -> bool:
	return _held.has(id)


func held_at(id: String) -> Vector3:
	return to_global(_held[id].pos)


func held_shown(id: String) -> bool:
	return _held[id].shown


## The ring-out knocked out a ball it has: it keeps it, and says so (kept) when it has taken it into the
## dark. False when it does not have that ball.
func keep(id: String) -> bool:
	if not _held.has(id):
		return false
	_held[id].gone = true
	return true


## The rules have just taken a ball off the table (its ring-out) and put the ball itself on its start spot;
## `from` is where it was, `hp` its hit points before. Gone over the edge, its picture is caught there (a
## ball that leaves the table alone ends its roll at once, so the rules have it back before it is seen
## off the table); stopped in a start zone, it is picked up where it lay. False when Bochet leaves it be.
func taken_off(id: String, from: Vector3, state: GameState, hp: int) -> bool:
	if not _shown or _entering or _held.has(id) or not _bodies.has(id):
		return false
	_state = state
	var loc: Vector3 = to_local(from)
	match _area(from):
		BallWorld.Area.VOID:
			_catch(id, loc, _bodies[id].radius(), hp)
			return true
		BallWorld.Area.STRIP:
			var target: Vector3 = to_local(_bodies[id].global_position)
			if Vector2(loc.x - target.x, loc.z - target.z).length() < 0.3:
				return false
			_pick_up(id, loc, target, hp)
			return true
	return false


## The match jumped (a replay going to another frame): every ball's picture is its own again at once, and
## those it was keeping are gone now (kept).
func reset() -> void:
	var gone: Array[String] = []
	for held: Held in _held.values():
		if held.gone or held.stage == Stage.KO:
			gone.append(held.id)
	_snap(_shown)
	for id: String in gone:
		kept.emit(id)


## Where on the table a point is: the map, a start strip, or off it all.
func _area(global: Vector3) -> BallWorld.Area:
	return _arena.area_at(_arena.to_local(global))


## Whether a hand is taking that ball at the edge right now (it has not gone under the table yet).
func catching(id: String) -> bool:
	return _held.has(id) and _held[id].stage == Stage.CATCHING


## Whether he can take a knocked-out hero's ball down a hole now (he is on the table, it is not in a hand).
func can_take(id: String) -> bool:
	return _shown and not _entering and not _left and not _held.has(id) and _bodies.has(id)


## A hero knocked out where its ball stands (not in a hand of his): a hole opens under the ball and his
## claws take it down (_ko_hole); `kept` when it is gone. False when he leaves it be (the match shatters it).
func ko_hole(id: String) -> bool:
	if not can_take(id):
		return false
	var b: BallBody = _bodies[id]
	var held := Held.new()
	held.id = id
	held.at = to_local(b.global_position)
	held.pos = held.at
	held.stage = Stage.KO
	_held[id] = held
	_dying[id] = true
	_ko_hole(held, b)
	return true


## Taking a knocked-out ball down now (a hole open, or one kept in a hand on its way into the dark).
func ko_busy() -> bool:
	if not _dying.is_empty():
		return true
	for held: Held in _held.values():
		if held.gone:
			return true
	return false


## The match is over (Marko 2026-11-11: N1, R4): the eyes shut and are gone, both hands let go of the edges
## the chosen way and sink into the dark, the right a moment after the left, all LEAVE_SLOW slower.
func leave() -> void:
	if not _shown or _left:
		return
	_left = true
	_entering = false
	if _entry != null and _entry.is_valid():
		_entry.kill()
	var s: float = LEAVE_SLOW
	var et: Tween = _btw()
	et.tween_property(self, "closed", 1.0, 0.3 * s)
	et.tween_callback(func() -> void: _eyes.visible = false)
	for h: Hand in _hands:
		if h.position.y < BELOW + 0.5:
			# Down in the dark already (caught a ball, or no room on its edge).
			continue
		_stop(h)
		h.busy = true
		var t: Tween = _tw(h, h)
		t.tween_interval(0.2 * s + (0.12 if h.side > 0.0 else 0.0))
		t.tween_property(h, "hang", 1.0, 0.16 * s)
		t.parallel().tween_property(h, "straight", 1.0, 0.16 * s)
		t.parallel().tween_property(h, "position:y", 1.0, 0.16 * s)
		t.tween_interval(0.1 * s)
		t.tween_property(h, "position:y", BELOW, 0.22 * s).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _exit_tree() -> void:
	# The KO grip's slow motion must not outlive him (the match left in the middle of it).
	if _slowing:
		Engine.time_scale = 1.0
		_slowing = false


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


## The hand over its edge, its claws on the table, each finger lifted or swung as its proxy is; rolled back
## over the wrist into an open palm under the edge (lean), that palm closed (close); or off the top towards
## holding the rim from outside (hang).
func _pose(h: Hand) -> void:
	if h.skel == null:
		return
	if h.hang > 0.001:
		_pose_hang(h)
		return
	var lean: float = h.lean
	h.pitch.rotation.x = PI * lean
	# The wrist comes in to the edge and down below the table top as the hand rolls back.
	h.turn.position = Vector3(lerpf(0.3, -2.3, lean), lerpf(1.15, -1.25, lean), 0)
	bone(h.skel, "arm1", lerpf(1.15, -1.1, lean))
	bone(h.skel, "arm2", lerpf(0.25, -0.2, lean))
	for k: int in 4:
		var fin: Node3D = h.fingers[k]
		var tip := fin.get_child(0) as Node3D
		var lift: float = clampf(maxf(-h.side * tip.rotation.z / 0.85, fin.position.y / 0.9 * 0.6), 0.0, 1.0)
		var rel: float = fin.position.z - (k - 1.5) * FINGER_GAP - h.body.position.z
		var i: int = 3 - k
		bone(h.skel, "f%d_1" % i, lerpf(0.12 + 0.8 * lift, lerpf(0.2, -0.5, h.close), lean), Vector3.RIGHT, atan(rel / 2.6) * (1.0 - lean))
		bone(h.skel, "f%d_2" % i, lerpf(-0.45 + 0.3 * lift, lerpf(-0.2, -0.8, h.close), lean))
		bone(h.skel, "f%d_3" % i, lerpf(-0.45 + 0.25 * lift, lerpf(-0.2, -0.75, h.close), lean))


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


func _hand(side: float) -> Hand:
	return _hands[1] if side > 0.0 else _hands[0]


func _hands_off() -> int:
	var n: int = 0
	for h: Hand in _hands:
		if h.off:
			n += 1
	return n


## Each hand keeps off whatever lies under it (Marko 2026-11-10/11): to the nearest free stretch of its
## edge within the walk, finger by finger, never walking past a ball. With no room on top it holds the rim
## from outside, its claws over the edge, where no ball lies by the rim for them to touch; along the outside
## to room on top when it comes free, and back up there. With no such place on the rim either it lets go
## of the edge into the dark, and comes back up the way it came at the start when there is room again.
## A ball still rolling is not in the way: the hand waits for it (_gate).
func _keep_clear(h: Hand, state: GameState, bodies: Dictionary[String, BallBody]) -> void:
	if h.busy or h.gate != "":
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


## A ball that lies still on the table, its picture where it is.
func _lying(b: BallBody) -> bool:
	return b.visible and b.in_play() and b.motion != BallBody.Motion.MOVING and b.motion != BallBody.Motion.OUT \
			and not _held.has(b.ball_id)


## Where along a hand's edge lies a ball the claws over the rim would touch.
func _rim_balls(side: float, bodies: Dictionary[String, BallBody]) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var edge: float = side * _ext.x
	for b: BallBody in bodies.values():
		if not _lying(b):
			continue
		var p: Vector3 = to_local(b.global_position)
		if absf(p.x - edge) < RIM_REACH:
			out.append(p.z)
	return out


## Where along a hand's edge (its z) lies something it must not rest on: balls lying on the table, the
## hexes of placed stages, cores on the field, all within NEAR_EDGE of that edge.
func _blocks(side: float, state: GameState, bodies: Dictionary[String, BallBody]) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var edge: float = side * _ext.x
	for b: BallBody in bodies.values():
		if not _lying(b):
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


## A tween of its own (a ball's picture, the face) that _snap can stop.
func _btw() -> Tween:
	_tweens = _tweens.filter(func(t: Tween) -> bool: return t.is_valid())
	var t: Tween = create_tween()
	_tweens.append(t)
	return t


## Everything that moves a hand now, stopped.
func _stop(h: Hand) -> void:
	for t: Tween in h.tweens:
		if t.is_valid():
			t.kill()
	h.tweens.clear()


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


## A hand that was taken off its edge, down in the dark and ready to come back up (_keep_clear brings it):
## out of its catching pose, and where it was along the edge before the catch moved it.
func _rest_hand(h: Hand) -> void:
	_stop(h)
	h.off = false
	h.open_for = false
	h.holding.clear()
	h.joiners = 0
	h.leaning = false
	h.gate = ""
	h.lean = 0.0
	h.close = 0.0
	h.body.position.z = h.lean_from_z
	h.at_z = h.home_z + h.body.position.z
	for k: int in h.fingers.size():
		var fin: Node3D = h.fingers[k]
		fin.position = Vector3(0, 0, (k - 1.5) * FINGER_GAP + h.body.position.z)
		(fin.get_child(0) as Node3D).rotation.z = 0.0
	h.position.y = BELOW
	h.hang = 1.0
	h.straight = 1.0
	h.hanging = true
	h.sunk = true
	h.busy = false


## The move timer under DRUM_FROM seconds: the viewer's right hand drums on the edge (Marko 2026-11-11).
func _drum(delta: float, clock_left: float) -> void:
	_drum_wait -= delta
	var every: float = drum_every(clock_left)
	if every <= 0.0 or _drum_wait > 0.0:
		return
	var h: Hand = _hands[1]
	if h.busy or h.off or h.gate != "" or h.hang > 0.01:
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


# --- a ball coming at an edge --------------------------------------------------------------------------

## The hand on top of an edge watches a ball that rolls at it: its fingers go up; when the ball is about
## to leave, it starts to roll back towards where the ball will go; if nothing leaves after all, the
## fingers come down and it rolls back over its fingers.
func _gate(h: Hand) -> void:
	if h.hanging or h.sunk:
		return
	if h.gate == "":
		if h.busy:
			return
		for b: BallBody in _bodies.values():
			if not b.visible or b.motion != BallBody.Motion.MOVING or _held.has(b.ball_id):
				continue
			var p: Vector3 = to_local(b.global_position)
			var v: Vector3 = _local_velocity(b)
			if absf(p.x - h.side * _ext.x) < 5.0 and absf(p.z - h.at_z) < 3.2 and v.x * h.side > 2.0:
				h.gate = "up"
				_fingers(h, true)
				return
		return
	if not _any_moving():
		# Nothing left the table after all: fingers down again, and out of the lean.
		h.gate = ""
		_fingers(h, false)
		if h.leaning:
			_unlean(h)
		return
	if h.leaning:
		return
	for b: BallBody in _bodies.values():
		if not b.visible or b.motion != BallBody.Motion.MOVING or _held.has(b.ball_id):
			continue
		var p: Vector3 = to_local(b.global_position)
		var v: Vector3 = _local_velocity(b)
		var d: float = absf(p.x - h.side * _ext.x)
		var vx: float = v.x * h.side
		if d < 2.4 and vx > 4.0:
			_prelean(h, p.z + v.z * (d / vx))
			return


func _local_velocity(b: BallBody) -> Vector3:
	return global_transform.basis.inverse() * b.linear_velocity


func _any_moving() -> bool:
	for b: BallBody in _bodies.values():
		if b.visible and b.motion == BallBody.Motion.MOVING and not _held.has(b.ball_id):
			return true
	return false


## The fingers up (a ball is coming) or down again, one after the other.
func _fingers(h: Hand, up: bool) -> void:
	for i: int in h.fingers.size():
		var fin: Node3D = h.fingers[i]
		var tip := fin.get_child(0) as Node3D
		var t: Tween = _tw(h, fin)
		t.tween_interval((0.035 if up else 0.075) * i)
		if up:
			t.tween_property(tip, "rotation:z", -h.side * 0.85, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t.parallel().tween_property(fin, "position:y", 0.9, 0.08)
		else:
			t.tween_property(tip, "rotation:z", 0.0, 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			t.parallel().tween_property(fin, "position:y", 0.0, 0.05)


## Before the ball has left: the hand starts to roll back and reaches along to where the ball is going.
func _prelean(h: Hand, to_z: float) -> void:
	h.leaning = true
	h.lean_from_z = h.body.position.z
	if h.lean_tween != null and h.lean_tween.is_valid():
		h.lean_tween.kill()
	var t: Tween = _tw(h, h)
	t.tween_property(h, "lean", 1.0, 0.26).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_property(h.body, "position:z", to_z - h.position.z, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	h.lean_tween = t


func _unlean(h: Hand) -> void:
	h.leaning = false
	if h.lean_tween != null and h.lean_tween.is_valid():
		h.lean_tween.kill()
	var t: Tween = _tw(h, h)
	t.tween_property(h, "lean", 0.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.parallel().tween_property(h.body, "position:z", h.lean_from_z, 0.3)
	h.lean_tween = t


# --- catching ------------------------------------------------------------------------------------------

## Every ball off the table (and so off the rules' map and strips) while the others still roll is caught.
func _watch() -> void:
	for id: String in _bodies:
		var b: BallBody = _bodies[id]
		if _held.has(id):
			_watch_held(_held[id], b)
			continue
		if not b.visible or not b.in_play():
			continue
		if _area(b.global_position) == BallWorld.Area.VOID:
			var hero: HeroState = _state.hero(id)
			_catch(id, to_local(b.global_position), b.radius(), hero.hp if hero != null else 0)


## A ball whose picture it has: where the rules put the ball itself back; thrown on from there before it
## was brought back, its picture is its own again at once.
func _watch_held(held: Held, b: BallBody) -> void:
	if held.stage == Stage.CATCHING or _area(b.global_position) == BallWorld.Area.VOID:
		return
	var p: Vector3 = to_local(b.global_position)
	if held.spot == Vector3.INF:
		held.spot = p
	elif Vector2(p.x - held.spot.x, p.z - held.spot.z).length() > 0.5:
		_release(held.id)


## A ball has just left the table (Marko 2026-11-10): the hand that holds that edge, its palm open below
## the edge (_catch_lean); a second one by the first into the same palm (_join); with both hands busy into
## the dark (_fall_past); over the near end into the mouth (_catch_mouth); elsewhere a hand from below.
func _catch(id: String, at: Vector3, radius: float, hp0: int) -> void:
	var held := Held.new()
	held.id = id
	# Where it left the table, at the height it rolled at (the ball itself may be falling already).
	held.at = Vector3(at.x, radius, at.z)
	held.pos = held.at
	held.stage = Stage.CATCHING
	held.hp0 = hp0
	_held[id] = held
	var side: float = 1.0 if at.x >= 0.0 else -1.0
	var short_end: bool = absf(at.z) > _ext.y - 0.3 and absf(at.x) < _ext.x - 0.3
	held.hold = Vector3(at.x + CATCH_REACH * side, CATCH_DOWN, at.z)
	if short_end:
		held.hold = Vector3(at.x, CATCH_DOWN, at.z + CATCH_REACH * signf(at.z))
	if short_end and at.z > 0.0:
		_catch_mouth(held)
		return
	var own: Hand = _hand(side)
	if not short_end and own.off and own.open_for and own.holding.size() == 1:
		var first: Held = own.holding[0]
		if absf(at.z - first.hold.z) < JOIN_ALONG:
			_join(held, own)
			return
	if _hands_off() >= 2:
		_fall_past(held)
		return
	if not short_end and not own.off and not own.hanging and not own.sunk and absf(at.z - (own.position.z + own.body.position.z)) < CATCH_ALONG:
		_catch_lean(held, own)
		return
	_catch_below(held, side, short_end)


## The ball's picture falls from where it is to `to` in `secs`.
func _fall(held: Held, to: Vector3, secs: float) -> Tween:
	var t: Tween = _btw()
	t.tween_property(held, "pos:x", to.x, secs)
	t.parallel().tween_property(held, "pos:z", to.z, secs)
	t.parallel().tween_property(held, "pos:y", to.y, secs).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return t


## The hand that holds this edge rolls back over its wrist into an open palm just under the edge (it may be
## halfway there already, _prelean) and the ball falls into it; it closes on what it holds and takes it
## under the table (Marko 2026-11-10).
func _catch_lean(held: Held, h: Hand) -> void:
	var gen: int = _gen
	h.off = true
	h.gate = ""
	# Whatever it was doing (walking, its fingers going up), it is catching now.
	_stop(h)
	if not h.leaning:
		h.lean_from_z = h.body.position.z
	h.leaning = false
	h.busy = true
	_cam.shake(0.3 if _hands_off() == 1 else 0.7, 0.35)
	h.holding = [held]
	h.open_for = true
	h.joiners = 0
	held.hand = h
	var dz: float = held.at.z - (h.position.z + h.body.position.z)
	var t: Tween = _tw(h, h)
	t.tween_property(h, "lean", 1.0, 0.2 * (1.0 - h.lean) + 0.02).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(h.body, "position:z", h.body.position.z + dz, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _fall(held, held.hold, 0.42).finished
	if gen != _gen:
		return
	await get_tree().create_timer(0.1).timeout
	while h.joiners > 0:
		await get_tree().process_frame
		if gen != _gen:
			return
	if gen != _gen:
		return
	h.open_for = false
	var t2: Tween = _tw(h, h)
	t2.tween_property(h, "close", 1.0, 0.1)
	t2.tween_interval(0.3)
	t2.tween_property(h, "position:y", -10.0, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for hv: Variant in h.holding:
		var hb: Held = hv
		t2.parallel().tween_property(hb, "pos", hb.hold + Vector3(0, -10, 0), 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t2.finished
	if gen != _gen:
		return
	for hv: Variant in h.holding:
		var hb: Held = hv
		_under(hb, _spare(hb.hold))


## A second ball into a palm that is still open for the first: the hand shifts to sit under both.
func _join(held: Held, h: Hand) -> void:
	var gen: int = _gen
	var first: Held = h.holding[0]
	var z2: float = held.hold.z
	if absf(z2 - first.hold.z) < 1.3:
		# The same hex: side by side in the palm.
		z2 = first.hold.z + (1.3 if held.hold.z >= first.hold.z else -1.3)
	held.hold = Vector3(first.hold.x, first.hold.y, z2)
	held.hand = h
	h.holding.append(held)
	h.joiners += 1
	_tw(h, h.body).tween_property(h.body, "position:z", (first.hold.z + z2) * 0.5 - h.position.z, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await _fall(held, held.hold, 0.42).finished
	if gen != _gen:
		return
	h.joiners -= 1


## No hand left for this one (K8): it goes on over the edge and drops into the dark; a hand brings it back
## after the others.
func _fall_past(held: Held) -> void:
	var gen: int = _gen
	var out: Vector3 = held.hold - held.at
	out.y = 0.0
	out = out.normalized()
	var t: Tween = _btw()
	t.tween_property(held, "pos:x", held.at.x + out.x * 4.5, 0.75)
	t.parallel().tween_property(held, "pos:z", held.at.z + out.z * 4.5, 0.75)
	t.parallel().tween_property(held, "pos:y", -11.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished
	if gen != _gen:
		return
	_under(held, _spare(held.hold))


## Away from the hand that holds that edge (the far half, a far end, or that hand busy): the hand of that
## side, or the other one, lets go of its edge, and a hand comes up from below, palm up, under the ball.
func _catch_below(held: Held, side: float, short_end: bool) -> void:
	var gen: int = _gen
	var g: Hand = _hand(side) if not _hand(side).off else _hand(-side)
	if not g.off:
		g.off = true
		g.gate = ""
		_stop(g)
		g.lean_from_z = g.body.position.z
		# (A hand already down in the dark, with no room on its edge, just stays there.)
		if not g.sunk or g.position.y > BELOW + 0.5:
			_let_go(g)
		if _hands_off() == 1:
			_cam.shake(0.3, 0.35)
		else:
			_cam.shake(0.7, 0.7)
	held.hand = g
	await get_tree().create_timer(0.24).timeout
	if gen != _gen:
		return
	var psi: float = (PI if side > 0.0 else 0.0)
	if short_end:
		psi = PI * 0.5 if held.at.z > 0.0 else -PI * 0.5
	var c: Claw = _make_claw(psi)
	held.claw = c
	var palm: Vector3 = held.hold - Vector3(0, 0.95, 0)
	c.position = palm + Vector3(0, -3.0, 0)
	# Up along the table's side with its fingers raised, then back onto its wrist, palm up.
	c.lean.rotation.z = -1.5
	var t: Tween = _btw()
	t.tween_property(c, "position", palm, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(c.lean, "rotation:z", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(held, "pos", held.hold, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(_grip.bind(c, true, 0.1))
	t.tween_interval(0.3)
	t.tween_property(c, "position", palm + Vector3(0, -10, 0), 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(held, "pos", held.hold + Vector3(0, -10, 0), 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished
	if gen != _gen:
		return
	_under(held, c)


## Over the near end, by the face (K10): the face slides under the ball and comes up a little, the mouth
## opens before the ball arrives, the ball drops in, the mouth snaps shut and is gone, a small gulp.
func _catch_mouth(held: Held) -> void:
	var gen: int = _gen
	var up_dy: float = -0.85 - EYES_DOWN
	# Where the mouth will be: down the face's plane, which leans back as the lids do.
	var tilt: float = -_lids.rotation.x
	var up := Vector3(held.at.x, -0.85, _eyes.position.z)
	var into: Vector3 = up + Basis(Vector3.UP, _eyes.rotation.y) * Vector3(0, -1.25 * cos(tilt), 1.25 * sin(tilt))
	_mouth.visible = true
	var t: Tween = _btw()
	t.tween_property(self, "face_x", held.at.x, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(self, "face_dy", up_dy, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_mouth, "scale:y", 1.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(held, "pos:x", into.x, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(held, "pos:z", into.z, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(held, "pos:y", into.y, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(_mouth, "scale:y", 0.02, 0.07)
	await t.finished
	if gen != _gen:
		return
	_mouth.visible = false
	held.shown = false
	_cam.shake(0.25, 0.2)
	var gulp: Tween = _btw()
	gulp.tween_property(self, "face_dy", up_dy - 0.35, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	gulp.tween_property(self, "face_dy", up_dy, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	gulp.tween_interval(0.14)
	gulp.tween_property(self, "face_x", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	gulp.parallel().tween_property(self, "face_dy", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_under(held, _spare(held.at + Vector3(0, 0, 3.0)))


## Caught: under the table and out of sight, with the hand that will bring it back.
func _under(held: Held, c: Claw) -> void:
	held.shown = false
	held.stage = Stage.UNDER
	held.claw = c


## Out of sight under the table, a hand that will bring a ball back.
func _spare(at: Vector3) -> Claw:
	var c: Claw = _make_claw(0.0)
	c.position = Vector3(at.x, -12.0, at.z)
	for px: Node3D in c.prox:
		px.rotation.z = 0.36
	return c


# --- the catching and returning hand ---------------------------------------------------------------------

## The hand palm up with its fingers away from the table: before `psi` its fingers point -x and its wrist
## is 2.0 towards +x; its lean node turns the whole hand about the wrist (-1.5 fingers up, 0 lying back).
func _make_claw(psi: float) -> Claw:
	var c := Claw.new()
	for k: int in 4:
		var px := Node3D.new()
		px.rotation.z = -0.7
		c.add_child(px)
		c.prox.append(px)
	var mirror := Node3D.new()
	c.add_child(mirror)
	c.spin = Node3D.new()
	c.spin.rotation.y = psi
	mirror.add_child(c.spin)
	c.lean = Node3D.new()
	c.lean.position = Vector3(2.0, 0, 0)
	c.spin.add_child(c.lean)
	c.un = Node3D.new()
	c.un.position = Vector3(-2.0, 0, 0)
	c.lean.add_child(c.un)
	var turn := Node3D.new()
	turn.rotation.y = PI * 0.5
	c.un.add_child(turn)
	c.flip = Node3D.new()
	c.flip.rotation.z = PI
	turn.add_child(c.flip)
	var model: Node3D = _model()
	model.position = Vector3(0, 0, -0.7)
	c.flip.add_child(model)
	var skels: Array[Node] = []
	_find(model, "Skeleton3D", skels)
	if not skels.is_empty():
		c.skel = skels[0] as Skeleton3D
	add_child(c)
	_claws.append(c)
	_pose_claw(c)
	return c


func _free_claw(c: Claw) -> void:
	if c == null:
		return
	_claws.erase(c)
	c.queue_free()


## The fingers: open to closed as the proxies are, and pinch brings the four fingertips together round
## what is held in front of them; palm down they stay nearly straight and point at one spot, a cone (the
## start zone's pinch, Marko 2026-11-10), and flat spreads them out.
func _pose_claw(c: Claw) -> void:
	if c.skel == null:
		return
	var g: float = clampf(inverse_lerp(-0.7, 0.36, c.prox[0].rotation.z), 0.0, 1.0)
	var pin: float = c.pinch
	bone(c.skel, "arm1", lerpf(1.1, 0.15, c.up) if c.palm_down else -1.1)
	bone(c.skel, "arm2", 0.2 if c.palm_down else -0.2)
	for i: int in 4:
		if c.palm_down:
			bone(c.skel, "f%d_1" % i, lerpf(lerpf(0.35, -0.25, pin), 0.05, c.flat), Vector3.RIGHT, (i - 1.5) * lerpf(lerpf(0.04, 0.4, pin), 0.03, c.flat))
			bone(c.skel, "f%d_2" % i, lerpf(lerpf(-0.1, -0.15, pin), 0.0, c.flat))
			bone(c.skel, "f%d_3" % i, lerpf(-0.2, 0.0, c.flat))
			continue
		var conv: float = (i - 1.5) * PINCH_SPLAY * pin
		bone(c.skel, "f%d_1" % i, lerpf(lerpf(0.2, -0.5, g), -0.12, pin), Vector3.RIGHT, conv)
		bone(c.skel, "f%d_2" % i, lerpf(lerpf(-0.2, -0.8, g), -0.3, pin))
		bone(c.skel, "f%d_3" % i, lerpf(lerpf(-0.2, -0.75, g), -0.45, pin))


## The fingers close (or open) in `secs`.
func _grip(c: Claw, closed_: bool, secs: float) -> void:
	for px: Node3D in c.prox:
		var t: Tween = _btw()
		t.tween_property(px, "rotation:z", 0.36 if closed_ else -0.7, secs)


## The hand of the start zone (Marko 2026-11-11: the same hand wherever a ball is brought back): palm down,
## its fingertips gathered where TIPS is.
func _palm_down(c: Claw, e: float) -> void:
	c.spin.rotation.y = -e * PI * 0.5
	c.flip.rotation.z = 0.0
	c.palm_down = true
	c.lean.rotation.z = 0.12
	c.pinch = 1.0
	c.flat = 0.0
	c.up = 0.0
	if c.tips == null:
		c.tips = Node3D.new()
		c.tips.position = TIPS
		c.un.add_child(c.tips)
	_pose_claw(c)


## Where the fingertips are from the hand's own place (the hand is Bochet's child, not turned).
func _tips_offset(c: Claw) -> Vector3:
	return to_local(c.tips.global_position) - c.position


## The ball's picture keeps to the fingertips in the same frame as the hand moves: a tween made after the
## hand's own, which also sets the picture directly (the match sets it before the tweens run).
func _follow(held: Held, c: Claw) -> void:
	if held.follow != null and held.follow.is_valid():
		held.follow.kill()
	var t: Tween = _btw()
	t.tween_method(_follow_step.bind(held, c), 0.0, 1.0, 600.0)
	held.follow = t


func _follow_step(_v: float, held: Held, c: Claw) -> void:
	if not is_instance_valid(c) or c.tips == null:
		return
	held.pos = to_local(c.tips.global_position)
	if _views.has(held.id) and is_instance_valid(_views[held.id]):
		_views[held.id].global_position = c.tips.global_position


func _unfollow(held: Held) -> void:
	if held.follow != null and held.follow.is_valid():
		held.follow.kill()
	held.follow = null


## One move without a stop: up beside the table first, and over its edge only once the ball is above the top.
func _pinch_path(k: float, c: Claw, low: Vector3, hover: Vector3) -> void:
	var up: float = 1.0 - pow(1.0 - k, 3.0)
	var over: float = smoothstep(0.5, 1.0, k)
	c.position = Vector3(hover.x, lerpf(low.y, hover.y, up), lerpf(low.z, hover.z, over))


# --- bringing back -------------------------------------------------------------------------------------

## When every catch is done and nothing rolls, and the rules have put the balls back on their strips, the
## hands bring them back, two at a time (both hands); a ball its ring-out knocked out stays in the dark.
func _bring_back() -> void:
	if _returning or _held.is_empty() or _any_moving():
		return
	var ready: Array[Held] = []
	for held: Held in _held.values():
		if held.stage == Stage.CATCHING:
			return
		if held.stage != Stage.UNDER:
			continue
		var h: HeroState = _state.hero(held.id)
		if h == null or not _bodies.has(held.id):
			continue
		if _area(_bodies[held.id].global_position) == BallWorld.Area.VOID and not h.is_ko():
			# The rules have not put it back yet (the roll is not over for them).
			continue
		if h.is_on_map():
			# Back on the map by some other way: nothing to bring back.
			_release(held.id)
			continue
		ready.append(held)
	if not ready.is_empty():
		_return_batch(ready)


func _return_batch(ready: Array[Held]) -> void:
	var gen: int = _gen
	_returning = true
	await get_tree().create_timer(0.3).timeout
	if gen != _gen:
		return
	var gone: Array[Held] = []
	for held: Held in ready:
		var h: HeroState = _state.hero(held.id)
		if held.gone or (h != null and h.is_ko()):
			gone.append(held)
	if not gone.is_empty():
		_keep_sign()
	for held: Held in gone:
		_keep_it(held)
	var n: int = 0
	for held: Held in ready:
		if gone.has(held):
			continue
		if n > 0 and n % 2 == 0:
			await get_tree().create_timer(1.15).timeout
			if gen != _gen:
				return
		n += 1
		if _held.get(held.id) == held:
			_return_one(held)
	while true:
		var busy: bool = false
		for held: Held in _held.values():
			if held.stage == Stage.BACK:
				busy = true
		if not busy:
			break
		await get_tree().process_frame
		if gen != _gen:
			return
	await get_tree().create_timer(1.5).timeout
	if gen != _gen:
		return
	_returning = false
	_hands_home()


## The hands a catch took off their edges come back up, those no ball still needs.
func _hands_home() -> void:
	for h: Hand in _hands:
		if not h.off:
			continue
		var used: bool = false
		for held: Held in _held.values():
			if held.hand == h:
				used = true
		if not used:
			_rest_hand(h)


## Up at the ball's start zone with the ball, set down on its spot, and away; held over the spot while its
## player chooses what the ring-out costs.
func _return_one(held: Held) -> void:
	var gen: int = _gen
	held.stage = Stage.BACK
	var target: Vector3 = to_local(_bodies[held.id].global_position)
	var place: Vector3 = await _pinch_in(held, target, HOLD_LIFT)
	if gen != _gen or _held.get(held.id) != held:
		return
	await _hold_wait(held)
	if gen != _gen or _held.get(held.id) != held:
		return
	var hero: HeroState = _state.hero(held.id)
	if held.gone or (hero != null and hero.is_ko()):
		await _take_down(held)
		return
	await _pinch_out(held, target, place)


## The start zone's hand, the ball in its fingertips: up outside the edge of the ball's start zone and over
## it to `lift` above the spot (Marko 2026-11-11). Returns where the hand is when the ball is on its spot.
func _pinch_in(held: Held, target: Vector3, lift: float) -> Vector3:
	var gen: int = _gen
	var c: Claw = held.claw
	if c == null:
		c = _spare(target)
		held.claw = c
	var e: float = 1.0 if target.z >= 0.0 else -1.0
	_palm_down(c, e)
	# (Worked out where the hand is, down in the dark: it must not show anywhere while the eyes step aside.)
	var place: Vector3 = target - _tips_offset(c)
	var hover: Vector3 = place + Vector3(0, lift, 0)
	if e > 0.0 and _eyes_near(target.x):
		_aside(target.x)
		held.set_meta("aside", true)
		# The eyes first, then the hand: it comes up where they were.
		await get_tree().create_timer(0.2).timeout
		if gen != _gen:
			return place
	# Beside the table the ball is clear of its side by more than its own half.
	var out: float = maxf(_ext.y + 1.3 - absf(target.z), 0.0)
	var low := Vector3(hover.x, hover.y - 6.5, hover.z + e * out)
	held.hover = hover
	held.low = low
	c.position = low
	held.pos = to_local(c.tips.global_position)
	# The ball shows once the fingers that hold it are out of the dark: it must not hang there alone.
	held.shown = false
	var t: Tween = _btw()
	t.tween_method(_pinch_path.bind(c, low, hover), 0.0, 1.0, 0.5)
	t.parallel().tween_callback(func() -> void: held.shown = true).set_delay(0.06)
	_follow(held, c)
	await t.finished
	return place


## Down onto the spot, let go, and away the chosen way (Marko 2026-11-11): back into the upright flat hand
## outside the edge and straight down, without a stop.
func _pinch_out(held: Held, target: Vector3, place: Vector3) -> void:
	var gen: int = _gen
	var c: Claw = held.claw
	var e: float = 1.0 if target.z >= 0.0 else -1.0
	var stand := Vector3(place.x, -1.9, e * (_ext.y + 0.8))
	var t: Tween = _btw()
	t.tween_property(c, "position", place, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_callback(_set_down.bind(held, target))
	t.tween_property(c, "pinch", 0.0, 0.1)
	t.tween_callback(_ring.bind(Vector3(target.x, 0.1, target.z)))
	t.tween_property(c.lean, "rotation:z", -1.5, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(c, "flat", 1.0, 0.17)
	t.parallel().tween_property(c, "up", 1.0, 0.25)
	t.parallel().tween_property(c, "position", stand, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_property(c, "position", stand + Vector3(0, -8.0, 0), 0.25).set_trans(Tween.TRANS_LINEAR)
	_follow(held, c)
	await t.finished
	if gen != _gen:
		return
	if held.has_meta("aside"):
		# The hand is gone: the eyes come back.
		_aside_end()
	_free_claw(c)


## On its spot: the picture is the ball's own again.
func _set_down(held: Held, _target: Vector3) -> void:
	_unfollow(held)
	if _held.get(held.id) == held:
		_held.erase(held.id)


## Held over its spot until the cost of the ring-out is settled, swaying a little (Marko 2026-11-10); damage
## is a squeeze with the number, a faint white blink (W3) and a hard shake.
func _hold_wait(held: Held) -> void:
	var gen: int = _gen
	var c: Claw = held.claw
	var clock: float = 0.0
	while ring_pending(_state, held.id):
		clock += get_process_delta_time()
		c.position = held.hover + Vector3(sin(clock * 2.6) * 0.1, sin(clock * 4.2) * 0.12, 0)
		await get_tree().process_frame
		if gen != _gen or _held.get(held.id) != held:
			return
	c.position = held.hover
	var hero: HeroState = _state.hero(held.id)
	if hero == null or hero.hp >= held.hp0 or not _views.has(held.id):
		return
	var bv: BallView = _views[held.id]
	var s0: Vector3 = bv.scale
	bv.float_text("-%d" % (held.hp0 - hero.hp), BallView.HIT_TINT)
	held.hp0 = hero.hp
	_cam.shake(0.3, 0.5)
	var q: Tween = _btw()
	q.tween_property(c, "pinch", 1.35, 0.09)
	q.parallel().tween_property(bv, "scale", Vector3(s0.x * 0.8, s0.y * 1.16, s0.z * 0.8), 0.09)
	q.tween_callback(bv.flash_faint)
	q.tween_interval(0.12)
	for i: int in 7:
		var amp: float = 0.6 * (1.0 - i / 9.0)
		var sx: float = amp if i % 2 == 0 else -amp
		q.tween_property(c, "position", held.hover + Vector3(sx, 0.22 if i % 2 == 0 else -0.12, 0), 0.07).set_trans(Tween.TRANS_SINE)
	q.tween_property(c, "position", held.hover, 0.08)
	q.tween_property(c, "pinch", 1.0, 0.1)
	q.parallel().tween_property(bv, "scale", s0, 0.1)
	q.tween_interval(0.15)
	_follow(held, c)
	await q.finished


## Its ring-out knocked it out (KO7, Marko 2026-11-10): the hand takes it back down into the dark and does
## not bring it back; the eyes narrow.
func _take_down(held: Held) -> void:
	var gen: int = _gen
	var c: Claw = held.claw
	var t: Tween = _btw()
	t.tween_method(_pinch_path.bind(c, held.low, held.hover), 1.0, 0.0, 0.45)
	_follow(held, c)
	await t.finished
	if gen != _gen:
		return
	_keep_sign()
	_keep_it(held)


## Kept in the dark for good: the match hides the ball.
func _keep_it(held: Held) -> void:
	_unfollow(held)
	held.shown = false
	if held.has_meta("aside"):
		_aside_end()
	_free_claw(held.claw)
	held.claw = null
	if _held.get(held.id) == held:
		_held.erase(held.id)
	kept.emit(held.id)


## The small sign: the eyes narrow and the face bobs in a short chuckle.
func _keep_sign() -> void:
	var t: Tween = _btw()
	t.tween_interval(0.25)
	t.tween_property(self, "squint", 1.0, 0.18)
	for i: int in 3:
		t.tween_property(self, "face_dy", face_dy + 0.18, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(self, "face_dy", face_dy, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_interval(0.55)
	t.tween_property(self, "squint", 0.0, 0.2)


## Its picture is the ball's own again, at once (thrown again while held, or the state jumped).
func _release(id: String) -> void:
	if not _held.has(id):
		return
	var held: Held = _held[id]
	_unfollow(held)
	if held.has_meta("aside"):
		_aside_end()
	_free_claw(held.claw)
	_held.erase(id)
	if held.hand != null:
		held.hand.holding.erase(held)
	_hands_home()


## Whether the player is still to choose what this ball's ring-out costs (damage, or a card instead). Never once
## the match is over (code review 2026-11-13): a match given up in the middle of that choice keeps the choice in
## its state for good, and the hand held the ball over its spot behind the end screen for ever.
static func ring_pending(state: GameState, hero_id: String) -> bool:
	if state.is_over():
		return false
	for d: Dictionary in state.pending:
		if str(d.get("type", "")) == RulesEngine.DECISION_DAMAGE and JsonUtil.as_bool(d.get("ring_out", false)) \
				and JsonUtil.as_strings(d.get("targets", [])).has(hero_id):
			return true
	return false


## A gold ring that spreads and fades where a ball has been set down.
func _ring(at: Vector3) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.5
	torus.outer_radius = 0.62
	ring.mesh = torus
	ring.material_override = MeshKit.unshaded(Palette.GOLD, false)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	ring.position = at
	var rt: Tween = ring.create_tween().set_parallel(true)
	rt.tween_property(ring, "scale", Vector3.ONE * 3.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "transparency", 1.0, 0.4)
	rt.chain().tween_callback(ring.queue_free)


## The face steps aside along the near edge for a hand that comes up by it, and back when none is there.
func _aside(x: float) -> void:
	_aside_n += 1
	var t: Tween = _btw()
	t.tween_property(self, "face_x", x + EYES_ASIDE_TO, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _aside_end() -> void:
	_aside_n = maxi(0, _aside_n - 1)
	if _aside_n == 0:
		var t: Tween = _btw()
		t.tween_property(self, "face_x", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


# --- a ball that stops in a start zone ---------------------------------------------------------------------

## A ball that stopped in a start zone (Marko 2026-11-10/11): the hand of that side lets go of its edge, the
## start zone's hand comes over the edge palm down, gathers its fingers on the ball where it lies, carries it
## to its spot and holds it there while its player chooses; from the other side's zone it takes it back over
## that edge into the dark and brings it up at its own.
func _pick_up(id: String, from: Vector3, target: Vector3, hp0: int) -> void:
	var gen: int = _gen
	var held := Held.new()
	held.id = id
	held.pos = from
	held.at = from
	held.stage = Stage.BACK
	held.spot = target
	held.hp0 = hp0
	_held[id] = held
	var ef: float = 1.0 if from.z >= 0.0 else -1.0
	var side: float = 1.0 if from.x >= 0.0 else -1.0
	var h: Hand = _hand(side)
	if not h.off:
		h.off = true
		h.gate = ""
		_stop(h)
		h.lean_from_z = h.body.position.z
		if not h.sunk or h.position.y > BELOW + 0.5:
			_let_go(h)
	held.hand = h
	_cam.shake(0.3, 0.35)
	if ef > 0.0 and _eyes_near(from.x):
		_aside(from.x)
		held.set_meta("aside", true)
	await get_tree().create_timer(0.5).timeout
	if gen != _gen or _held.get(id) != held:
		return
	var c: Claw = _make_claw(0.0)
	held.claw = c
	_palm_down(c, ef)
	c.pinch = 0.0
	var off: Vector3 = _tips_offset(c)
	var pick: Vector3 = from - off
	var up := Vector3(0, HOLD_LIFT, 0)
	c.position = pick + Vector3(0, -5.5, ef * 2.4)
	var t: Tween = _btw()
	t.tween_property(c, "position", pick + Vector3(0, 0.9, 0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "position", pick, 0.1)
	t.tween_property(c, "pinch", 1.0, 0.1)
	t.tween_callback(_follow.bind(held, c))
	t.tween_interval(0.1)
	t.tween_property(c, "position", pick + up, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await t.finished
	if gen != _gen or _held.get(id) != held:
		return
	var place: Vector3 = target - off
	if (from.z >= 0.0) != (target.z >= 0.0):
		# Back over the edge it came over, and down into the dark with the ball: the way in, run backwards.
		var top: Vector3 = pick + up
		var out: float = maxf(_ext.y + 1.3 - absf(from.z), 0.0)
		var low := Vector3(top.x, top.y - 6.5, top.z + ef * out)
		var d: Tween = _btw()
		d.tween_method(_pinch_path.bind(c, low, top), 1.0, 0.0, 0.45)
		_follow(held, c)
		await d.finished
		if gen != _gen or _held.get(id) != held:
			return
		held.shown = false
		_unfollow(held)
		if held.has_meta("aside"):
			held.remove_meta("aside")
			_aside_end()
		await get_tree().create_timer(0.3).timeout
		if gen != _gen or _held.get(id) != held:
			return
		place = await _pinch_in(held, target, HOLD_LIFT)
		if gen != _gen or _held.get(id) != held:
			return
	else:
		held.hover = place + up
		held.low = Vector3(held.hover.x, held.hover.y - 6.5, held.hover.z + ef * maxf(_ext.y + 1.3 - absf(target.z), 0.0))
		var carry: Tween = _btw()
		carry.tween_property(c, "position", held.hover, 0.36).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_follow(held, c)
		await carry.finished
		if gen != _gen or _held.get(id) != held:
			return
	await _hold_wait(held)
	if gen != _gen or _held.get(id) != held:
		return
	var hero: HeroState = _state.hero(id)
	if held.gone or (hero != null and hero.is_ko()):
		await _take_down(held)
	else:
		await _pinch_out(held, target, place)
	if gen != _gen:
		return
	_hands_home()


# --- a hero knocked out ---------------------------------------------------------------------------------

## KO4 (Marko 2026-11-10): a hole opens in the table under the ball, the fingers come up out of it round
## the ball and close on it (the game slows a moment), and pull it down with its figure; the hole shuts.
## KO5: next to another ball the hole is only as wide as there is room for (half the way to a ball that
## goes down too), the hand as big as the hole but never smaller than the ball needs. KO6: two at once,
## a hole and a hand each.
func _ko_hole(held: Held, b: BallBody) -> void:
	var gen: int = _gen
	var at: Vector3 = held.at
	var r: float = b.radius()
	var space: float = b.tuning.hex_spacing()
	var rad: float = space
	for ob: BallBody in _bodies.values():
		if ob == b or not ob.visible:
			continue
		var op: Vector3 = to_local(ob.global_position)
		var od: float = Vector2(op.x - at.x, op.z - at.z).length()
		if od > space * 3.0:
			continue
		var room: float = od * 0.5 - 0.05 if _dying.has(ob.ball_id) else od - ob.radius() - 0.05
		rad = minf(rad, room / 1.22)
	rad = hole_radius(space, r, rad)
	var hole := Node3D.new()
	add_child(hole)
	_ko_nodes.append(hole)
	hole.position = Vector3(at.x, 0.06, at.z)
	hole.rotation.x = -PI * 0.5
	# Over a stage's board too (it is drawn without depth at priority 2).
	var sizes: Array[float] = [1.22, 1.07, 1.0]
	var cols: Array[Color] = [Color(RIM, 0.3), HOLE_RIM, HOLE_DARK]
	var zs: Array[float] = [-0.01, -0.005, 0.0]
	for i: int in sizes.size():
		var mi: MeshInstance3D = _flat(hole, disc(Vector2.ZERO, rad * sizes[i], 30), cols[i], zs[i])
		var m := mi.material_override as StandardMaterial3D
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.render_priority = 3
	hole.scale = Vector3.ONE * 0.05
	var k: float = maxf(0.95 * rad / space, (r + 0.03) / 1.15)
	var claw: Node3D = _ko_hand()
	claw.scale = Vector3.ONE * k
	add_child(claw)
	_ko_nodes.append(claw)
	# The palm right under the ball, so that the fingertips close on the ball and not below it.
	var palm := Vector3(at.x, -0.62 * k - 0.06, at.z)
	var wrap: PackedFloat32Array = wrap_solve(r / k, (at.y - palm.y) / k)
	var wide: float = clampf(inverse_lerp(0.6, 0.95, k), 0.0, 1.0)
	_wrap_set(0.0, claw, wrap, wide)
	claw.position = palm + Vector3(0, -3.2, 0)
	var t: Tween = _btw()
	t.tween_property(hole, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.1)
	t.tween_property(claw, "position", palm, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.14)
	t.tween_callback(_ko_slow)
	t.tween_method(_wrap_set.bind(claw, wrap, wide), 0.0, 1.0, 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_interval(0.34)
	t.tween_property(claw, "position", palm + Vector3(0, -6.0, 0), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(held, "pos", at + Vector3(0, -6.0, 0), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(hole, "scale", Vector3.ONE * 0.02, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished
	if gen != _gen:
		return
	for n: Node3D in [hole, claw]:
		_ko_nodes.erase(n)
		n.queue_free()
	_dying.erase(held.id)
	held.shown = false
	if _held.get(held.id) == held:
		_held.erase(held.id)
	kept.emit(held.id)


## How wide a KO hole is: as much as `room` allows, at most a hex, never less than the ball and a little.
static func hole_radius(space: float, ball_r: float, room: float) -> float:
	return maxf(minf(room, space), ball_r + 0.12)


## The KO grip slows the game for a moment (real time).
func _ko_slow() -> void:
	if not slow_ko or _slowing:
		return
	_slowing = true
	Engine.time_scale = KO_SLOW_SCALE
	await get_tree().create_timer(KO_SLOW_TIME, true, false, true).timeout
	if _slowing:
		Engine.time_scale = 1.0
		_slowing = false


## The closed grip on a ball of radius `r` whose centre is `cy` above the palm, both in the hand's own
## units: each piece of a finger runs along the tangent to the ball from where the piece before it ended,
## the claw and its point aimed at the ball. Returns each piece's turn from the one before.
static func wrap_solve(r: float, cy: float) -> PackedFloat32Array:
	var c := Vector2(0, cy)
	var j := Vector2(1.15, 0.15)
	var prev: float = 0.0
	var out := PackedFloat32Array()
	for i: int in WRAP_LENS.size():
		var t: float = r + WRAP_THICK[i]
		var v: Vector2 = c - j
		var alpha: float = asin(clampf(t / maxf(v.length(), 0.001), 0.0, 1.0))
		if i >= 3:
			var dist: float = v.length()
			var ends: float = r + (0.13 if i == 3 else 0.02)
			alpha = acos(clampf((dist * dist + WRAP_LENS[i] * WRAP_LENS[i] - ends * ends) / (2.0 * dist * WRAP_LENS[i]), -1.0, 1.0))
		var d: Vector2 = v.normalized().rotated(-alpha)
		var phi: float = atan2(-d.x, d.y)
		out.append(phi - prev)
		prev = phi
		j += d * WRAP_LENS[i]
	return out


## The fingers from open (0: as wide as the hole lets them, `wide`) to closed on the ball (1).
func _wrap_set(g: float, claw: Node3D, wrap: PackedFloat32Array, wide: float) -> void:
	if not is_instance_valid(claw):
		return
	for f: Node in claw.get_children():
		var n := f as Node3D
		n.rotation.z = lerpf(lerpf(WRAP_OPEN[0], WRAP_WIDE[0], wide), wrap[0], g)
		var piv := (n.get_child(0) as Node3D).get_child(0) as Node3D
		piv.rotation.z = 0.0
		for i: int in range(1, wrap.size()):
			piv = piv.get_child(2) as Node3D
			piv.rotation.z = lerpf(lerpf(WRAP_OPEN[i], WRAP_WIDE[i], wide), wrap[i], g)


## The KO hand: only its four fingers, round where the ball will be, each three pieces and a claw.
func _ko_hand() -> Node3D:
	var skin: ShaderMaterial = _flat_mat(KO_SKIN, RIM, 0.5)
	var nail: ShaderMaterial = _flat_mat(KO_NAIL, KO_NAIL_RIM, 0.2)
	var root := Node3D.new()
	for k: int in 4:
		var a: float = TAU * k / 4.0 + 0.6
		var f := Node3D.new()
		f.position = Vector3(cos(a) * 1.15, 0.15, sin(a) * 1.15)
		f.rotation.y = -a
		f.rotation.z = -0.7
		f.add_child(_chain([0.8, 0.65, 0.45], [0.4, 0.36, 0.31, 0.26], [0.0, 0.35, 0.4], skin, nail, 0.5, 0.3))
		root.add_child(f)
	return root


## A finger along +y: jointed pieces that curl about z, each joint a knob, then a two-piece claw. Every
## joint's children are its knob, its piece and the next joint, in that order (_wrap_set walks them).
func _chain(lens: Array[float], radii: Array[float], bends: Array[float], skin: Material, nail: Material, claw_len: float, claw_bend: float) -> Node3D:
	var root := Node3D.new()
	var at: Node3D = root
	for i: int in lens.size():
		var piv := Node3D.new()
		piv.rotation.z = bends[i]
		if i > 0:
			piv.position.y = lens[i - 1]
		at.add_child(piv)
		piv.add_child(_knob(radii[i] * 1.12, skin))
		piv.add_child(_seg(lens[i], radii[i], radii[i + 1], 6, skin))
		at = piv
	var last: float = radii[radii.size() - 1]
	var cp := Node3D.new()
	cp.position.y = lens[lens.size() - 1]
	cp.rotation.z = claw_bend
	at.add_child(cp)
	cp.add_child(_knob(last * 1.05, skin))
	cp.add_child(_seg(claw_len, last * 0.95, last * 0.62, 5, nail))
	var tp := Node3D.new()
	tp.position.y = claw_len
	tp.rotation.z = claw_bend * 0.6
	cp.add_child(tp)
	tp.add_child(_seg(claw_len * 0.95, last * 0.62, 0.0, 5, nail))
	return root


static func _piece(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _seg(length: float, r0: float, r1: float, sides: int, mat: Material) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.bottom_radius = r0
	c.top_radius = r1
	c.height = length
	c.radial_segments = sides
	c.rings = 1
	var mi: MeshInstance3D = _piece(c, mat)
	mi.position.y = length * 0.5
	return mi


static func _knob(r: float, mat: Material) -> MeshInstance3D:
	var sp := SphereMesh.new()
	sp.radius = r
	sp.height = r * 2.0
	sp.radial_segments = 6
	sp.rings = 3
	return _piece(sp, mat)


static func _flat_mat(base: Color, rim: Color, rim_amt: float) -> ShaderMaterial:
	if _flat_shader == null:
		_flat_shader = Shader.new()
		_flat_shader.code = FLAT_SHADER
	var m := ShaderMaterial.new()
	m.shader = _flat_shader
	m.render_priority = 4
	m.set_shader_parameter("base", base)
	m.set_shader_parameter("rim", rim)
	m.set_shader_parameter("rim_amt", rim_amt)
	return m


# --- coming up ----------------------------------------------------------------------------------------

## At once: on the edges with its eyes open (shown), or out of sight below the table with its eyes shut.
## Every ball's picture is its own again.
func _snap(shown: bool) -> void:
	_gen += 1
	if _entry != null and _entry.is_valid():
		_entry.kill()
	for t: Tween in _tweens:
		if t.is_valid():
			t.kill()
	_tweens.clear()
	for c: Claw in _claws:
		c.queue_free()
	_claws.clear()
	for n: Node3D in _ko_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_ko_nodes.clear()
	_dying.clear()
	if _slowing:
		Engine.time_scale = 1.0
		_slowing = false
	_held.clear()
	_returning = false
	_left = false
	_shown = shown
	_entering = false
	closed = 0.0 if shown else 1.0
	squint = 0.0
	face_x = 0.0
	face_dy = 0.0
	_aside_n = 0
	_eyes.visible = shown
	_mouth.visible = false
	_mouth.scale.y = 0.02
	_eyes_placed = false
	for h: Hand in _hands:
		_stop(h)
		h.position = Vector3(h.side * _ext.x, 0.0 if shown else BELOW, _ext.y * HOME)
		h.hang = 0.0 if shown else 1.0
		h.straight = 0.0 if shown else 1.0
		h.lean = 0.0
		h.close = 0.0
		h.home_z = h.position.z
		h.at_z = h.home_z
		h.body.position.z = 0.0
		h.lean_from_z = 0.0
		for k: int in h.fingers.size():
			var fin: Node3D = h.fingers[k]
			fin.position = Vector3(0, 0, (k - 1.5) * FINGER_GAP)
			(fin.get_child(0) as Node3D).rotation.z = 0.0
		h.busy = false
		h.hanging = not shown
		h.sunk = not shown
		h.off = false
		h.gate = ""
		h.leaning = false
		h.holding.clear()
		h.open_for = false
		h.joiners = 0
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
## an iris and a slit pupil that slide inside it, cut off along a slanted line across the top, lower towards
## the middle, with a thin brow on the cut (the O8 eyes); under them a mouth, shut and gone until a ball
## comes by. The cut is a real cut (Marko 2026-11-13): a dark lid painted over the eye only hid on the dark
## under the table, and showed as a cap as soon as the camera turned and the eye stood against anything else.
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
		_cut(eye, disc(Vector2.ZERO, 1.32, 26), Color(EYE, 0.22), -0.03, lo, slope * e)
		_cut(eye, disc(Vector2.ZERO, 1.0, 26), EYE, 0.0, lo, slope * e)
		_irises.append(_cut(eye, disc(Vector2.ZERO, 0.6, 20), IRIS, 0.02, lo, slope * e))
		_pupils.append(_cut(eye, lens(Vector2(0, -0.62), Vector2(0, 0.62), 0.5, 7), PUPIL, 0.04, lo, slope * e))
		_flat(eye, PackedVector2Array([Vector2(-1.25 * e, lo - slope * 1.25 - 0.09), Vector2(1.25 * e, lo + slope * 1.25 - 0.09),
			Vector2(1.25 * e, lo + slope * 1.25 + 0.05), Vector2(-1.25 * e, lo - slope * 1.25 + 0.05)]), BROW, 0.07)
	# The mouth (K10): a dark lens with a row of teeth above and below, in the same plane as the eyes.
	_jaw = Node3D.new()
	_jaw.rotation.x = -0.95
	root.add_child(_jaw)
	_mouth = Node3D.new()
	_mouth.position = Vector3(0, -1.25, 0)
	_jaw.add_child(_mouth)
	var half: float = 2.9
	var depth: float = 1.0
	_flat(_mouth, lens(Vector2(-half - 0.3, 0), Vector2(half + 0.3, 0), depth + 0.22, 12), Color(EYE, 0.2), -0.03)
	_flat(_mouth, lens(Vector2(-half, 0), Vector2(half, 0), depth, 12), MOUTH, 0.0)
	for i: int in 7:
		var x: float = (i - 3) * 0.74
		var edge: float = depth * sin(PI * (x + half) / (half * 2.0))
		_flat(_mouth, PackedVector2Array([Vector2(x - 0.3, edge), Vector2(x + 0.3, edge), Vector2(x, edge - 0.58)]), TOOTH, 0.03)
		if i < 6:
			var xl: float = x + 0.37
			var el: float = depth * sin(PI * (xl + half) / (half * 2.0))
			_flat(_mouth, PackedVector2Array([Vector2(xl - 0.28, -el), Vector2(xl + 0.28, -el), Vector2(xl, -el + 0.5)]), TOOTH, 0.03)
	_mouth.scale.y = 0.02
	_mouth.visible = false
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


## A flat polygon as _flat, of which only the part under the line y = lo + slope * x of its parent's plane
## is drawn. A piece that slides or stretches in that plane says so with _cut_at, so the line stays put.
static func _cut(parent: Node3D, pts: PackedVector2Array, col: Color, z: float, lo: float, slope: float) -> MeshInstance3D:
	var mi: MeshInstance3D = _flat(parent, pts, col, z)
	var m := ShaderMaterial.new()
	m.shader = _cut_shader(col.a < 1.0)
	m.set_shader_parameter("col", col)
	m.set_shader_parameter("lo", lo)
	m.set_shader_parameter("slope", slope)
	mi.material_override = m
	return mi


## Where a _cut piece is in its parent's plane now: moved by `shift`, `wide` times as wide.
static func _cut_at(piece: MeshInstance3D, shift: Vector2, wide: float) -> void:
	var m: ShaderMaterial = piece.material_override
	m.set_shader_parameter("shift", shift)
	m.set_shader_parameter("wide", wide)


static var _cut_shaders: Dictionary[bool, Shader] = {}


static func _cut_shader(see_through: bool) -> Shader:
	if not _cut_shaders.has(see_through):
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(1.0);
uniform vec2 shift = vec2(0.0);
uniform float wide = 1.0;
uniform float lo = 0.0;
uniform float slope = 0.0;
varying vec2 at;
void vertex() {
	at = vec2(VERTEX.x * wide, VERTEX.y) + shift;
}
void fragment() {
	if (at.y > lo + slope * at.x) {
		discard;
	}
	ALBEDO = col.rgb;
%s}
""" % ("	ALPHA = col.a;
" if see_through else "")
		_cut_shaders[see_through] = sh
	return _cut_shaders[see_through]


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
## close from the home view, further out as the view turns away. Out at once, back in eased. Aside along
## the edge (face_x) and lifted (face_dy) as the mouth and the hands need.
func _place_eyes(delta: float) -> void:
	var view: Camera3D = get_viewport().get_camera_3d()
	if view == null:
		return
	var from: Vector3 = to_local(view.global_position)
	var fx: float = face_x + _dodge_x
	var want: float = eyes_out(from)
	while want < EYES_FURTHEST and not eyes_seen(Vector3(fx, EYES_DOWN, _ext.y + want), from, _ext):
		want += 0.2
	var now: float = _eyes.position.z - _ext.y
	if not _eyes_placed or want > now:
		now = want
	else:
		now = lerpf(now, want, clampf(delta * 10.0, 0.0, 1.0))
	_eyes_placed = true
	_eyes.position = Vector3(fx, EYES_DOWN + face_dy, _ext.y + now)
	var to: Vector3 = from - _eyes.position
	_eyes.rotation.y = atan2(to.x, to.z)
	_lids.rotation.x = -atan2(to.y, Vector2(to.x, to.z).length())
	_jaw.rotation.x = _lids.rotation.x


## The eyes get out from behind the cards in hand (Marko 2026-11-11, mockup A): once the raised cards have
## covered them for DODGE_AFTER seconds both eyes slide aside along the near edge until they are clear,
## sometimes to the left of the cards, sometimes to the right, and watch the cards from there; DODGE_BACK
## seconds after the cards are down they come back. Not on the move with every twitch of the mouse over
## the hand, and not while a hand of his or his mouth needs the face somewhere (those go first).
func _drive_dodge(delta: float) -> void:
	if not _eyes.visible or _left or _aside_n > 0 or _mouth.visible or _hand_at_edge():
		_dodge_want = 0.0
		_covered_for = 0.0
		_dodge_x = lerpf(_dodge_x, 0.0, clampf(delta * 7.0, 0.0, 1.0))
		return
	var covered: bool = false
	if _cover.size.x > 0.0:
		for r: Rect2 in _eye_rects(-_dodge_x):
			if r.intersects(_cover.grow(DODGE_GAP)):
				covered = true
	if covered:
		_covered_for += delta
		_clear_for = 0.0
	else:
		_clear_for += delta
		_covered_for = 0.0
	# The place is worked out once, when they go (or when the hand changes), not again on the way there.
	var hand_changed: bool = absf(_cover.position.x - _cover_used.position.x) > 8.0 or absf(_cover.size.x - _cover_used.size.x) > 8.0
	if _covered_for >= DODGE_AFTER and (_dodge_want == 0.0 or hand_changed):
		_dodge_want = _dodge_offset()
		_cover_used = _cover
	elif _clear_for >= DODGE_BACK:
		_dodge_want = 0.0
	_dodge_x = lerpf(_dodge_x, _dodge_want, clampf(delta * 7.0, 0.0, 1.0))


## A hand of his is bringing a ball back (up at a start zone, where the eyes would slide to).
func _hand_at_edge() -> bool:
	for held: Held in _held.values():
		if held.stage == Stage.BACK:
			return true
	return false


## Whether the eyes are within EYES_ASIDE of x along the near edge: where they belong, or where they have
## slid to from the cards.
func _eyes_near(x: float) -> bool:
	return absf(x - face_x) < EYES_ASIDE or absf(x - face_x - _dodge_x) < EYES_ASIDE


## How far along the edge the eyes go to be clear of the cards: to the side they are on already, else to
## one picked by chance (or dodge_side); to the other when that one has no room before the corner of the
## table; with room on neither, as far as they may on the first.
func _dodge_offset() -> float:
	var most: float = _ext.x - DODGE_CORNER
	var side: float = signf(_dodge_want)
	if side == 0.0:
		side = dodge_side if dodge_side != 0.0 else (1.0 if randf() < 0.5 else -1.0)
		dodge_side = 0.0
	for sgn: float in [side, -side]:
		for n: int in range(1, 90):
			var d: float = sgn * n * 0.4
			if absf(face_x + d) > most:
				break
			var clear: bool = true
			for r: Rect2 in _eye_rects(d - _dodge_x):
				if r.intersects(_cover.grow(DODGE_GAP)):
					clear = false
			if clear:
				return d
	return side * most - face_x


## The two eyes on the screen if they were `shift` further along the near edge than they are.
func _eye_rects(shift: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var view: Camera3D = get_viewport().get_camera_3d()
	if view == null:
		return out
	var move: Vector3 = global_transform.basis * Vector3(shift, 0, 0)
	var tilt := Basis(Vector3.RIGHT, _lids.rotation.x)
	for e: float in [-1.0, 1.0]:
		var r := Rect2()
		var first: bool = true
		for i: int in 8:
			var a: float = TAU * i / 8.0
			var p: Vector3 = _eyes.global_transform * (tilt * Vector3(e * 1.45 + cos(a) * 1.35, 0.1 + sin(a) * 1.35, 0)) + move
			if view.is_position_behind(p):
				continue
			var s: Vector2 = view.unproject_position(p)
			if first:
				r = Rect2(s, Vector2.ZERO)
				first = false
			else:
				r = r.expand(s)
		out.append(r)
	return out


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


## Where the eyes look: at a ball being caught or one that rolls (pupils wide), else at the ball of the
## hero whose turn it is; they blink now and then, and narrow (squint) at a ball they keep, looking down.
func _drive_eyes(delta: float, state: GameState, bodies: Dictionary[String, BallBody]) -> void:
	var want := Vector2(0, 0.18)
	var busy: bool = false
	for held: Held in _held.values():
		if held.stage == Stage.CATCHING:
			want = _look_at(to_global(held.pos))
			busy = true
			break
	if not busy:
		for b: BallBody in bodies.values():
			if b.visible and b.motion == BallBody.Motion.MOVING and not _held.has(b.ball_id):
				want = _look_at(b.global_position)
				busy = true
				break
	if not busy:
		var id: String = str(state.active.get(state.to_act, ""))
		if bodies.has(id):
			var wb: BallBody = bodies[id]
			if wb.visible:
				want = _look_at(wb.global_position)
	if not busy and absf(_dodge_x) > 0.5:
		# Aside, they watch the cards they made room for.
		want = Vector2(-signf(_dodge_x) * 0.36, -0.22)
	_look = _look.lerp(want, clampf(delta * 9.0, 0.0, 1.0))
	if squint > 0.01:
		_look = _look.lerp(Vector2(0, -0.3), squint * 0.6)
	_wide = lerpf(_wide, 0.5 if busy else 0.22, clampf(delta * 8.0, 0.0, 1.0))
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_in = 2.6
		_blink = 0.2
	_blink = maxf(0.0, _blink - delta)
	var shut: float = 1.0 - absf(_blink - 0.1) / 0.1 if _blink > 0.0 else 0.0
	_lids.scale.y = lerpf(1.0, 0.06, shut) * lerpf(1.0, 0.4, squint) * lerpf(1.0, 0.05, closed)
	for i: int in _irises.size():
		_irises[i].position = Vector3(_look.x * 0.8, _look.y * 0.8, 0.02)
		_cut_at(_irises[i], _look * 0.8, 1.0)
		_pupils[i].position = Vector3(_look.x, _look.y, 0.04)
		_pupils[i].scale.x = _wide
		_cut_at(_pupils[i], _look, _wide)


## In the eyes' own plane: sideways is sideways, up is away from the camera.
func _look_at(p: Vector3) -> Vector2:
	var loc: Vector3 = _eyes.global_transform.affine_inverse() * p
	var d := Vector2(loc.x, -loc.z)
	return d.normalized() * 0.4 * clampf(d.length() / 6.0, 0.0, 1.0)
