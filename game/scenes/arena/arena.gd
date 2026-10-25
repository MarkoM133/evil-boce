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
## Hills (Ramp) and wind arrows drawn over the terrain, rebuilt when the terrain changes.
var _props: Node3D
var _props_key: String = ""
## Wind arrows: [MeshInstance3D, base position, unit direction (x, z), phase].
var _arrows: Array[Array] = []
var _time: float = 0.0
static var _chevron: ArrayMesh


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
	_props = Node3D.new()
	_props.name = "TerrainProps"
	add_child(_props)
	_props_key = ""
	_refresh_props()


func _process(delta: float) -> void:
	if absf(_emphasis - _emphasis_goal) > 0.001:
		_emphasis = move_toward(_emphasis, _emphasis_goal, delta / 0.15)
		_ground_mat.set_shader_parameter("emphasis", _emphasis)
	if not _arrows.is_empty():
		# Wind: chevrons drift downwind and fade in and out.
		_time += delta
		for a: Array in _arrows:
			var mi: MeshInstance3D = a[0]
			var base: Vector3 = a[1]
			var dir: Vector2 = a[2]
			var phase: float = a[3]
			var k: float = fposmod(_time * 0.7 + phase, 1.0)
			mi.position = base + Vector3(dir.x, 0, dir.y) * (k - 0.5) * map.hex_size * 0.9
			mi.transparency = 1.0 - 0.75 * sin(k * PI)


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


## Ground height at `pos` (a Ramp hill), so pieces standing there can be drawn on top.
func height_at(pos: Vector3) -> float:
	return TerrainPhysics.height(terrain, map, tuning, Vector2(pos.x, pos.z))


func hill_radius() -> float:
	return TerrainPhysics.hill_radius(map)


func _refresh_props() -> void:
	if _props == null:
		return
	var key: String = JSON.stringify(terrain.to_dict())
	if key == _props_key:
		return
	_props_key = key
	for c: Node in _props.get_children():
		c.queue_free()
	_arrows.clear()
	var hills: Dictionary[Vector2i, bool] = {}
	for a: Vector2i in terrain.cells:
		match terrain.at(a):
			Terrain.Type.RAMP:
				hills[terrain.center_of(a)] = true
			Terrain.Type.WIND:
				_add_arrow(a, terrain.dir_of(a))
	for c: Vector2i in hills:
		var mi := MeshInstance3D.new()
		mi.mesh = _hill_mesh(hill_radius(), tuning.hill_height)
		# The ground shader works from world x / z, so the hill keeps the hex lines and colour.
		mi.material_override = _ground_mat
		mi.position = hex_center(c)
		_props.add_child(mi)


func _add_arrow(a: Vector2i, dir: int) -> void:
	var d: Vector2 = TerrainPhysics.wind_vector(dir)
	var mi := MeshInstance3D.new()
	mi.mesh = _chevron_mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var base: Vector3 = hex_center(a) + Vector3(0, 0.02, 0)
	mi.position = base
	mi.scale = Vector3.ONE * map.hex_size
	# The chevron points along +x; turn it to the wind (x, z).
	mi.rotation.y = -atan2(d.y, d.x)
	_props.add_child(mi)
	_arrows.append([mi, base, d, randf()])


## A paraboloid cap: height h at the centre, 0 at radius r (the shape height_at() follows).
static func _hill_mesh(r: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: int = 10
	var segs: int = 40
	var pts: Array[Vector3] = []
	for i: int in rings + 1:
		var k: float = float(i) / rings
		for j: int in segs + 1:
			var ang: float = TAU * j / segs
			pts.append(Vector3(cos(ang) * k * r, h * (1.0 - k * k) + 0.005, sin(ang) * k * r))
	for i: int in rings:
		for j: int in segs:
			var a: Vector3 = pts[i * (segs + 1) + j]
			var b: Vector3 = pts[(i + 1) * (segs + 1) + j]
			var c: Vector3 = pts[(i + 1) * (segs + 1) + j + 1]
			var d: Vector3 = pts[i * (segs + 1) + j + 1]
			for v: Vector3 in [a, c, b, a, d, c]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## A flat ">" on the ground, pointing along +x, about half a hex long.
static func _chevron_mesh() -> ArrayMesh:
	if _chevron != null:
		return _chevron
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w: float = 0.09
	for side: float in [1.0, -1.0]:
		var tip := Vector3(0.22, 0, 0)
		var back := Vector3(-0.12, 0, 0.26 * side)
		var n: Vector3 = Vector3(0, 0, -side) * w
		var quad: Array[Vector3] = [back - n, tip - n, tip + n, back + n]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.add_vertex(quad[idx])
	_chevron = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 1.0, 0.98, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_chevron.surface_set_material(0, mat)
	return _chevron


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
	_refresh_props()


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
