extends Node3D
## Turn-based battle scene. Rules live in BattleSystem; this script builds the
## diorama, runs the turn loop, takes touch input and plays the effects.

signal _command_chosen(skill: SkillData, target: Combatant)

## Slots in screen space (right, up along the ground), converted to world
## positions with HD2D.iso_right/iso_up. Party on the left, enemies right.
const PARTY_SLOTS := [Vector2(-3.6, 0.0)]
const ENEMY_SLOTS := [Vector2(1.4, 0.0), Vector2(3.0, 1.4), Vector2(3.2, -1.3), Vector2(4.8, 0.2)]
const CAMERA_SIZE := 9.5
const SUN_ANGLES := Vector3(-44, -50, 0)
const TAP_RADIUS := 130.0

var system: BattleSystem
var _encounter: Dictionary
var _actors: Dictionary = {} # Combatant -> Node3D
var _name_labels: Dictionary = {} # Combatant -> Label3D
var _camera: Camera3D
var _camera_home: Vector3
var _shake := 0.0
var _time := 0.0

# UI
var _ui_root: Control
var _log_label: Label
var _order_label: Label
var _status: Dictionary = {} # Combatant -> {hp, qi, heat, hp_text}
var _command_panel: PanelContainer
var _command_box: GridContainer
var _hint_label: Label
var _banner: Label
var _targeting_skill: SkillData = null
var _selector: MeshInstance3D


func _ready() -> void:
	var enc_id: StringName = GameState.pending_encounter.get("id", &"ridge_wolves")
	_encounter = Db.encounter(enc_id)
	var party: Array[Combatant] = [Combatant.new(Db.player_data(GameState.flags), true)]
	var enemies: Array[Combatant] = []
	var counts := {}
	for enemy_id: StringName in _encounter.enemies:
		counts[enemy_id] = counts.get(enemy_id, 0) + 1
	var seen := {}
	for enemy_id: StringName in _encounter.enemies:
		var c := Combatant.new(Db.combatant(enemy_id))
		if counts[enemy_id] > 1:
			c.name_suffix = " " + "ABCD"[seen.get(enemy_id, 0)]
			seen[enemy_id] = seen.get(enemy_id, 0) + 1
		enemies.append(c)
	system = BattleSystem.new(party, enemies)

	_build_stage()
	_build_ui()
	_run_battle()


# --- Stage -----------------------------------------------------------------

