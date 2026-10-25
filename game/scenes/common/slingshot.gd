class_name Slingshot
extends RefCounted
## Drag-and-release aiming for one ball: pull away from the ball, the arrow points the other
## way, power = drag length on screen (full at PhysicsTuning.max_drag_screen_fraction of the
## screen height). Draws the band and arrow into its own mesh; add `make_instance()` to the scene.

var tuning: PhysicsTuning
var mesh := ImmediateMesh.new()
var material: StandardMaterial3D
var ball: BallBody
var power: float = 0.0
var dir := Vector3.FORWARD
var pull := Vector3.ZERO


func _init(tuning_: PhysicsTuning) -> void:
	tuning = tuning_
	material = MeshKit.unshaded(Color.WHITE)
	material.no_depth_test = false


func make_instance() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func is_aiming() -> bool:
	return ball != null


func start(b: BallBody) -> void:
	ball = b
	power = 0.0
	pull = Vector3.ZERO


func cancel() -> void:
	ball = null
	power = 0.0
	mesh.clear_surfaces()


## True when the current pull is strong enough to count as a throw.
func is_throw() -> bool:
	return ball != null and power >= tuning.min_power


## Recomputes power and direction from the mouse, then redraws.
func update(cam: Camera3D, mouse: Vector2, screen_height: float) -> void:
	if ball == null:
		return
	var at: Vector3 = ball.global_position
	var full: float = tuning.max_drag_screen_fraction * screen_height
	power = clampf(mouse.distance_to(cam.unproject_position(at)) / full, 0.0, 1.0)
	var g: Variant = Plane(Vector3.UP, 0.0).intersects_ray(cam.project_ray_origin(mouse), cam.project_ray_normal(mouse))
	if g != null:
		var gp: Vector3 = g
		var p := Vector3(gp.x - at.x, 0, gp.z - at.z)
		if p.length() > 0.05:
			dir = -p.normalized()
			pull = p
	draw()


func draw() -> void:
	mesh.clear_surfaces()
	if not is_throw():
		return
	var at: Vector3 = ball.global_position
	var r: float = ball.radius()
	var base := Vector3(at.x, 0.05, at.z)
	var side: Vector3 = Vector3.UP.cross(dir)
	var len: float = r + 0.3 + power * 4.0 * tuning.hex_spacing()
	var color: Color = Color.WHITE.lerp(Palette.GOLD, power)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	MeshKit.ribbon(mesh, PackedVector3Array([base, base + pull.limit_length(len * 1.2)]), 0.05, Color(1, 1, 1, 0.35))
	var start_at: Vector3 = base + dir * (r + 0.15)
	var head: Vector3 = base + dir * len
	MeshKit.ribbon(mesh, PackedVector3Array([start_at, head]), 0.16, Color(color, 0.95))
	var hw: float = 0.38
	mesh.surface_set_color(Color(color, 0.95))
	mesh.surface_add_vertex(head + side * hw)
	mesh.surface_add_vertex(head - side * hw)
	mesh.surface_add_vertex(head + dir * 0.6)
	mesh.surface_end()
