class_name Arena
extends Node3D
## The table: a raised hex map with an open edge (falling off is ring-out), a start strip
## along the near (+z, team 0) and far (-z, team 1) edges, all standing on a big table.
## Map, strips and table top are at y = 0 except the table, which is DEPTH lower.

const DEPTH: float = 0.6
const STRIP_DEPTH: float = 2.2
const SHADER: Shader = preload("res://scenes/arena/hex_ground.gdshader")

var map: HexMap
var tuning: PhysicsTuning

var _cells_img: Image
var _cells_tex: ImageTexture
var _ground_mat := ShaderMaterial.new()
## Terrain to draw; owned by the sandbox or the rules engine, see set_terrain().
var terrain: TerrainMap = TerrainMap.new()
var _range: Dictionary[Vector2i, bool] = {}
var _marks: Dictionary[Vector2i, bool] = {}
var _emphasis: float = 0.0
var _emphasis_goal: float = 0.0
## Per team: x_min, x_max, inner z (strip begins), far z (strip ends).
var _strips: Array[Vector4] = []


func build(map_: HexMap, tuning_: PhysicsTuning) -> void:
	map = map_
	tuning = tuning_
	for c: Node in get_children():
		c.queue_free()
	_range.clear()
	_marks.clear()
	_strips.clear()
	_cells_img = Image.create(map.size, map.size, false, Image.FORMAT_RGBA8)
	_cells_tex = ImageTexture.create_from_image(_cells_img)
	_refresh_cells()
	_ground_mat.shader = SHADER
	_ground_mat.set_shader_parameter("cells", _cells_tex)
	_ground_mat.set_shader_parameter("map_n", map.size)
	_ground_mat.set_shader_parameter("hex_size", map.hex_size)
	_ground_mat.set_shader_parameter("origin", map.origin)
	_build_geometry()


func _process(delta: float) -> void:
	if absf(_emphasis - _emphasis_goal) > 0.001:
		_emphasis = move_toward(_emphasis, _emphasis_goal, delta / 0.15)
		_ground_mat.set_shader_parameter("emphasis", _emphasis)


# --- queries ----------------------------------------------------------------

func hex_at(pos: Vector3) -> Vector2i:
	return map.from_world(Vector2(pos.x, pos.z))


func hex_center(a: Vector2i) -> Vector3:
	var p: Vector2 = map.to_world(a)
	return Vector3(p.x, 0, p.y)


func area_at(pos: Vector3) -> BallWorld.Area:
	if map.contains(hex_at(pos)):
		return BallWorld.Area.MAP
	return BallWorld.Area.STRIP if strip_at(pos) >= 0 else BallWorld.Area.VOID


## Team whose start strip is under `pos`, or -1.
func strip_at(pos: Vector3) -> int:
	if map.contains(hex_at(pos)):
		return -1
	for team: int in _strips.size():
		var s: Vector4 = _strips[team]
		if pos.x < s.x or pos.x > s.y:
			continue
		if pos.z >= minf(s.z, s.w) and pos.z <= maxf(s.z, s.w):
			return team
	return -1


## Left and right x of a team's strip.
func strip_x_range(team: int) -> Vector2:
	var s: Vector4 = _strips[team]
	return Vector2(s.x, s.y)


## A point on the middle line of a team's strip, x clamped to the strip.
func strip_point(team: int, x: float, margin: float = 0.0) -> Vector3:
	var s: Vector4 = _strips[team]
	var peak: float = s.z + (0.5 * map.hex_size if team == 0 else -0.5 * map.hex_size)
	return Vector3(clampf(x, s.x + margin, s.y - margin), 0, (peak + s.w) * 0.5)


func terrain_at(pos: Vector3) -> Terrain.Type:
	return terrain.at(hex_at(pos))


## Rough size of the whole table, for the camera.
func extent() -> Vector2:
	return Vector2(map.size * map.spacing(), map.size * 1.5 * map.hex_size + 2.0 * STRIP_DEPTH)


# --- marks on the ground ----------------------------------------------------

## Draws `tm` from now on; call refresh_terrain() after changing it.
func set_terrain(tm: TerrainMap) -> void:
	terrain = tm
	_refresh_cells()


func refresh_terrain() -> void:
	_refresh_cells()


func show_range(cells: Array[Vector2i], marked: Array[Vector2i]) -> void:
	_range.clear()
	_marks.clear()
	for a: Vector2i in cells:
		_range[a] = true
	for a: Vector2i in marked:
		_marks[a] = true
	_refresh_cells()


func set_grid_emphasis(on: bool) -> void:
	_emphasis_goal = 1.0 if on else 0.0


func _refresh_cells() -> void:
	if _cells_img == null:
		return
	_cells_img.fill(Color(0, 0, 0, 1))
	for a: Vector2i in map.cells():
		var o: Vector2i = Hex.axial_to_offset(a)
		var t: int = terrain.at(a)
		var g: float = 1.0 if _range.has(a) else 0.0
		var b: float = 1.0 if _marks.has(a) else 0.0
		if t != 0 or g > 0.0 or b > 0.0:
			_cells_img.set_pixel(o.x, o.y, Color(t / 255.0, g, b, 1.0))
	_cells_tex.update(_cells_img)


# --- geometry ---------------------------------------------------------------