func _build_stage() -> void:
	HD2D.build_environment(self, {
		"sky_top": Color("1b1838"), "sky_horizon": Color("d88f62"), "fog": Color("4a3a60"),
		"fog_density": 0.009, "ambient": 0.8,
	})
	HD2D.build_sun(self, Color("ffc58f"), 1.6, SUN_ANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	HD2D.add_ground(self, "grass", Vector2(80, 80))
	# Trodden clearing where the fight happens, aligned with the screen.
	HD2D.add_decal(self, "clearing", Vector2(17, 12), Vector3(0.6, 0, 0), 45)
	var up := HD2D.iso_up()
	var right := HD2D.iso_right()
	# Treeline curving around the top of the screen and down both sides.
	var trees: Array[Vector3] = []
	for i in 34:
		var a := rng.randf_range(0.15, PI - 0.15)
		var r := rng.randf_range(7.5, 13.0)
		var pos := right * cos(a) * r + up * sin(a) * r * 0.75
		var too_close := false
		for t in trees:
			if t.distance_to(pos) < 2.0:
				too_close = true
				break
		if too_close:
			continue
		trees.append(pos)
		HD2D.add_pine(self, pos, rng.randf_range(3.8, 7.0), rng)
	for i in 7:
		var a := rng.randf_range(0.2, PI - 0.2)
		var r := rng.randf_range(5.5, 7.5)
		HD2D.add_rock(self, right * cos(a) * r + up * sin(a) * r * 0.7, rng.randf_range(0.5, 1.1), rng)
	HD2D.add_undergrowth(self, rng, Rect2(-16, -16, 32, 32), 220, func(p: Vector3) -> bool:
		var sx := p.dot(right)
		var sy := p.dot(up)
		return absf(sx) > 6.0 or absf(sy) > 3.6)
	HD2D.add_ground_detail(self, rng, Rect2(-14, -14, 28, 28), 40, func(p: Vector3) -> bool:
		return absf(p.dot(right)) > 5.0 or absf(p.dot(up)) > 3.0)
	var shafts: Array = []
	for i in 4:
		shafts.append(right * rng.randf_range(-7, 7) + up * rng.randf_range(2, 7))
	HD2D.add_light_shafts(self, rng, shafts, SUN_ANGLES)
	HD2D.add_petals(self, Vector3(10, 3, 10), 110).position = Vector3(0, 3.5, 0)
	HD2D.add_post_overlay(self, 0.5)

	for i in system.party.size():
		_add_actor(system.party[i], _slot(PARTY_SLOTS[i]), false)
	for i in system.enemies.size():
		_add_actor(system.enemies[i], _slot(ENEMY_SLOTS[i]), true)

	var ring := TorusMesh.new()
	ring.inner_radius = 0.55
	ring.outer_radius = 0.65
	_selector = HD2D.add_mesh(self, ring, HD2D.material(UITheme.GOLD, 0.5, 0.0, UITheme.GOLD, 2.5), Vector3.ZERO)
	_selector.visible = false

	_camera = HD2D.build_iso_camera(self, Vector3(0.4, 0.9, 0), CAMERA_SIZE)
	_camera_home = _camera.position


func _slot(screen: Vector2) -> Vector3:
	return HD2D.iso_right() * screen.x + HD2D.iso_up() * screen.y


func _add_actor(c: Combatant, pos: Vector3, is_enemy: bool) -> void:
	var id: StringName = c.data.sprite_id if is_enemy else SpriteSheets.player_id()
	var node := SpriteSheets.make_actor(id)
	node.position = pos
	add_child(node)
	_actors[c] = node
	# Party faces screen-right toward the enemies, enemies face left.
	SpriteSheets.set_dir(node.get_node("Sprite"), 4 if is_enemy else 0)
	if is_enemy:
		var label := Label3D.new()
		label.font_size = 26
		label.outline_size = 8
		label.pixel_size = 0.005
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3(0, SpriteSheets.height_m(id) + 0.45, 0)
		node.add_child(label)
		_name_labels[c] = label


func _sprite(c: Combatant) -> AnimatedSprite3D:
	return _actors[c].get_node("Sprite")


func _process(delta: float) -> void:
	_time += delta
	# Slow handheld drift keeps the diorama feeling alive.
	var drift := _camera.basis.x * sin(_time * 0.35) * 0.1 + _camera.basis.y * sin(_time * 0.5) * 0.04
	var shake := (_camera.basis.x * randf_range(-1, 1) + _camera.basis.y * randf_range(-1, 1)) * _shake
	_shake = move_toward(_shake, 0.0, delta * 1.2)
	_camera.position = _camera_home + drift + shake
	if _selector.visible:
		_selector.scale = Vector3.ONE * (1.0 + sin(_time * 6.0) * 0.06)


# --- UI --------------------------------------------------------------------

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui_root = Control.new()
	_ui_root.theme = UITheme.get_theme()
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui_root)

	# Party status, top-left.
	var status_panel := PanelContainer.new()
	status_panel.position = Vector2(20, 20)
	status_panel.custom_minimum_size = Vector2(330, 0)
	_ui_root.add_child(status_panel)
	var status_box := VBoxContainer.new()
	status_panel.add_child(status_box)
	for c in system.party:
		var name_row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = c.display_name
		name_label.add_theme_color_override("font_color", UITheme.GOLD)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_row.add_child(name_label)
		var hp_text := Label.new()
		hp_text.add_theme_font_size_override("font_size", 20)
		name_row.add_child(hp_text)
		status_box.add_child(name_row)
		var hp := UITheme.bar(Color("7fd18b"))
		var qi := UITheme.bar(Color("b89bff"))
		var nano := UITheme.bar(Color("8fd8e8"))
		var heat := UITheme.bar(Color("ffae4a"))
		var rows: Array = [["Integrity", hp], ["Core heat", heat], ["Nanobots", nano]]
		if c.data.max_qi > 0:
			rows.append(["Qi", qi])
		for pair: Array in rows:
			var row := HBoxContainer.new()
			var l := Label.new()
			l.text = pair[0]
			l.custom_minimum_size = Vector2(110, 0)
			l.add_theme_font_size_override("font_size", 16)
			row.add_child(l)
			pair[1].size_flags_horizontal = Control.SIZE_EXPAND_FILL
			pair[1].size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(pair[1])
			status_box.add_child(row)
		_status[c] = { "hp": hp, "qi": qi, "nano": nano, "heat": heat, "hp_text": hp_text }

	_log_label = Label.new()
	_log_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_log_label.position.y = 24
	_log_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log_label.add_theme_color_override("font_color", UITheme.DIAGNOSTIC)
	_log_label.add_theme_font_size_override("font_size", 22)
	_ui_root.add_child(_log_label)

	_order_label = Label.new()
	_order_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	_order_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_order_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_order_label.add_theme_font_size_override("font_size", 18)
	_order_label.add_theme_color_override("font_color", UITheme.MUTED)
	_ui_root.add_child(_order_label)

	_command_panel = PanelContainer.new()
	_command_panel.visible = false
	_ui_root.add_child(_command_panel)
	_command_box = GridContainer.new()
	_command_box.columns = 5
	_command_box.add_theme_constant_override("h_separation", 10)
	_command_box.add_theme_constant_override("v_separation", 10)
	_command_panel.add_child(_command_box)

	_hint_label = Label.new()
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.position.y -= 130
	_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", UITheme.GOLD)
	_hint_label.visible = false
	_ui_root.add_child(_hint_label)

	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 48)
	_banner.add_theme_color_override("font_color", UITheme.GOLD)
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.modulate.a = 0.0
	_ui_root.add_child(_banner)
	_refresh()


