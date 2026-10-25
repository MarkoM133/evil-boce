class_name MeshKit
extends RefCounted
## Small procedural mesh helpers. Godot treats clockwise triangles as front faces;
## add_tri takes the wanted facing and fixes the winding itself.


static func add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, want: Vector3) -> void:
	if (b - a).cross(c - a).dot(want) > 0.0:
		var tp: Vector3 = b
		b = c
		c = tp
		var tn: Vector3 = nb
		nb = nc
		nc = tn
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)


static func add_flat_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, want: Vector3) -> void:
	var n: Vector3 = want.normalized()
	add_tri(st, a, b, c, n, n, n, want)


## Unit hemisphere, open at the equator; `top` points it up (+y), otherwise down.
static func hemisphere(top: bool, segments: int = 48, rings: int = 14) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sy: float = 1.0 if top else -1.0
	for i: int in rings:
		var p0: float = PI * 0.5 * float(i) / rings
		var p1: float = PI * 0.5 * float(i + 1) / rings
		for j: int in segments:
			var t0: float = TAU * float(j) / segments
			var t1: float = TAU * float(j + 1) / segments
			var a := Vector3(sin(p0) * cos(t0), cos(p0) * sy, sin(p0) * sin(t0))
			var b := Vector3(sin(p0) * cos(t1), cos(p0) * sy, sin(p0) * sin(t1))
			var c := Vector3(sin(p1) * cos(t0), cos(p1) * sy, sin(p1) * sin(t0))
			var d := Vector3(sin(p1) * cos(t1), cos(p1) * sy, sin(p1) * sin(t1))
			if i > 0:
				add_tri(st, a, b, c, a, b, c, (a + b + c) / 3.0)
			add_tri(st, b, d, c, b, d, c, (b + c + d) / 3.0)
	return st.commit()


## Flat ring in the xz plane (inner 0 = disc), facing +y or -y.
static func annulus(inner: float, outer: float, up: bool, segments: int = 48) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var want: Vector3 = Vector3.UP if up else Vector3.DOWN
	for j: int in segments:
		var t0: float = TAU * float(j) / segments
		var t1: float = TAU * float(j + 1) / segments
		var o0 := Vector3(cos(t0), 0, sin(t0)) * outer
		var o1 := Vector3(cos(t1), 0, sin(t1)) * outer
		if inner <= 0.0:
			add_flat_tri(st, Vector3.ZERO, o0, o1, want)
		else:
			var i0 := Vector3(cos(t0), 0, sin(t0)) * inner
			var i1 := Vector3(cos(t1), 0, sin(t1)) * inner
			add_flat_tri(st, i0, o0, o1, want)
			add_flat_tri(st, i0, o1, i1, want)
	return st.commit()


## Flat ribbon along `points` (y kept), into an ImmediateMesh surface already begun
## with PRIMITIVE_TRIANGLES. Use a double-sided material.
static func ribbon(im: ImmediateMesh, points: PackedVector3Array, width: float, color: Color) -> void:
	if points.size() < 2:
		return
	im.surface_set_color(color)
	for i: int in range(1, points.size()):
		var a: Vector3 = points[i - 1]
		var b: Vector3 = points[i]
		var d := Vector3(b.x - a.x, 0, b.z - a.z)
		if d.length_squared() < 0.000001:
			continue
		var side: Vector3 = Vector3.UP.cross(d.normalized()) * width * 0.5
		im.surface_add_vertex(a - side)
		im.surface_add_vertex(a + side)
		im.surface_add_vertex(b + side)
		im.surface_add_vertex(a - side)
		im.surface_add_vertex(b + side)
		im.surface_add_vertex(b - side)


static func unshaded(color: Color, double_sided: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
