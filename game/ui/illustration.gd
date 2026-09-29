class_name Illustration
extends Control
## Full-screen illustrated panel with a slow Ken Burns push-in. The image is
## cropped to `region` (to drop letterbox bars and the generator watermark)
## and scaled to cover the screen at any aspect ratio.

var _rect: TextureRect


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_rect = TextureRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	resized.connect(func() -> void: _rect.pivot_offset = size / 2.0)


## `region` is in source pixels; an empty rect uses the whole image.
func show_image(path: String, region := Rect2(), duration := 8.0, zoom := 1.08, drift := Vector2.ZERO) -> void:
	var tex: Texture2D = load(path)
	if region.has_area():
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = region
		tex = atlas
	_rect.texture = tex
	_rect.pivot_offset = size / 2.0
	_rect.scale = Vector2.ONE
	_rect.position = Vector2.ZERO
	var tween := _rect.create_tween().set_parallel(true)
	tween.tween_property(_rect, "scale", Vector2.ONE * zoom, duration).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_rect, "position", drift, duration).set_trans(Tween.TRANS_SINE)


## Drifting white-to-violet petals for 2D screens.
static func add_petals(parent: Node, amount := 60) -> GPUParticles2D:
	var particles := GPUParticles2D.new()
	particles.amount = amount
	particles.lifetime = 10.0
	particles.preprocess = 10.0
	particles.texture = PixelArt.texture(&"petal")
	particles.position = Vector2(640, -40)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(900, 20, 0)
	pm.direction = Vector3(0.4, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 25.0
	pm.initial_velocity_max = 60.0
	pm.gravity = Vector3(10, 12, 0)
	pm.angular_velocity_min = -80.0
	pm.angular_velocity_max = 80.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 4.0
	pm.scale_min = 0.8
	pm.scale_max = 1.8
	pm.particle_flag_disable_z = true
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(0.8, 0.7, 1.0, 0))
	ramp.add_point(0.1, Color(1, 0.97, 0.97, 0.9))
	ramp.add_point(0.75, Color(0.85, 0.75, 1.0, 0.9))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	pm.color_ramp = ramp_tex
	particles.process_material = pm
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	particles.material = mat
	parent.add_child(particles)
	return particles