func _refresh() -> void:
	for c: Combatant in _status:
		var s: Dictionary = _status[c]
		s.hp.max_value = c.data.max_hp
		s.hp.value = c.hp
		s.hp_text.text = "%d/%d" % [c.hp, c.data.max_hp]
		s.qi.max_value = maxi(1, c.data.max_qi)
		s.qi.value = c.qi
		s.nano.max_value = maxi(1, c.data.max_nano)
		s.nano.value = c.nano
		s.heat.max_value = Combatant.MAX_HEAT
		s.heat.value = c.heat
	for c: Combatant in _name_labels:
		var label: Label3D = _name_labels[c]
		var tags := ""
		if c.statuses.has(&"corroded"):
			tags += "  [corroded]"
		if c.statuses.has(&"assessed"):
			tags += "  [mapped]"
		label.text = "%s\n%d/%d%s" % [c.display_name, c.hp, c.data.max_hp, tags]
		label.modulate = Color(1, 0.55, 0.5) if c.statuses.has(&"corroded") else (Color(0.75, 0.85, 1.0) if c.statuses.has(&"assessed") else Color.WHITE)
	var names := system.turn_order_preview(5).map(func(c: Combatant) -> String: return c.display_name)
	_order_label.text = "Turn order\n" + "\n".join(PackedStringArray(names))


func _log(text: String) -> void:
	_log_label.text = text
	_log_label.modulate.a = 0.0
	_log_label.create_tween().tween_property(_log_label, "modulate:a", 1.0, 0.2)


func _show_banner(text: String, color := UITheme.GOLD, hold := 1.2) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	var tween := _banner.create_tween()
	tween.tween_property(_banner, "modulate:a", 1.0, 0.25)
	tween.tween_interval(hold)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.4)
	await tween.finished


# --- Turn loop -------------------------------------------------------------

