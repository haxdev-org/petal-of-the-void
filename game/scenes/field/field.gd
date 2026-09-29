extends Node3D
## Broken Tooth Ridge, eastern slope: the crater where Baihua landed
## (Chapter One). A fixed isometric diorama with tap-to-move and joystick
## controls that hands off to the battle scene through encounters.

const MOVE_SPEED := 4.2
const BOUNDS := Rect2(-16, -26, 32, 34)
const ENCOUNTER_RADIUS := 2.0
const START_POSITION := Vector3(0, 0, 4.5)
const CAMERA_SIZE := 11.0
const SUN_ANGLES := Vector3(-48, -30, 0)

## Encounter id -> marker position.
const ENCOUNTERS := {
	&"ridge_wolves": Vector3(-6, 0, -6),
	&"ridge_bear": Vector3(7, 0, -12),
	&"ridge_wolf_demon": Vector3(0, 0, -20),
}

var _player: Node3D
var _player_sprite: AnimatedSprite3D
var _camera: Camera3D
var _move_target: Variant = null
var _obstacles: Array[Vector3] = [] # x, z = centre, y = radius
var _markers: Dictionary = {}
var _in_transition := false

var _joystick: TouchJoystick
var _menu_button: Button
var _menu_panel: PanelContainer
var _stones_label: Label
var _diagnostic: Label
var _target_ring: MeshInstance3D


func _ready() -> void:
	HD2D.build_environment(self, {
		"sky_top": Color("1a1a3f"), "sky_horizon": Color("d8946c"), "fog": Color("4a4262"),
		"fog_density": 0.007, "ambient": 0.8,
	})
	HD2D.build_sun(self, Color("ffd2a0"), 1.6, SUN_ANGLES)
	_build_terrain()
	_build_player()
	_build_markers()
	HD2D.add_petals(self, Vector3(16, 3, 16), 160).position = Vector3(0, 4, -8)
	HD2D.add_post_overlay(self, 0.5)

	_camera = HD2D.build_iso_camera(self, _player.position + Vector3(0, 0.8, 0), CAMERA_SIZE)
	_build_hud()
	_show_intro()


# --- World -----------------------------------------------------------------