func _build_geometry() -> void:
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	var strip_st: Array[SurfaceTool] = []
	for team: int in 2:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		strip_st.append(st)
	var down := Vector3(0, -DEPTH, 0)
	var s: float = map.hex_size
	# Zig-zag edge points of the two strip rows, left to right.
	var zig: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array()]

	for a: Vector2i in map.cells():
		var c2: Vector2 = map.to_world(a)
		var c := Vector3(c2.x, 0, c2.y)
		var row: int = Hex.axial_to_offset(a).y
		for i: int in 6:
			var p0: Vector2 = c2 + Hex.corner(i - 1, s)
			var p1: Vector2 = c2 + Hex.corner(i, s)
			var v0 := Vector3(p0.x, 0, p0.y)
			var v1 := Vector3(p1.x, 0, p1.y)
			MeshKit.add_flat_tri(top, c, v0, v1, Vector3.UP)
			if map.contains(a + Hex.DIRECTIONS[i]):
				continue
			var team: int = -1
			if row == map.size - 1 and (i == 1 or i == 2):
				team = 0
			elif row == 0 and (i == 4 or i == 5):
				team = 1
			if team >= 0:
				_add_zig(zig[team], p0, p1)
				continue
			var out := Vector3(cos(deg_to_rad(60.0 * i)), 0, sin(deg_to_rad(60.0 * i)))
			MeshKit.add_flat_tri(sides, v0, v1, v1 + down, out)
			MeshKit.add_flat_tri(sides, v0, v1 + down, v0 + down, out)

	for team: int in 2:
		_build_strip(team, zig[team], strip_st[team], sides, down)

	var mesh := ArrayMesh.new()
	top.commit(mesh)
	sides.commit(mesh)
	strip_st[0].commit(mesh)
	strip_st[1].commit(mesh)
	var mi := MeshInstance3D.new()
	mi.name = "Map"
	mi.mesh = mesh
	mi.set_surface_override_material(0, _ground_mat)
	mi.set_surface_override_material(1, _plain(Color("201a15"), 0.95))
	mi.set_surface_override_material(2, _plain(_strip_color(0), 0.8))
	mi.set_surface_override_material(3, _plain(_strip_color(1), 0.8))
	add_child(mi)

	var body := StaticBody3D.new()
	body.name = "MapBody"
	body.collision_layer = BallBody.LAYER_GROUND
	body.collision_mask = 0
	body.physics_material_override = _ground_material()
	var shape := CollisionShape3D.new()
	var tri: ConcavePolygonShape3D = mesh.create_trimesh_shape()
	tri.backface_collision = true
	shape.shape = tri
	body.add_child(shape)
	add_child(body)

	_build_table()


func _add_zig(points: PackedVector2Array, p0: Vector2, p1: Vector2) -> void:
	for p: Vector2 in [p0, p1]:
		var dup: bool = false
		for q: Vector2 in points:
			if q.distance_to(p) < 0.001:
				dup = true
				break
		if not dup:
			points.append(p)


func _build_strip(team: int, zig: PackedVector2Array, st: SurfaceTool, sides: SurfaceTool,
		down: Vector3) -> void:
	var pts: Array[Vector2] = []
	for p: Vector2 in zig:
		pts.append(p)
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var sign_z: float = 1.0 if team == 0 else -1.0
	var inner: float = pts[0].y
	var peak: float = inner
	for p: Vector2 in pts:
		peak = maxf(peak, p.y) if team == 0 else minf(peak, p.y)
		inner = minf(inner, p.y) if team == 0 else maxf(inner, p.y)
	var far: float = peak + sign_z * STRIP_DEPTH
	var want := Vector3.UP
	for i: int in range(1, pts.size()):
		var a := Vector3(pts[i - 1].x, 0, pts[i - 1].y)
		var b := Vector3(pts[i].x, 0, pts[i].y)
		var fa := Vector3(a.x, 0, far)
		var fb := Vector3(b.x, 0, far)
		MeshKit.add_flat_tri(st, a, b, fb, want)
		MeshKit.add_flat_tri(st, a, fb, fa, want)
	var x0: float = pts[0].x
	var x1: float = pts[pts.size() - 1].x
	var out_far := Vector3(0, 0, sign_z)
	var c0 := Vector3(x0, 0, far)
	var c1 := Vector3(x1, 0, far)
	MeshKit.add_flat_tri(sides, c0, c1, c1 + down, out_far)
	MeshKit.add_flat_tri(sides, c0, c1 + down, c0 + down, out_far)
	for end: int in 2:
		var x: float = x0 if end == 0 else x1
		var edge_z: float = pts[0].y if end == 0 else pts[pts.size() - 1].y
		var e0 := Vector3(x, 0, edge_z)
		var e1 := Vector3(x, 0, far)
		var out := Vector3(-1 if end == 0 else 1, 0, 0)
		MeshKit.add_flat_tri(sides, e0, e1, e1 + down, out)
		MeshKit.add_flat_tri(sides, e0, e1 + down, e0 + down, out)
	_strips.append(Vector4(x0, x1, inner, far))


func _build_table() -> void:
	var ext: Vector2 = extent()
	var size := Vector3(ext.x * 2.2, 0.8, ext.y * 2.0)
	var table := MeshInstance3D.new()
	table.name = "Table"
	var box := BoxMesh.new()
	box.size = size
	table.mesh = box
	table.material_override = _plain(Color("241c16"), 0.9)
	table.position = Vector3(0, -DEPTH - size.y * 0.5, 0)
	add_child(table)
	var body := StaticBody3D.new()
	body.name = "TableBody"
	body.collision_layer = BallBody.LAYER_GROUND
	body.collision_mask = 0
	body.physics_material_override = _ground_material()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	shape.position = table.position
	body.add_child(shape)
	add_child(body)


## Frictionless, and absorbent so balls never bounce off the ground.
static func _ground_material() -> PhysicsMaterial:
	var m := PhysicsMaterial.new()
	m.friction = 0.0
	m.bounce = 1.0
	m.absorbent = true
	return m


static func _strip_color(team: int) -> Color:
	var c: Color = Palette.team(team)
	return Color.from_hsv(c.h, c.s * 0.55, 0.26)


static func _plain(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m
