class_name TableEnv
extends RefCounted
## Environment and lights for a table scene (sandbox, match). Quality (Settings) turns the
## costlier parts off on "low" and sharpens the shadows on "high".


static func add_to(parent: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff3e0")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = GameSettings.quality() != "low"
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	var quality: String = GameSettings.quality()
	env.ssao_enabled = quality != "low"
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.5
	env.fog_enabled = true
	env.fog_light_color = Palette.BG
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, 32, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = quality != "low"
	if quality == "high":
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
		RenderingServer.directional_shadow_atlas_set_size(8192, true)
	else:
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		RenderingServer.directional_shadow_atlas_set_size(4096, true)
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 120.0
	parent.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-30, 200, 0)
	rim.light_energy = 0.3
	rim.light_color = Color("bfd8ff")
	parent.add_child(rim)
