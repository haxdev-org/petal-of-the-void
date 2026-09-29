class_name SpriteSheets
extends RefCounted
## Loads the generated sprite sheets (assets/sprites/<id>.png + .json) into
## SpriteFrames and builds lit, shadow-casting AnimatedSprite3D actors.

const DIR := "res://assets/sprites/"

static var _frames: Dictionary = {}
static var _meta: Dictionary = {}


static func meta(id: StringName) -> Dictionary:
	if not _meta.has(id):
		var text := FileAccess.get_file_as_string(DIR + String(id) + ".json")
		var data: Variant = JSON.parse_string(text)
		_meta[id] = data if typeof(data) == TYPE_DICTIONARY else {}
	return _meta[id]


static func frames(id: StringName) -> SpriteFrames:
	if _frames.has(id):
		return _frames[id]
	var sheet: Texture2D = load(DIR + String(id) + ".png")
	var m := meta(id)
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	var fw: int = int(m.frame_w)
	var fh: int = int(m.frame_h)
	for anim_name: String in m.anims:
		var a: Dictionary = m.anims[anim_name]
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, float(a.fps))
		sf.set_animation_loop(anim_name, bool(a.loop))
		for i in int(a.frames):
			var atlas := AtlasTexture.new()
			atlas.atlas = sheet
			atlas.region = Rect2(i * fw, int(a.row) * fh, fw, fh)
			sf.add_frame(anim_name, atlas)
	_frames[id] = sf
	return sf


## Baihua wears the cracked chassis until the story gives her the robe.
static func player_id() -> StringName:
	return &"baihua" if GameState.has_flag(&"robe") else &"baihua_armor"


## Height of the drawn character in metres.
static func height_m(id: StringName) -> float:
	return float(meta(id).get("height_m", 1.6))


## A character standing on the ground at the node origin: an AnimatedSprite3D
## ("Sprite") that is lit by the scene and casts a real shadow, plus a soft
## contact shadow ("Shadow").
static func make_actor(id: StringName, flip := false) -> Node3D:
	var root := Node3D.new()
	var m := meta(id)
	var sprite := AnimatedSprite3D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = frames(id)
	sprite.pixel_size = 1.0 / float(m.get("ppm", 44.0))
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.5
	# Unlit, like a pre-rendered Infinity Engine sprite: the palette stays exact
	# and the sun behind the camera can't silhouette it.
	sprite.shaded = false
	sprite.modulate = Color(0.97, 0.95, 1.0)
	sprite.double_sided = true
	sprite.flip_h = flip
	sprite.offset = Vector2(0, float(m.frame_h) / 2.0)
	var directional := int(m.get("dirs", 1)) > 1
	sprite.set_meta("dirs", int(m.get("dirs", 1)))
	sprite.set_meta("dir", 0)
	if directional:
		# Pre-rendered at the camera's pitch: a screen-aligned card whose
		# bottom edge sits on the ground point.
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		sprite.scale.y = HD2D.iso_sprite_stretch()
	root.add_child(sprite)
	play(sprite, &"idle")
	# Desynchronise idle loops so a pack of wolves doesn't breathe in unison.
	sprite.frame = randi() % maxi(1, sprite.sprite_frames.get_frame_count(sprite.animation))

	var shadow := Sprite3D.new()
	shadow.name = "Shadow"
	shadow.texture = HD2D.tex("soft_circle")
	shadow.modulate = Color(0.05, 0.03, 0.1, 0.45)
	shadow.pixel_size = height_m(id) * 0.55 / 64.0
	shadow.rotation_degrees.x = -90
	shadow.position.y = 0.015
	shadow.shaded = false
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shadow)
	return root


## Facing index 0..7: 0 = screen right, counter-clockwise (2 = away, 6 = toward camera).
static func set_dir(sprite: AnimatedSprite3D, dir: int) -> void:
	var dirs: int = sprite.get_meta("dirs", 1)
	if dirs <= 1:
		return
	dir = wrapi(dir, 0, dirs)
	if dir == sprite.get_meta("dir", 0):
		return
	sprite.set_meta("dir", dir)
	var base := base_anim(sprite)
	var frame := sprite.frame
	sprite.play(_name(sprite, base))
	sprite.frame = mini(frame, sprite.sprite_frames.get_frame_count(sprite.animation) - 1)


## Facing from a world-space movement vector, in the isometric view.
static func dir_from_motion(v: Vector3) -> int:
	var right := v.dot(HD2D.iso_right())
	var up := v.dot(HD2D.iso_up())
	if absf(right) < 0.001 and absf(up) < 0.001:
		return 0
	return wrapi(roundi(rad_to_deg(atan2(up, right)) / 45.0), 0, 8)


static func _name(sprite: AnimatedSprite3D, anim: StringName) -> StringName:
	var dirs: int = sprite.get_meta("dirs", 1)
	if dirs > 1:
		var named := StringName("%s_%d" % [anim, sprite.get_meta("dir", 0)])
		if sprite.sprite_frames.has_animation(named):
			return named
	return anim


## The animation name without its direction suffix.
static func base_anim(sprite: AnimatedSprite3D) -> StringName:
	var n := String(sprite.animation)
	var i := n.rfind("_")
	if i > 0 and n.substr(i + 1).is_valid_int():
		return StringName(n.substr(0, i))
	return sprite.animation


static func play(sprite: AnimatedSprite3D, anim: StringName) -> void:
	var named := _name(sprite, anim)
	if sprite.sprite_frames.has_animation(named):
		sprite.play(named)


static func is_playing(sprite: AnimatedSprite3D, anim: StringName) -> bool:
	return base_anim(sprite) == anim


## Plays a one-shot animation and returns to idle when it ends.
static func play_then_idle(sprite: AnimatedSprite3D, anim: StringName) -> void:
	if not sprite.sprite_frames.has_animation(_name(sprite, anim)):
		return
	play(sprite, anim)
	await sprite.animation_finished
	if is_playing(sprite, anim):
		play(sprite, &"idle")
