extends Node3D
## Broken Tooth Ridge, eastern slope: the crater where Baihua landed
## (Chapter One). A gray-box diorama that shows the HD-2D look, tap-to-move and
## joystick controls, and hands off to the battle scene through encounters.

const MOVE_SPEED := 4.2
const BOUNDS := Rect2(-15, -24, 30, 32)
const CAMERA_OFFSET := Vector3(0, 10.5, 13.5)
const ENCOUNTER_RADIUS := 2.0
const START_POSITION := Vector3(0, 0, 4.5)

## Encounter id -> marker position.
const ENCOUNTERS := {
	&"ridge_wolves": Vector3(-6, 0, -6),
	&"ridge_bear": Vector3(7, 0, -12),
	&"ridge_wolf_demon": Vector3(0, 0, -20),
}

var _player: Node3D
var _player_sprite: Sprite3D
var _camera: Camera3D
var _move_target: Variant = null
var _obstacles: Array[Vector3] = [] # x, z = centre, y = radius
var _markers: Dictionary = {}
var _walk_time := 0.0
var _in_transition := false

var _joystick: TouchJoystick
var _menu_button: Button
var _menu_panel: PanelContainer
var _stones_label: Label
var _diagnostic: Label
var _target_ring: MeshInstance3D


func _ready() -> void:
	HD2D.build_environment(self)
	HD2D.build_sun(self)
	_build_terrain()
	_build_player()
	_build_markers()
	HD2D.add_petals(self, Vector3(14, 3, 14), 140).position = Vector3(0, 4, -8)

	_camera = Camera3D.new()
	_camera.fov = 30
	_camera.attributes = HD2D.build_camera_attributes(CAMERA_OFFSET.length())
	add_child(_camera)
	_update_camera(1.0)
	_build_hud()
	_show_intro()


# --- World -----------------------------------------------------------------