func _build_terrain() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	HD2D.add_ground(self, "grass", Vector2(100, 100), Vector3(0, 0, -8), 7.0, Vector3.ZERO)
	# Scorched earth around the impact, then the vitrified glass itself.
	HD2D.add_crater(self, Vector3.ZERO)
	# Scorched, trampled ground around the blanket (kept outside the bowl).
	for i in 10:
		var a := i * TAU / 10.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(8.0, 11.0)
		var s := rng.randf_range(4.0, 7.0)
		var d := HD2D.add_decal(self, "clearing", Vector2(s, s * 0.8), Vector3(cos(a) * r, 0, sin(a) * r), rng.randf_range(0, 360), 0.006)
		d.material_override.albedo_color = Color(1, 1, 1, rng.randf_range(0.6, 0.9))
	# The path north, worn through the grass.
	HD2D.add_path(self, 2.8, 30, Vector3(0, 0, -17))

	# Thrown rock on the rim, and trees snapped outward in a radial pattern.
	for i in 14:
		var a := i * TAU / 14.0 + rng.randf_range(-0.15, 0.15)
		var r := rng.randf_range(3.9, 5.0)
		var pos := Vector3(cos(a) * r, 0, sin(a) * r)
		if absf(pos.x) < 1.8 and pos.z < 0:
			continue
		var size := rng.randf_range(0.25, 0.55)
		pos.y = HD2D.crater_height(r) - 0.05
		HD2D.add_rock(self, pos, size, rng)
		_obstacles.append(Vector3(pos.x, size * 0.6, pos.z))
	for i in 9:
		var a := i * TAU / 9.0 + rng.randf_range(-0.25, 0.25)
		var r := rng.randf_range(6.5, 10.0)
		var pos := Vector3(cos(a) * r, 0, sin(a) * r)
		if absf(pos.x) < 2.4 and pos.z < 0 or _near_marker(pos, 3.0) or pos.distance_to(START_POSITION) < 2.5:
			continue
		var variant := rng.randi_range(0, 2)
		var length: float = [4.0, 5.5, 7.0][variant]
		# Logs lie pointing away from the impact; their broken end faces it.
		var yaw := rad_to_deg(atan2(pos.x, pos.z))
		pos.y = HD2D.crater_height(r) * 0.5
		HD2D.add_prop(self, "log_%d" % variant, pos, yaw + rng.randf_range(-12, 12))
		var dir := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
		for k in 3:
			var c := pos + dir * length * (0.15 + 0.35 * k)
			_obstacles.append(Vector3(c.x, 0.55, c.z))
		var stump_pos := pos + dir * rng.randf_range(-0.8, -0.2) + Vector3(rng.randf_range(-0.6, 0.6), 0, 0)
		HD2D.add_prop(self, "stump_%d" % (i % 2), stump_pos, rng.randf_range(0, 360))
		_obstacles.append(Vector3(stump_pos.x, 0.45, stump_pos.z))

	# Forest and boulders, kept off the path, out of the crater and clear of the encounters.
	var tree_positions: Array[Vector3] = []
	for i in 70:
		var pos := Vector3(rng.randf_range(BOUNDS.position.x, BOUNDS.end.x), 0, rng.randf_range(BOUNDS.position.y, BOUNDS.end.y))
		if absf(pos.x) < 2.6 or pos.length() < 6.5 or _near_marker(pos, 3.5) or pos.distance_to(START_POSITION) < 3.0:
			continue
		var too_close := false
		for t in tree_positions:
			if t.distance_to(pos) < 2.2:
				too_close = true
				break
		if too_close:
			continue
		if rng.randf() < 0.7:
			var h := rng.randf_range(3.6, 7.0)
			HD2D.add_pine(self, pos, h, rng)
			_obstacles.append(Vector3(pos.x, 0.5, pos.z))
			tree_positions.append(pos)
		else:
			var s := rng.randf_range(0.5, 1.2)
			HD2D.add_rock(self, pos, s, rng)
			_obstacles.append(Vector3(pos.x, s * 0.65, pos.z))
	# Dense treeline just outside the walkable area so the edges never look empty.
	for i in 40:
		var side := rng.randi_range(0, 3)
		var pos: Vector3
		match side:
			0: pos = Vector3(BOUNDS.position.x - rng.randf_range(0.5, 4.0), 0, rng.randf_range(BOUNDS.position.y - 4, BOUNDS.end.y))
			1: pos = Vector3(BOUNDS.end.x + rng.randf_range(0.5, 4.0), 0, rng.randf_range(BOUNDS.position.y - 4, BOUNDS.end.y))
			2: pos = Vector3(rng.randf_range(BOUNDS.position.x - 4, BOUNDS.end.x + 4), 0, BOUNDS.position.y - rng.randf_range(0.5, 4.0))
			_: pos = Vector3(rng.randf_range(BOUNDS.position.x - 4, BOUNDS.end.x + 4), 0, BOUNDS.end.y + rng.randf_range(0.5, 4.0))
		HD2D.add_pine(self, pos, rng.randf_range(4.0, 7.0), rng)
	# Ridge walls behind the treeline and the Jade Canopy range beyond.
	HD2D.add_prop(self, "cliff_1", Vector3(-6, 0, BOUNDS.position.y - 7), 0)
	HD2D.add_prop(self, "cliff_0", Vector3(10, 0, BOUNDS.position.y - 8), 8)
	HD2D.add_prop(self, "cliff_0", Vector3(BOUNDS.position.x - 7, 0, -12), -90)

	HD2D.add_undergrowth(self, rng, BOUNDS, 420, func(p: Vector3) -> bool:
		return absf(p.x) > 1.7 and p.length() > 5.0 and not _near_marker(p, 2.2) and p.distance_to(START_POSITION) > 1.5)
	HD2D.add_ground_detail(self, rng, BOUNDS, 90, func(p: Vector3) -> bool:
		return absf(p.x) > 1.6 and p.length() > 7.0)
	var shafts: Array = []
	for i in 6:
		shafts.append(Vector3(rng.randf_range(-12, 12), 0, rng.randf_range(-22, 2)))
	HD2D.add_light_shafts(self, rng, shafts, SUN_ANGLES)


func _near_marker(pos: Vector3, radius: float) -> bool:
	for id: StringName in ENCOUNTERS:
		if pos.distance_to(ENCOUNTERS[id]) < radius:
			return true
	return false


