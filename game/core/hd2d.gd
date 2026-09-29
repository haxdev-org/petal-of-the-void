class_name HD2D
extends RefCounted
## Shared "HD-2D" look: pixel-art sprites in a lit 3D diorama with pixel
## textures, real shadows, bloom, tilt-shift depth of field, fog, light shafts
## and drifting petals. Everything here runs on Godot's Mobile renderer;
## desktop-only effects (volumetric fog, SSAO, SSR) are faked with fog planes,
## additive shafts and baked-looking pixel shading instead.

const TEX_DIR := "res://assets/textures/"
const MODEL_DIR := "res://assets/models/"
## One texture tile covers this many metres (44 px/m at 64 px tiles).
const TILE_M := 1.45

## Fixed Baldur's Gate-style view: diagonal yaw, steep pitch, orthographic.
const ISO_YAW := 45.0
const ISO_PITCH := 42.0

static var _tex_cache: Dictionary = {}
static var _model_cache: Dictionary = {}


# --- assets -------------------------------------------------------------------

static func tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		_tex_cache[name] = load(TEX_DIR + name + ".png")
	return _tex_cache[name]


static func model(name: String) -> PackedScene:
	if not _model_cache.has(name):
		_model_cache[name] = load(MODEL_DIR + name + ".glb")
	return _model_cache[name]