func _run_battle() -> void:
	_log(system.threat_assessment())
	await _show_banner(_encounter.name, Color.WHITE, 0.8)
	while system.outcome() == BattleSystem.Outcome.ONGOING:
		var actor := system.advance_to_next_actor()
		for line in system.begin_turn(actor):
			_log(line)
			_flash(actor, Color(0.6, 1.0, 0.4))
			await _wait(0.6)
		_refresh()
		if not actor.is_alive():
			await _defeat_actor(actor)
			continue
		if system.outcome() != BattleSystem.Outcome.ONGOING:
			break
		var skill: SkillData
		var targets: Array[Combatant]
		if actor.is_player:
			_log("%s: awaiting command." % actor.display_name)
			var choice: Array = await _player_choose(actor)
			skill = choice[0]
			targets = system.default_targets(actor, skill, choice[1])
		else:
			await _wait(0.35)
			var action := system.choose_enemy_action(actor)
			skill = action.skill
			targets = action.targets
		var result := system.execute(actor, skill, targets)
		_log(result.log[0])
		await _animate(result)
		_refresh()
	await _finish()


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _finish() -> void:
	if system.outcome() == BattleSystem.Outcome.VICTORY:
		var stones := system.total_reward()
		GameState.spirit_stones += stones
		GameState.set_flag(_encounter.flag)
		_log("Hostiles neutralised. Spirit stones recovered: %d." % stones)
		await _show_banner("Victory", UITheme.GOLD, 1.4)
		SceneRouter.go_to(SceneRouter.FIELD)
	else:
		_log("Structural integrity critical. Emergency shutdown.")
		await _show_banner("Defeat", Color(1, 0.4, 0.4), 1.6)
		SceneRouter.go_to(SceneRouter.TITLE)


# --- Player input ----------------------------------------------------------

func _player_choose(actor: Combatant) -> Array:
	_show_main_commands(actor)
	var args: Array = await _command_chosen
	_command_panel.visible = false
	_hint_label.visible = false
	_selector.visible = false
	_targeting_skill = null
	return args


func _clear_commands() -> void:
	for child in _command_box.get_children():
		_command_box.remove_child(child)
		child.queue_free()


func _place_command_panel() -> void:
	_command_panel.visible = true
	_command_box.columns = clampi(_command_box.get_child_count(), 1, 6)
	_command_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	await get_tree().process_frame
	_command_panel.position = Vector2((vp.x - _command_panel.size.x) / 2.0, vp.y - _command_panel.size.y - 16)


func _show_main_commands(actor: Combatant) -> void:
	_clear_commands()
	_hint_label.visible = false
	_selector.visible = false
	_targeting_skill = null
	var by_id := {}
	for s in actor.skills:
		by_id[s.id] = s
	_command_box.add_child(_skill_button(actor, by_id[&"strike"], "Strike"))
	_command_box.add_child(_skill_button(actor, by_id[&"core_surge"], "Surge (%d heat)" % by_id[&"core_surge"].heat_cost))
	if actor.skills.any(func(s: SkillData) -> bool: return s.is_qi_technique()):
		_command_box.add_child(UITheme.button("Techniques", func() -> void: _show_techniques(actor), 172))
	else:
		_command_box.add_child(_skill_button(actor, by_id[&"assess"], "Sweep"))
	_command_box.add_child(_skill_button(actor, by_id[&"nanobot_repair"], "Repair %d%%" % by_id[&"nanobot_repair"].nano_cost))
	_command_box.add_child(_skill_button(actor, by_id[&"stillness"], "Stillness"))
	var stellar := _skill_button(actor, by_id[&"stellar_discharge"], "STELLAR" if actor.heat >= Combatant.MAX_HEAT else "Stellar %d%%" % actor.heat)
	if not stellar.disabled:
		stellar.add_theme_color_override("font_color", UITheme.GOLD)
		var pulse := stellar.create_tween().set_loops()
		pulse.tween_property(stellar, "modulate", Color(1.4, 1.2, 0.8), 0.5)
		pulse.tween_property(stellar, "modulate", Color.WHITE, 0.5)
	_command_box.add_child(stellar)
	_place_command_panel()