func _build_player() -> void:
	_player = SpriteSheets.make_actor(SpriteSheets.player_id())
	_player_sprite = _player.get_node("Sprite")
	_player.position = GameState.field_position if GameState.has_field_position else START_POSITION
	_player.position.y = HD2D.crater_height(Vector2(_player.position.x, _player.position.z).length())
	add_child(_player)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.28
	ring_mesh.outer_radius = 0.36
	_target_ring = HD2D.add_mesh(self, ring_mesh,
		HD2D.material(UITheme.GOLD, 0.5, 0.0, UITheme.GOLD, 2.0), Vector3.ZERO)
	_target_ring.visible = false


func _build_markers() -> void:
	for id: StringName in ENCOUNTERS:
		var enc := Db.encounter(id)
		if GameState.has_flag(enc.flag):
			continue
		var marker := Node3D.new()
		marker.position = ENCOUNTERS[id]
		add_child(marker)
		var enemy_ids: Array = enc.enemies
		var right := HD2D.iso_right()
		var up := HD2D.iso_up()
		for i in mini(enemy_ids.size(), 3):
			var data := Db.combatant(enemy_ids[i])
			var actor := SpriteSheets.make_actor(data.sprite_id)
			actor.position = right * (i * 1.1 - 0.55 * mini(enemy_ids.size() - 1, 2)) + up * (i % 2) * 0.8
			marker.add_child(actor)
			SpriteSheets.set_dir(actor.get_node("Sprite"), [5, 6, 7][i % 3])
		var danger := OmniLight3D.new()
		danger.light_color = Color("ff4a3a")
		danger.light_energy = 0.7
		danger.omni_range = 3.5
		danger.position = Vector3(0, 1.0, 0)
		marker.add_child(danger)
		_markers[id] = marker


# --- HUD -------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var root := Control.new()
	root.theme = UITheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	_joystick = TouchJoystick.new()
	root.add_child(_joystick)

	_diagnostic = Label.new()
	_diagnostic.position = Vector2(24, 20)
	_diagnostic.add_theme_color_override("font_color", UITheme.DIAGNOSTIC)
	_diagnostic.add_theme_font_size_override("font_size", 22)
	root.add_child(_diagnostic)

	_stones_label = Label.new()
	_stones_label.position = Vector2(24, 56)
	_stones_label.add_theme_color_override("font_color", UITheme.GOLD)
	_stones_label.add_theme_font_size_override("font_size", 20)
	_stones_label.text = "Spirit stones: %d" % GameState.spirit_stones
	root.add_child(_stones_label)

	_menu_button = UITheme.button("Menu", _toggle_menu, 140)
	UITheme.pin_top_right(_menu_button, 140, 72)
	root.add_child(_menu_button)

	_menu_panel = PanelContainer.new()
	_menu_panel.visible = false
	_menu_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_menu_panel.add_child(box)
	box.add_child(UITheme.button("Save", _on_save, 280))
	var quality_button := UITheme.button(_quality_text(), func() -> void: pass, 280)
	quality_button.pressed.connect(func() -> void:
		Settings.set_quality((Settings.quality + 1) % 3)
		quality_button.text = _quality_text()
		GameState.field_position = _player.position
		GameState.has_field_position = true
		SceneRouter.go_to(SceneRouter.FIELD))
	box.add_child(quality_button)
	box.add_child(UITheme.button("Title Screen", func() -> void:
		GameState.field_position = _player.position
		GameState.has_field_position = true
		SceneRouter.go_to(SceneRouter.TITLE), 280))
	box.add_child(UITheme.button("Close", _toggle_menu, 280))
	root.add_child(_menu_panel)


func _quality_text() -> String:
	return "Graphics: %s" % ["Low", "Medium", "High"][Settings.quality]


func _show_intro() -> void:
	var remaining := _markers.size()
	if GameState.has_field_position and remaining == 0:
		_say("The stone pulses. Direction: north.")
	elif GameState.has_field_position:
		_say("Structural integrity: 91%. Hostiles remaining: %d." % remaining)
	else:
		_say("Broken Tooth Ridge. Memory archive: corrupted. Begin walking.")


func _say(text: String) -> void:
	_diagnostic.text = text
	_diagnostic.modulate.a = 0.0
	var tween := _diagnostic.create_tween()
	tween.tween_property(_diagnostic, "modulate:a", 1.0, 0.6)