func _build_terrain() -> void:
	var ground := PlaneMesh.new()
	ground.size = Vector2(60, 70)
	HD2D.add_mesh(self, ground, HD2D.material(Color("2c3029")), Vector3(0, 0, -8))

	# The path north, worn lighter.
	var path := PlaneMesh.new()
	path.size = Vector2(2.4, 30)
	HD2D.add_mesh(self, path, HD2D.material(Color("5a5040")), Vector3(0, 0.01, -12))

	# The crater: rock vitrified to black glass, still faintly hot at the centre.
	var glass := CylinderMesh.new()
	glass.top_radius = 3.2
	glass.bottom_radius = 3.6
	glass.height = 0.12
	HD2D.add_mesh(self, glass, HD2D.material(Color("0b0a12"), 0.06, 0.3), Vector3(0, 0.02, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in 7:
		var crack := BoxMesh.new()
		crack.size = Vector3(rng.randf_range(1.2, 2.6), 0.02, 0.06)
		var angle := i * TAU / 7.0 + rng.randf_range(-0.2, 0.2)
		var mat := HD2D.material(Color("ff9a3c"), 0.5, 0.0, Color("ff8a2a"), 3.0)
		HD2D.add_mesh(self, crack, mat, Vector3(cos(angle), 0.1, sin(angle)) * 1.2, Vector3(0, -rad_to_deg(angle), 0))
	var ember := OmniLight3D.new()
	ember.light_color = Color("ff9a4a")
	ember.light_energy = 1.6
	ember.omni_range = 6.0
	ember.position = Vector3(0, 0.5, 0)
	add_child(ember)
	var flicker := ember.create_tween().set_loops()
	flicker.tween_property(ember, "light_energy", 1.1, 1.3).set_trans(Tween.TRANS_SINE)
	flicker.tween_property(ember, "light_energy", 1.8, 1.1).set_trans(Tween.TRANS_SINE)

	# Ridge walls and forest, kept off the path and away from the crater.
	for i in 38:
		var pos := Vector3(rng.randf_range(-15, 15), 0, rng.randf_range(-26, 8))
		if absf(pos.x) < 2.5 or pos.length() < 5.0 or _near_marker(pos, 3.5):
			continue
		if rng.randf() < 0.6:
			var h := rng.randf_range(2.5, 5.0)
			HD2D.add_pine(self, pos, h)
			_obstacles.append(Vector3(pos.x, 0.45, pos.z))
		else:
			var s := rng.randf_range(0.8, 2.0)
			HD2D.add_rock(self, pos, s, rng)
			_obstacles.append(Vector3(pos.x, s * 0.6, pos.z))
	# Distant peaks of the Jade Canopy range, softened by fog.
	for i in 7:
		var peak := PrismMesh.new()
		peak.size = Vector3(rng.randf_range(10, 18), rng.randf_range(8, 16), 6)
		HD2D.add_mesh(self, peak, HD2D.material(Color("3a3f5a")),
			Vector3(-30 + i * 10 + rng.randf_range(-3, 3), peak.size.y / 2.0, -40 - rng.randf_range(0, 8)))


func _near_marker(pos: Vector3, radius: float) -> bool:
	for id: StringName in ENCOUNTERS:
		if pos.distance_to(ENCOUNTERS[id]) < radius:
			return true
	return false


func _build_player() -> void:
	_player = HD2D.make_sprite_actor(PixelArt.texture(&"baihua"))
	_player_sprite = _player.get_node("Sprite")
	_player.position = GameState.field_position if GameState.has_field_position else START_POSITION
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
		for i in mini(enemy_ids.size(), 3):
			var data := Db.combatant(enemy_ids[i])
			var actor := HD2D.make_sprite_actor(PixelArt.texture(data.sprite_id), data.sprite_scale)
			actor.position = Vector3(i * 0.9 - 0.4 * mini(enemy_ids.size() - 1, 2), 0, i * 0.4)
			marker.add_child(actor)
			var sprite: Sprite3D = actor.get_node("Sprite")
			var bob := sprite.create_tween().set_loops()
			bob.tween_property(sprite, "position:y", 0.08, 0.5 + i * 0.1).set_trans(Tween.TRANS_SINE)
			bob.tween_property(sprite, "position:y", 0.0, 0.5 + i * 0.1).set_trans(Tween.TRANS_SINE)
		var danger := OmniLight3D.new()
		danger.light_color = Color("ff4a3a")
		danger.light_energy = 0.8
		danger.omni_range = 3.0
		danger.position = Vector3(0, 1.0, 0)
		marker.add_child(danger)
		_markers[id] = marker


# --- HUD -------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
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
	_menu_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	root.add_child(_menu_button)

	_menu_panel = PanelContainer.new()
	_menu_panel.visible = false
	_menu_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_menu_panel.add_child(box)
	box.add_child(UITheme.button("Save", _on_save, 280))
	var quality_button := UITheme.button(_quality_text(), Callable(), 280)
	quality_button.pressed.connect(func() -> void:
		Settings.set_quality((Settings.quality + 1) % 3)
		quality_button.text = _quality_text()
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
	_target_ring.position = _move_target + Vector3(0, 0.05, 0)
	_target_ring.visible = true


func _physics_process(delta: float) -> void:
	if _in_transition:
		return
	var input := Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")
	if _joystick.touch_index >= 0:
		input = _joystick.vector
	var velocity := Vector3(input.x, 0, input.y)
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
		_player.position = _push_out_of_obstacles(next)
		if absf(velocity.x) > 0.1:
			_player_sprite.flip_h = velocity.x < 0
		_walk_time += delta * 10.0
		_player_sprite.position.y = absf(sin(_walk_time)) * 0.07
	else:
		_walk_time = 0.0
		_player_sprite.position.y = lerpf(_player_sprite.position.y, 0.0, 0.3)
	_update_camera(delta * 5.0)
	_check_encounters()


func _clamp_to_bounds(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, BOUNDS.position.x, BOUNDS.end.x), 0, clampf(p.z, BOUNDS.position.y, BOUNDS.end.y))


func _push_out_of_obstacles(p: Vector3) -> Vector3:
	for o in _obstacles:
		var centre := Vector3(o.x, 0, o.z)
		var min_dist := o.y + 0.3
		var d := p.distance_to(centre)
		if d < min_dist and d > 0.0001:
			p = centre + (p - centre) / d * min_dist
	return p


func _update_camera(weight: float) -> void:
	var goal := _player.position + CAMERA_OFFSET
	_camera.position = _camera.position.lerp(goal, clampf(weight, 0.0, 1.0))
	_camera.look_at(_camera.position - CAMERA_OFFSET + Vector3(0, 0.8, 0))


func _check_encounters() -> void:
	for id: StringName in _markers:
		var marker: Node3D = _markers[id]
		if _player.position.distance_to(marker.position) < ENCOUNTER_RADIUS:
			_start_battle(id)
			return


func _start_battle(id: StringName) -> void:
	_in_transition = true
	# Return a step back toward the start so the player isn't on the marker.
	var marker_pos: Vector3 = _markers[id].position
	var back := (_player.position - marker_pos).normalized()
	GameState.field_position = marker_pos + back * (ENCOUNTER_RADIUS + 1.0)
	GameState.has_field_position = true
	GameState.pending_encounter = { "id": id }
	SceneRouter.go_to(SceneRouter.BATTLE, Color(1.0, 0.85, 0.55), 0.35)