func _show_techniques(actor: Combatant) -> void:
	_clear_commands()
	for s in actor.skills:
		if s.is_qi_technique():
			var label := "%s%s (%d qi)" % [s.display_name, " *" if s.optimized else "", s.qi_cost]
			_command_box.add_child(_skill_button(actor, s, label))
	if actor.knows(&"assess"):
		_command_box.add_child(_skill_button(actor, actor.skills.filter(func(s: SkillData) -> bool: return s.id == &"assess")[0], "Sensor Sweep"))
	_command_box.add_child(UITheme.button("Back", func() -> void: _show_main_commands(actor), 172))
	_place_command_panel()


func _skill_button(actor: Combatant, skill: SkillData, text: String) -> Button:
	var b := UITheme.button(text, func() -> void: _on_skill_picked(actor, skill), 172)
	b.disabled = not actor.can_use(skill)
	b.tooltip_text = skill.description
	return b


func _on_skill_picked(actor: Combatant, skill: SkillData) -> void:
	var foes := system.living(system.foes_of(actor))
	if skill.target != SkillData.Target.ONE_ENEMY or foes.size() == 1:
		_command_chosen.emit(skill, foes[0] if skill.target == SkillData.Target.ONE_ENEMY else null)
		return
	_targeting_skill = skill
	_clear_commands()
	_command_box.add_child(UITheme.button("Back", func() -> void: _show_main_commands(actor), 172))
	_place_command_panel()
	_hint_label.text = "Tap a target for %s" % skill.display_name
	_hint_label.visible = true
	_select(foes[0])


func _select(c: Combatant) -> void:
	_selector.visible = true
	_selector.position = _actors[c].position + Vector3(0, 0.05, 0)
	_selector.set_meta("target", c)


func _unhandled_input(event: InputEvent) -> void:
	if _targeting_skill == null:
		return
	if not (event is InputEventScreenTouch and event.pressed):
		return
	if _command_panel.get_global_rect().has_point(event.position):
		return
	var best: Combatant = null
	var best_dist := TAP_RADIUS
	for c in system.living(system.enemies):
		var node: Node3D = _actors[c]
		var screen := _camera.unproject_position(node.position + Vector3(0, 0.7, 0))
		var d: float = screen.distance_to(event.position)
		if d < best_dist:
			best = c
			best_dist = d
	if best == null:
		return
	# First tap selects, second tap on the same enemy confirms.
	if _selector.get_meta("target", null) == best:
		_command_chosen.emit(_targeting_skill, best)
	else:
		_select(best)


# --- Effects ---------------------------------------------------------------