func _toggle_menu() -> void:
	_menu_panel.visible = not _menu_panel.visible


func _on_save() -> void:
	GameState.field_position = _player.position
	GameState.has_field_position = true
	_say("Progress saved." if GameState.save_game() else "Save failed.")
	_menu_panel.visible = false


func _hud_blocks(pos: Vector2) -> bool:
	if _menu_panel.visible:
		return true
	return _menu_button.get_global_rect().has_point(pos)


# --- Input & movement ------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _in_transition:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _hud_blocks(event.position):
				return
			if _joystick.in_activation_zone(event.position):
				_joystick.start(event.index, event.position)
				_move_target = null
			else:
				_set_move_target(event.position)
		else:
			_joystick.release(event.index)
	elif event is InputEventScreenDrag:
		if event.index == _joystick.touch_index:
			_joystick.drag(event.index, event.position)
		elif not _hud_blocks(event.position):
			_set_move_target(event.position)


func _set_move_target(screen_pos: Vector2) -> void:
	var origin := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)
	if hit == null:
		return
	_move_target = _clamp_to_bounds(hit)
	_move_target.y = 0.0
	_target_ring.position = _move_target + Vector3(0, 0.05, 0)
	_target_ring.visible = true


func _physics_process(delta: float) -> void:
	if _in_transition:
		return
	# Screen directions map onto the diagonal ground axes of the isometric view.
	var input := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if _joystick.touch_index >= 0:
		input = _joystick.vector
	var velocity := HD2D.iso_right() * input.x - HD2D.iso_up() * input.y
	if input != Vector2.ZERO:
		_move_target = null
		_target_ring.visible = false
	elif _move_target != null:
		var to_target: Vector3 = _move_target - _player.position
		to_target.y = 0
		if to_target.length() < 0.1:
			_move_target = null
			_target_ring.visible = false
		else:
			velocity = to_target.normalized()
	velocity = velocity.limit_length(1.0) * MOVE_SPEED

	var moving := velocity.length() > 0.05
	if moving:
		var next := _clamp_to_bounds(_player.position + velocity * delta)
		next = _push_out_of_obstacles(next)
		next.y = HD2D.crater_height(Vector2(next.x, next.z).length())
		_player.position = next
		SpriteSheets.set_dir(_player_sprite, SpriteSheets.dir_from_motion(velocity))
		if not SpriteSheets.is_playing(_player_sprite, &"walk"):
			SpriteSheets.play(_player_sprite, &"walk")
	elif not SpriteSheets.is_playing(_player_sprite, &"idle"):
		SpriteSheets.play(_player_sprite, &"idle")
	_update_camera(delta * 5.0)
	_check_encounters()


func _clamp_to_bounds(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, BOUNDS.position.x, BOUNDS.end.x), p.y, clampf(p.z, BOUNDS.position.y, BOUNDS.end.y))


func _push_out_of_obstacles(p: Vector3) -> Vector3:
	for o in _obstacles:
		var centre := Vector3(o.x, p.y, o.z)
		var min_dist := o.y + 0.3
		var d := p.distance_to(centre)
		if d < min_dist and d > 0.0001:
			p = centre + (p - centre) / d * min_dist
	return p


func _update_camera(weight: float) -> void:
	var goal := _player.position + Vector3(0, 0.8, 0) + HD2D.iso_offset()
	_camera.position = _camera.position.lerp(goal, clampf(weight, 0.0, 1.0))


func _check_encounters() -> void:
	for id: StringName in _markers:
		var marker: Node3D = _markers[id]
		if _player.position.distance_to(marker.position) < ENCOUNTER_RADIUS:
			_start_battle(id)
			return


func _start_battle(id: StringName) -> void:
	_in_transition = true
	SpriteSheets.play(_player_sprite, &"idle")
	# Return a step back toward the start so the player isn't on the marker.
	var marker_pos: Vector3 = _markers[id].position
	var back := (_player.position - marker_pos).normalized()
	GameState.field_position = marker_pos + back * (ENCOUNTER_RADIUS + 1.0)
	GameState.has_field_position = true
	GameState.pending_encounter = { "id": id }
	SceneRouter.go_to(SceneRouter.BATTLE, Color(1.0, 0.85, 0.55), 0.35)
