class_name HD2D
extends RefCounted
## Shared "HD-2D" look: pixel sprites in a lit 3D diorama with bloom,
## tilt-shift depth of field, fog and drifting particles. Everything here
## runs on Godot's Mobile renderer; heavier desktop-only effects (volumetric
## fog, SSAO, SSR) are deliberately avoided and faked with fog and particles.

## Size of one sprite pixel in world units. 24 px sprite ~ 1.5 m tall.
const PIXEL_SIZE := 0.0625


static func build_environment(parent: Node, mood := {}) -> WorldEnvironment:
	var quality: int = Settings.quality
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = mood.get("sky_top", Color("141433"))
	sky_mat.sky_horizon_color = mood.get("sky_horizon", Color("c98a6a"))
	sky_mat.ground_horizon_color = mood.get("sky_horizon", Color("c98a6a")).darkened(0.3)
	sky_mat.ground_bottom_color = Color("0b0b18")
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = mood.get("ambient", 0.4)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = mood.get("exposure", 1.0)

	env.glow_enabled = quality > Settings.Quality.LOW
	env.glow_intensity = 0.9
	env.glow_strength = 1.0
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	env.fog_enabled = true
	env.fog_light_color = mood.get("fog", Color("3a3458"))
	env.fog_density = mood.get("fog_density", 0.007)
	env.fog_sky_affect = 0.3

	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	parent.add_child(world_env)
	return world_env


## Tilt-shift depth of field: sharp band around the focus distance, blurred
## foreground and background. This is what makes scenes read as miniatures.
static func build_camera_attributes(focus_distance: float) -> CameraAttributesPractical:
	var attrs := CameraAttributesPractical.new()
	if Settings.quality == Settings.Quality.HIGH:
		attrs.dof_blur_far_enabled = true
		attrs.dof_blur_far_distance = focus_distance + 6.0
		attrs.dof_blur_far_transition = 8.0
		attrs.dof_blur_near_enabled = true
		attrs.dof_blur_near_distance = maxf(1.0, focus_distance - 6.0)
		attrs.dof_blur_near_transition = 3.0
		attrs.dof_blur_amount = 0.12
	return attrs


static func build_sun(parent: Node, color := Color("ffcf9a"), energy := 1.3, angles := Vector3(-38, -35, 0)) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.light_color = color
	sun.light_energy = energy
	sun.rotation_degrees = angles
	sun.shadow_enabled = Settings.quality > Settings.Quality.LOW
	sun.directional_shadow_max_distance = 40.0
	parent.add_child(sun)
	return sun


## A pixel-art character standing on the ground, with a blob shadow.
static func make_sprite_actor(texture: Texture2D, scale := 1.0, flip := false) -> Node3D:
	var root := Node3D.new()
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.texture = texture
	sprite.pixel_size = PIXEL_SIZE * scale
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	# Unshaded keeps the pixel art's palette exact; the blob shadow and bloom
	# ground the sprite in the lit scene.
	sprite.shaded = false
	sprite.flip_h = flip
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.offset = Vector2(0, texture.get_height() / 2.0)
	root.add_child(sprite)

	var shadow := Sprite3D.new()
	shadow.name = "Shadow"
	shadow.texture = PixelArt.texture(&"soft_circle")
	shadow.modulate = Color(0, 0, 0, 0.55)
	shadow.pixel_size = texture.get_width() * PIXEL_SIZE * scale / 28.0
	shadow.rotation_degrees.x = -90
	shadow.position.y = 0.02
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shadow)
	return root


static func material(color: Color, roughness := 0.9, metallic := 0.0, emission := Color.BLACK, emission_energy := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	if emission_energy > 0.0:
		mat.emission_enabled = true
		mat.emission = emission
		mat.emission_energy_multiplier = emission_energy
	return mat


static func add_mesh(parent: Node, mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func add_pine(parent: Node, pos: Vector3, height: float) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.18
	trunk.height = height * 0.35
	add_mesh(parent, trunk, material(Color("3b2a22")), pos + Vector3(0, height * 0.175, 0))
	for i in 3:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = height * (0.34 - i * 0.07)
		cone.height = height * 0.45
		cone.radial_segments = 7
		var y := height * (0.4 + i * 0.2)
		add_mesh(parent, cone, material(Color("1f3b33").lerp(Color("2f5a45"), i * 0.3)), pos + Vector3(0, y, 0))


static func add_rock(parent: Node, pos: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(size, size * rng.randf_range(0.5, 1.2), size * rng.randf_range(0.7, 1.1))
	var rot := Vector3(rng.randf_range(-12, 12), rng.randf_range(0, 360), rng.randf_range(-12, 12))
	add_mesh(parent, box, material(Color("4d4a55").lerp(Color("6b6272"), rng.randf())), pos + Vector3(0, box.size.y * 0.35, 0), rot)


## Drifting white petals and violet void motes: the game's visual signature.
static func add_petals(parent: Node, extents: Vector3, amount := 80) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = amount if Settings.quality > Settings.Quality.LOW else amount / 3
	particles.lifetime = 9.0
	particles.preprocess = 9.0
	particles.visibility_aabb = AABB(-extents * 1.5, extents * 3.0)

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.direction = Vector3(1, -0.4, 0.3)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0, -0.25, 0)
	pm.angular_velocity_min = -90.0
	pm.angular_velocity_max = 90.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.97, 0.95, 0.0))
	ramp.set_color(1, Color(1.0, 0.97, 0.95, 0.0))
	ramp.add_point(0.1, Color(1.0, 0.96, 0.96, 1.0))
	ramp.add_point(0.8, Color(0.85, 0.75, 1.0, 1.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	particles.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.14, 0.14)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = PixelArt.texture(&"petal")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.85, 1.0)
	mat.emission_energy_multiplier = 0.6
	quad.material = mat
	particles.draw_pass_1 = quad
	parent.add_child(particles)
	return particles


## Floating label that rises and fades, for damage numbers.
static func pop_label(parent: Node, pos: Vector3, text: String, color: Color, size := 64) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.outline_size = 12
	label.modulate = color
	label.outline_modulate = Color(0.05, 0.03, 0.1)
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = pos
	parent.add_child(label)
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", pos.y + 0.9, 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 0.4).set_delay(0.6)
	tween.chain().tween_callback(label.queue_free)