func _animate(result: Dictionary) -> void:
	var actor: Combatant = result.actor
	var skill: SkillData = result.skill
	var node: Node3D = _actors[actor]
	var home := node.position
	var hits: Array = result.hits

	var sprite := _sprite(actor)
	match skill.kind:
		SkillData.Kind.PHYSICAL:
			var dest := home
			if hits.size() == 1:
				dest = home.lerp(_actors[hits[0].target].position, 0.7)
			else:
				dest = home + HD2D.iso_right() * (1.0 if actor.is_player else -1.0)
			SpriteSheets.play_then_idle(sprite, &"attack")
			var t := create_tween()
			t.tween_property(node, "position", dest, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			await t.finished
			_apply_hits(hits, skill)
			t = create_tween()
			t.tween_property(node, "position", home, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			await t.finished
		SkillData.Kind.QI:
			SpriteSheets.play_then_idle(sprite, &"cast")
			await _cast_glow(node, skill.fx_color, 0.35)
			await _projectiles(node.position, hits, skill.fx_color)
			_apply_hits(hits, skill)
		SkillData.Kind.STELLAR:
			SpriteSheets.play_then_idle(sprite, &"cast")
			await _stellar_discharge(node, hits, skill)
		SkillData.Kind.HEAL:
			SpriteSheets.play_then_idle(sprite, &"cast")
			await _cast_glow(node, skill.fx_color, 0.5)
			_apply_hits(hits, skill)
		SkillData.Kind.MARK:
			await _sensor_sweep(node, hits, skill)
		SkillData.Kind.GUARD:
			await _cast_glow(node, skill.fx_color, 0.4)
			HD2D.pop_label(self, node.position + Vector3(0, 2.0, 0), "Guard", skill.fx_color, 48)

	if result.learned != null:
		_log("Cognitive core mapped %s. Optimised." % skill.display_name)
		await _show_banner("Technique mapped: %s" % skill.display_name, UITheme.DIAGNOSTIC, 1.0)
	await _wait(0.3)
	for hit: Dictionary in hits:
		if hit.killed:
			await _defeat_actor(hit.target)


## A scan line passes over the target and it reads as mapped.
func _sensor_sweep(node: Node3D, hits: Array, skill: SkillData) -> void:
	for hit: Dictionary in hits:
		var target_node: Node3D = _actors[hit.target]
		var h := SpriteSheets.height_m(hit.target.data.sprite_id)
		var plane := QuadMesh.new()
		plane.size = Vector2(h * 1.3, 0.05)
		var mat := HD2D.material(skill.fx_color, 0.3, 0.0, skill.fx_color, 6.0)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		var line := HD2D.add_mesh(self, plane, mat, target_node.position + Vector3(0, h + 0.2, 0))
		var t := create_tween()
		t.tween_property(line, "position:y", target_node.position.y, 0.45)
		t.tween_callback(line.queue_free)
		HD2D.pop_label(self, target_node.position + Vector3(0, h + 0.4, 0), "Mapped", skill.fx_color, 40)
		_flash(hit.target, Color(0.7, 0.85, 1.4))
	await _wait(0.5)
	_refresh()


func _apply_hits(hits: Array, skill: SkillData) -> void:
	for hit: Dictionary in hits:
		var target: Combatant = hit.target
		var node: Node3D = _actors[target]
		if hit.heal:
			HD2D.pop_label(self, node.position + Vector3(0, 1.8, 0), "+%d" % hit.amount, Color("8fffb0"))
			continue
		if hit.amount == 0 and hit.status == &"assessed":
			continue
		var color := Color(1.0, 0.9, 0.6) if skill.kind != SkillData.Kind.PHYSICAL else Color.WHITE
		HD2D.pop_label(self, node.position + Vector3(0, 1.6, 0), str(hit.amount), color)
		if hit.status != &"":
			HD2D.pop_label(self, node.position + Vector3(0.4, 2.2, 0), String(hit.status).capitalize(), skill.fx_color, 40)
		_flash(target, Color(2.0, 0.6, 0.5))
		if target.is_alive():
			_hurt(target)
		_shake = maxf(_shake, 0.06)
	_refresh()


## Hurt pose with a small knock-back, then back to idle.
func _hurt(c: Combatant) -> void:
	var sprite := _sprite(c)
	var node: Node3D = _actors[c]
	var home := node.position
	var push := HD2D.iso_right() * (0.35 if not c.is_player else -0.35)
	SpriteSheets.play(sprite, &"hurt")
	var t := create_tween()
	t.tween_property(node, "position", home + push, 0.08)
	t.tween_property(node, "position", home, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_callback(func() -> void:
		if SpriteSheets.is_playing(sprite, &"hurt"):
			SpriteSheets.play(sprite, &"idle"))


func _flash(c: Combatant, color: Color) -> void:
	var sprite := _sprite(c)
	var t := create_tween()
	t.tween_property(sprite, "modulate", color, 0.06)
	t.tween_property(sprite, "modulate", Color.WHITE, 0.2)


func _cast_glow(node: Node3D, color: Color, duration: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.omni_range = 3.5
	light.light_energy = 0.0
	light.position = Vector3(0, 1.0, 0.4)
	node.add_child(light)
	var t := create_tween()
	t.tween_property(light, "light_energy", 4.0, duration * 0.6)
	t.tween_property(light, "light_energy", 0.0, duration * 0.4)
	await t.finished
	light.queue_free()


func _glow_orb(color: Color, radius: float) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	var mat := HD2D.material(color, 0.3, 0.0, color, 4.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var orb := HD2D.add_mesh(self, sphere, mat, Vector3.ZERO)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = 2.5
	orb.add_child(light)
	return orb


func _projectiles(from: Vector3, hits: Array, color: Color) -> void:
	var t := create_tween().set_parallel(true)
	var orbs: Array[MeshInstance3D] = []
	for hit: Dictionary in hits:
		var orb := _glow_orb(color, 0.18)
		orb.position = from + Vector3(0.3, 1.0, 0)
		orbs.append(orb)
		t.tween_property(orb, "position", _actors[hit.target].position + Vector3(0, 0.8, 0), 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await t.finished
	for orb in orbs:
		orb.queue_free()


## Chapter Three: the regulator gives way. She glows amber-gold, then fires a
## column of raw fusion output.
func _stellar_discharge(node: Node3D, hits: Array, skill: SkillData) -> void:
	_log("Regulator override. Thermal threshold climbing.")
	var sprite: AnimatedSprite3D = node.get_node("Sprite")
	var charge := _glow_orb(skill.fx_color, 0.1)
	charge.position = node.position + Vector3(0.2, 1.0, 0)
	var t := create_tween().set_parallel(true)
	t.tween_property(sprite, "modulate", Color(2.2, 1.7, 0.9), 1.0)
	t.tween_property(charge, "scale", Vector3.ONE * 6.0, 1.0).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	t.tween_property(self, "_shake", 0.05, 1.0)
	await t.finished

	# The column: a bright core with a soft additive halo, from her palm outward.
	var start := charge.position
	var end := start + HD2D.iso_right() * 9.0
	var beams: Array[MeshInstance3D] = []
	for layer: Array in [[0.09, 1.0, false], [0.28, 0.35, true]]:
		var beam_mesh := CylinderMesh.new()
		beam_mesh.top_radius = layer[0]
		beam_mesh.bottom_radius = layer[0]
		beam_mesh.height = 1.0
		var beam_mat := HD2D.material(Color(1, 0.9, 0.6, layer[1]), 0.3, 0.0, skill.fx_color, 8.0)
		beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if layer[2]:
			beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		var b := HD2D.add_mesh(self, beam_mesh, beam_mat, (start + end) / 2.0)
		b.look_at_from_position(b.position, end, Vector3.UP)
		b.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		b.scale = Vector3(1, 0.01, 1)
		beams.append(b)
	var beam := beams[0]
	var flash := OmniLight3D.new()
	flash.light_color = skill.fx_color
	flash.light_energy = 12.0
	flash.omni_range = 14.0
	flash.position = HD2D.iso_right() * 2.0 + Vector3(0, 2.0, 0)
	add_child(flash)
	_shake = 0.3
	t = create_tween().set_parallel(true)
	for b in beams:
		t.tween_property(b, "scale", Vector3(1, (end - start).length(), 1), 0.12)
	await t.finished
	_apply_hits(hits, skill)
	t = create_tween().set_parallel(true)
	for b in beams:
		t.tween_property(b, "scale:x", 0.01, 0.6).set_delay(0.3)
		t.tween_property(b, "scale:z", 0.01, 0.6).set_delay(0.3)
	t.tween_property(flash, "light_energy", 0.0, 0.9)
	t.tween_property(charge, "scale", Vector3.ONE * 0.01, 0.4)
	t.tween_property(sprite, "modulate", Color.WHITE, 1.2)
	await t.finished
	for b in beams:
		b.queue_free()
	flash.queue_free()
	charge.queue_free()
	_log("Emergency cooling: full capacity. Heat vented.")


func _defeat_actor(c: Combatant) -> void:
	var node: Node3D = _actors[c]
	if not node.visible:
		return
	var sprite: AnimatedSprite3D = node.get_node("Sprite")
	SpriteSheets.play(sprite, &"hurt")
	var t := create_tween().set_parallel(true)
	t.tween_property(sprite, "modulate", Color(1.5, 0.4, 0.4, 0.0), 0.5)
	t.tween_property(node, "position:y", -0.3, 0.5)
	await t.finished
	node.visible = false
	_refresh()