## Tiled pixel-art material. Nearest filtering keeps pixels crisp; mipmaps
## stop distant ground from shimmering.
## `uv_scale` is how many times the tile repeats across the mesh's UV space:
## for a PlaneMesh that is its size in metres divided by TILE_M; Blender props
## already carry metre-based UVs so they use Vector3.ONE.
static func tile_material(name: String, uv_scale := Vector3.ONE, roughness := 0.95, double_sided := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex("tile_" + name)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.uv1_scale = uv_scale
	if ResourceLoader.exists(TEX_DIR + "tile_" + name + "_n.png"):
		mat.normal_enabled = true
		mat.normal_texture = tex("tile_" + name + "_n")
		mat.normal_scale = 0.8
	mat.roughness = roughness
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if double_sided:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


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


static func sprite_material(name: String, unshaded := false, additive := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex(name)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	if additive:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	else:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.albedo_color = Color(0.97, 0.95, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat


# --- camera -----------------------------------------------------------------------

## Camera offset from its target for the isometric view.
static func iso_offset(distance := 40.0) -> Vector3:
	var p := deg_to_rad(ISO_PITCH)
	var y := deg_to_rad(ISO_YAW)
	return Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * distance


## World direction that maps to screen-right, and to screen-up along the ground.
static func iso_right() -> Vector3:
	return Vector3(1, 0, -1).normalized()


static func iso_up() -> Vector3:
	return Vector3(-1, 0, -1).normalized()


## Upright sprites are foreshortened by the steep camera; scale them back up.
static func iso_sprite_stretch() -> float:
	return 1.0 / cos(deg_to_rad(ISO_PITCH))


static func build_iso_camera(parent: Node, target: Vector3, size: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	cam.near = 1.0
	cam.far = 160.0
	cam.position = target + iso_offset()
	cam.attributes = build_camera_attributes(iso_offset().length())
	parent.add_child(cam)
	cam.look_at(target)
	return cam


# --- environment ------------------------------------------------------------------

static func build_environment(parent: Node, mood := {}) -> WorldEnvironment:
	var quality: int = Settings.quality
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = mood.get("sky_top", Color("1a1a3f"))
	sky_mat.sky_horizon_color = mood.get("sky_horizon", Color("d8946c"))
	sky_mat.ground_horizon_color = mood.get("sky_horizon", Color("d8946c")).darkened(0.35)
	sky_mat.ground_bottom_color = Color("0b0b18")
	sky_mat.sun_angle_max = 25.0
	sky_mat.sun_curve = 0.2
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = mood.get("ambient_color", Color("7c7aa8"))
	env.ambient_light_energy = mood.get("ambient", 0.9)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = mood.get("exposure", 1.05)
	env.tonemap_white = 4.0

	env.glow_enabled = quality > Settings.Quality.LOW
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = mood.get("fog", Color("46405f"))
	env.fog_density = mood.get("fog_density", 0.006)
	env.fog_sky_affect = 0.25
	env.fog_aerial_perspective = 0.6

	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04

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
		attrs.dof_blur_far_distance = focus_distance + 7.0
		attrs.dof_blur_far_transition = 10.0
		attrs.dof_blur_near_enabled = true
		attrs.dof_blur_near_distance = maxf(1.0, focus_distance - 6.0)
		attrs.dof_blur_near_transition = 3.0
		attrs.dof_blur_amount = 0.1
	return attrs


## Sun from the camera's upper left, slightly in front, the same direction
## the sprites were rendered with, so props and characters agree.
static func sun_travel() -> Vector3:
	var forward := Vector3(-1, 0, -1).normalized()
	var right := iso_right()
	return (forward * 0.35 + right * 0.55 + Vector3.DOWN * 0.95).normalized()


static func build_sun(parent: Node, color := Color("ffd2a0"), energy := 1.5, angles := Vector3.ZERO) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.light_color = color
	sun.light_energy = energy
	parent.add_child(sun)
	sun.look_at_from_position(-sun_travel() * 20.0, Vector3.ZERO)
	parent.remove_child(sun)
	sun.shadow_enabled = Settings.quality > Settings.Quality.LOW
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	# The orthographic camera sits 40 m from its target, so the whole screen
	# has to fit inside the shadow range or its edges fall into darkness.
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_fade_start = 0.95
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.5
	sun.shadow_blur = 1.2
	sun.light_indirect_energy = 0.0
	parent.add_child(sun)
	return sun


## Full-screen vignette and a gentle colour grade, drawn over everything.
static func add_post_overlay(parent: Node, strength := 0.55) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 50
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float strength = 0.55;
void fragment() {
	vec3 col = texture(screen, SCREEN_UV).rgb;
	vec2 d = SCREEN_UV - vec2(0.5);
	float v = smoothstep(0.35, 0.95, length(d) * 1.35);
	// cool the shadows and warm the highlights very slightly
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, col * vec3(0.94, 0.96, 1.08), (1.0 - l) * 0.35);
	col = mix(col, col * vec3(1.05, 1.01, 0.96), l * 0.25);
	col *= 1.0 - v * strength;
	COLOR = vec4(col, 1.0);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("strength", strength)
	rect.material = mat
	layer.add_child(rect)
	parent.add_child(layer)
	return layer


# --- scenery ----------------------------------------------------------------------

static func add_mesh(parent: Node, mesh: Mesh, mat: Material, pos: Vector3, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


## Flat textured ground, `size` metres, centred on `pos`. `hole_radius` leaves
## a circular gap (around `pos`) for sunken terrain such as the crater.
static func add_ground(parent: Node, tile: String, size: Vector2, pos := Vector3.ZERO, hole_radius := 0.0, hole_centre := Vector3.ZERO) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cell := 2.0
	var nx := int(ceil(size.x / cell))
	var nz := int(ceil(size.y / cell))
	var origin := Vector3(-size.x / 2.0, 0, -size.y / 2.0)
	for iz in nz:
		for ix in nx:
			var a := origin + Vector3(ix * cell, 0, iz * cell)
			var centre := pos + a + Vector3(cell / 2.0, 0, cell / 2.0)
			if hole_radius > 0.0 and Vector2(centre.x - hole_centre.x, centre.z - hole_centre.z).length() < hole_radius:
				continue
			var b := a + Vector3(cell, 0, 0)
			var c := a + Vector3(cell, 0, cell)
			var d := a + Vector3(0, 0, cell)
			# Godot's front faces wind clockwise: a->b->c seen from above.
			for v: Vector3 in [a, b, c, a, c, d]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(v.x + pos.x, v.z + pos.z) / TILE_M)
				st.set_uv2(Vector2(v.x + pos.x, v.z + pos.z) / 9.0)
				st.add_vertex(v)
	st.index()
	st.generate_tangents()
	var plane := st.commit()
	# Give the flat mesh a little thickness in its bounding box, as the
	# built-in primitives do.
	plane.custom_aabb = AABB(Vector3(-size.x / 2.0, -0.5, -size.y / 2.0), Vector3(size.x, 1.0, size.y))
	var mat := tile_material(tile, Vector3.ONE)
	# Large-scale brightness variation hides the tile repeat.
	mat.detail_enabled = true
	mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	mat.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	mat.detail_albedo = tex("macro")
	mat.uv2_scale = Vector3.ONE
	mat.albedo_color = Color(1.18, 1.18, 1.18)
	var mi := add_mesh(parent, plane, mat, pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A textured patch laid over the ground (path, trodden clearing).
static func add_patch(parent: Node, tile: String, size: Vector2, pos: Vector3, rot_y := 0.0) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = size
	var mi := add_mesh(parent, plane, tile_material(tile, Vector3(size.x, size.y, 1.0) / TILE_M), pos + Vector3(0, 0.012, 0), Vector3(0, rot_y, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Soft-edged ground decal (clearing, crater) laid flat at `pos`.
static func add_decal(parent: Node, name: String, size: Vector2, pos: Vector3, rot_y := 0.0, height := 0.02) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var mat := sprite_material(name)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color.WHITE
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	var mi := add_mesh(parent, quad, mat, pos + Vector3(0, height, 0), Vector3(-90, rot_y, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A worn path: soft-sided strip running along local -Z, `length` metres long.
static func add_path(parent: Node, width: float, length: float, pos: Vector3, rot_y := 0.0) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(width, length)
	var mat := sprite_material("path_strip")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color.WHITE
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.uv1_scale = Vector3(1.0, length / (4.0 * TILE_M), 1.0)
	var mi := add_mesh(parent, quad, mat, pos + Vector3(0, 0.018, 0), Vector3(-90, rot_y, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Height of the crater terrain at radius r (mirrors tools/blender_props.py).
static func crater_height(r: float) -> float:
	var bowl := -1.1 * pow(maxf(0.0, 1.0 - pow(r / 3.4, 2.0)), 1.2) if r < 3.4 else 0.0
	var rim := 0.75 * exp(-pow((r - 4.0) / 0.9, 2.0))
	var blanket := 0.15 * exp(-pow((r - 5.5) / 1.5, 2.0))
	return bowl + rim + blanket


## The impact crater: real terrain (bowl, rim, ejecta) draped with the radial
## crater texture, plus smoke and embers still rising from the glass.
static func add_crater(parent: Node, pos: Vector3) -> Node3D:
	var inst: Node3D = model("crater").instantiate()
	inst.position = pos
	parent.add_child(inst)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex("crater")
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.normal_enabled = true
	mat.normal_texture = tex("crater_n")
	mat.normal_scale = 1.0
	mat.roughness = 0.6
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Heat still bleeding out of the glass.
	var ember := OmniLight3D.new()
	ember.light_color = Color("ff9a4a")
	ember.light_energy = 2.2
	ember.omni_range = 7.5
	ember.position = Vector3(0, 0.2, 0)
	inst.add_child(ember)
	var flicker := ember.create_tween().set_loops()
	flicker.tween_property(ember, "light_energy", 1.5, 1.3).set_trans(Tween.TRANS_SINE)
	flicker.tween_property(ember, "light_energy", 2.5, 1.1).set_trans(Tween.TRANS_SINE)
	_add_smoke(inst, Vector3(0, -0.9, 0))
	_add_embers(inst, Vector3(0, -0.9, 0))
	return inst


static func _add_smoke(parent: Node, pos: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 24 if Settings.quality > Settings.Quality.LOW else 8
	particles.lifetime = 7.0
	particles.preprocess = 7.0
	particles.position = pos
	particles.visibility_aabb = AABB(Vector3(-6, -1, -6), Vector3(12, 12, 12))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.6
	pm.direction = Vector3(0.2, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.25
	pm.initial_velocity_max = 0.5
	pm.gravity = Vector3(0.15, 0.12, 0.05)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.scale_min = 1.2
	pm.scale_max = 2.4
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0, 0.4))
	scale_curve.add_point(Vector2(1, 1.6))
	var sc := CurveTexture.new()
	sc.curve = scale_curve
	pm.scale_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.35, 0.3, 0.4, 0.0))
	ramp.add_point(0.15, Color(0.3, 0.26, 0.34, 0.35))
	ramp.set_color(1, Color(0.4, 0.38, 0.45, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	particles.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex("smoke")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = mat
	particles.draw_pass_1 = quad
	parent.add_child(particles)


static func _add_embers(parent: Node, pos: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.amount = 40 if Settings.quality > Settings.Quality.LOW else 12
	particles.lifetime = 3.0
	particles.preprocess = 3.0
	particles.position = pos
	particles.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 2.2
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.4
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0.1, 0.3, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.3, 1.0))
	ramp.set_color(1, Color(0.6, 0.1, 0.05, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	particles.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex("soft_circle")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.2)
	mat.emission_energy_multiplier = 3.0
	quad.material = mat
	particles.draw_pass_1 = quad
	parent.add_child(particles)


## Scatter flat decals (dirt patches, pebbles) over the ground.
static func add_ground_detail(parent: Node, rng: RandomNumberGenerator, area: Rect2, count: int, keep_clear: Callable) -> void:
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 4:
		attempts += 1
		var p := Vector3(rng.randf_range(area.position.x, area.end.x), 0, rng.randf_range(area.position.y, area.end.y))
		if not keep_clear.call(p):
			continue
		placed += 1
		if rng.randf() < 0.45:
			var s := rng.randf_range(2.0, 5.0)
			var d := add_decal(parent, "clearing", Vector2(s, s * rng.randf_range(0.6, 1.0)), p, rng.randf_range(0, 360), 0.006)
			d.material_override.albedo_color = Color(1, 1, 1, rng.randf_range(0.5, 0.9))
		else:
			var s := rng.randf_range(0.5, 0.9)
			add_decal(parent, "pebbles", Vector2(s, s * 0.75), p, rng.randf_range(0, 360), 0.008)


## Blender prop (assets/models/<name>.glb) with textures assigned by mesh name.
static func add_prop(parent: Node, name: String, pos: Vector3, rot_y := 0.0, scale := 1.0) -> Node3D:
	var inst: Node3D = model(name).instantiate()
	inst.position = pos
	inst.rotation_degrees.y = rot_y
	inst.scale = Vector3.ONE * scale
	parent.add_child(inst)
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		var n := mi.name.to_lower()
		if n.begins_with("trunk"):
			mi.material_override = tile_material("bark")
		elif n.begins_with("canopy"):
			mi.material_override = tile_material("needles", Vector3.ONE, 1.0, true)
		else:
			mi.material_override = tile_material("rock")
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return inst


static func add_pine(parent: Node, pos: Vector3, height: float, rng: RandomNumberGenerator = null) -> Node3D:
	var variant := 0 if height < 4.8 else (1 if height < 6.0 else 2)
	var base_h: float = [4.2, 5.4, 6.5][variant]
	var rot: float = rng.randf_range(0, 360) if rng else 0.0
	return add_prop(parent, "pine_%d" % variant, pos, rot, height / base_h)


static func add_rock(parent: Node, pos: Vector3, size: float, rng: RandomNumberGenerator) -> Node3D:
	var variant := 0 if size < 0.85 else (1 if size < 1.3 else 2)
	var base: float = [0.6, 1.0, 1.5][variant]
	return add_prop(parent, "boulder_%d" % variant, pos + Vector3(0, size * 0.22, 0), rng.randf_range(0, 360), size / base)


## Grass tufts and ferns as camera-facing pixel sprites, batched per variant.
static func add_undergrowth(parent: Node, rng: RandomNumberGenerator, area: Rect2, count: int, keep_clear: Callable) -> void:
	var budget := count if Settings.quality > Settings.Quality.LOW else count / 3
	var variants := ["grass_tuft_0", "grass_tuft_1", "grass_tuft_2", "fern"]
	var lists: Array = [[], [], [], []]
	var placed := 0
	var attempts := 0
	while placed < budget and attempts < budget * 4:
		attempts += 1
		var p := Vector3(rng.randf_range(area.position.x, area.end.x), 0, rng.randf_range(area.position.y, area.end.y))
		if not keep_clear.call(p):
			continue
		var v := 3 if rng.randf() < 0.18 else rng.randi_range(0, 2)
		lists[v].append(p)
		placed += 1
	for v in 4:
		if lists[v].is_empty():
			continue
		var t := tex(variants[v])
		var quad := QuadMesh.new()
		quad.size = Vector2(t.get_width(), t.get_height()) / 44.0
		quad.center_offset = Vector3(0, quad.size.y / 2.0, 0)
		var mat := sprite_material(variants[v], true)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		mat.billboard_keep_scale = true
		quad.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = quad
		mm.instance_count = lists[v].size()
		for i in lists[v].size():
			var s := rng.randf_range(0.85, 1.25)
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)), lists[v][i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)


## Layered pixel mountain ridges on the horizon, softened by fog.
static func add_mountains(parent: Node, distance := 55.0, rot_y := 0.0) -> void:
	for layer in 3:
		var t := tex("mountains_%d" % layer)
		var quad := QuadMesh.new()
		var width := 150.0 - layer * 25.0
		quad.size = Vector2(width, width * t.get_height() / t.get_width())
		var mat := sprite_material("mountains_%d" % layer, true)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		quad.material = mat
		var z := -(distance + (2 - layer) * 12.0)
		var pos := Vector3(0, quad.size.y * 0.32 - layer * 1.5, z).rotated(Vector3.UP, deg_to_rad(rot_y))
		var mi := add_mesh(parent, quad, mat, pos, Vector3(0, rot_y, 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Additive light shafts angled down from the sun.
static func add_light_shafts(parent: Node, rng: RandomNumberGenerator, positions: Array, sun_angles: Vector3) -> void:
	if Settings.quality == Settings.Quality.LOW:
		return
	for p: Vector3 in positions:
		var quad := QuadMesh.new()
		quad.size = Vector2(rng.randf_range(1.2, 2.6), rng.randf_range(9.0, 14.0))
		var mat := sprite_material("light_shaft", true, true)
		mat.albedo_color = Color(1.0, 0.92, 0.75, rng.randf_range(0.18, 0.32))
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		mat.no_depth_test = false
		quad.material = mat
		var mi := add_mesh(parent, quad, mat, p + Vector3(0, quad.size.y * 0.4, 0), Vector3(-18, 45 + rng.randf_range(-20, 20), 22))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tween := mi.create_tween().set_loops()
		var a := mat.albedo_color.a
		tween.tween_property(mat, "albedo_color:a", a * 0.5, rng.randf_range(2.5, 4.5)).set_trans(Tween.TRANS_SINE)
		tween.tween_property(mat, "albedo_color:a", a, rng.randf_range(2.5, 4.5)).set_trans(Tween.TRANS_SINE)


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
