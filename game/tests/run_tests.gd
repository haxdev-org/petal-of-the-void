extends SceneTree
## Headless tests for the battle rules. Run from the game/ folder:
##   godot --headless --import            (first time, builds the class cache)
##   godot --headless -s tests/run_tests.gd

var _failures := 0
var _count := 0


func _init() -> void:
	for method in get_method_list():
		var name: String = method.name
		if name.begins_with("test_"):
			_count += 1
			call(name)
	print("\n%d tests, %d failures" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)


func _battle(enemy_ids: Array, seed_value := 1234) -> BattleSystem:
	var party: Array[Combatant] = [Combatant.new(Db.combatant(&"baihua"), true)]
	var enemies: Array[Combatant] = []
	for id: StringName in enemy_ids:
		enemies.append(Combatant.new(Db.combatant(id)))
	return BattleSystem.new(party, enemies, seed_value)


func test_turn_order_preview_matches_actual_order() -> void:
	var system := _battle([&"acid_fang_wolf", &"quill_bear"])
	var predicted := system.turn_order_preview(8)
	for i in 8:
		var actual := system.advance_to_next_actor()
		check(actual == predicted[i], "turn %d: preview %s, actual %s" % [i, predicted[i].display_name, actual.display_name])


func test_faster_units_act_more_often() -> void:
	var system := _battle([&"quill_bear"])
	var turns := {}
	for i in 60:
		var actor := system.advance_to_next_actor()
		turns[actor] = turns.get(actor, 0) + 1
	var baihua := system.party[0]
	var bear := system.enemies[0]
	check(turns[baihua] > turns[bear], "Baihua (speed 14) should out-act the bear (speed 8)")


func test_strike_damages_and_builds_heat() -> void:
	var system := _battle([&"acid_fang_wolf"])
	var baihua := system.party[0]
	var wolf := system.enemies[0]
	var result := system.execute(baihua, Db.skill(&"strike"), [wolf])
	check(wolf.hp < wolf.data.max_hp, "strike should damage the wolf")
	check(result.hits[0].amount > 0, "hit amount recorded")
	check(baihua.heat == 15, "strike adds 15 heat, got %d" % baihua.heat)


func test_stellar_discharge_needs_full_heat() -> void:
	var system := _battle([&"acid_fang_wolf", &"acid_fang_wolf"])
	var baihua := system.party[0]
	var stellar := Db.skill(&"stellar_discharge")
	check(not baihua.can_use(stellar), "stellar locked at 0 heat")
	baihua.heat = Combatant.MAX_HEAT
	check(baihua.can_use(stellar), "stellar available at full heat")
	system.execute(baihua, stellar, system.default_targets(baihua, stellar))
	check(baihua.heat == 0, "stellar consumes the heat")
	check(system.outcome() == BattleSystem.Outcome.VICTORY, "stellar discharge wipes a wolf pack")


func test_baihua_copies_monster_technique_once() -> void:
	var system := _battle([&"acid_fang_wolf", &"acid_fang_wolf"])
	var baihua := system.party[0]
	var wolf := system.enemies[0]
	var acid := Db.skill(&"acid_fang")
	var result := system.execute(wolf, acid, [baihua])
	check(result.learned != null, "acid fang should be learned")
	check(baihua.knows(&"acid_fang"), "Baihua knows acid fang")
	var copy: SkillData = baihua.skills.filter(func(s: SkillData) -> bool: return s.id == &"acid_fang")[0]
	check(copy.optimized and copy.power > acid.power, "copy is optimised")
	check(not acid.optimized and acid.copyable, "shared data is untouched")
	var again := system.execute(system.enemies[1], acid, [baihua])
	check(again.learned == null, "technique is only learned once")
	var fresh := _battle([&"acid_fang_wolf"])
	check(not fresh.party[0].knows(&"acid_fang"), "learned skills don't leak between battles")


func test_corrosion_ticks_and_expires() -> void:
	var system := _battle([&"acid_fang_wolf"])
	var baihua := system.party[0]
	baihua.statuses[&"corroded"] = 2
	var hp := baihua.hp
	check(system.begin_turn(baihua).size() == 1, "corrosion logs")
	check(baihua.hp < hp, "corrosion damages")
	system.begin_turn(baihua)
	check(not baihua.statuses.has(&"corroded"), "corrosion expires")


func test_qi_regenerates_each_turn() -> void:
	var system := _battle([&"acid_fang_wolf"])
	var baihua := system.party[0]
	baihua.qi = 10
	system.begin_turn(baihua)
	check(baihua.qi == 10 + baihua.data.qi_regen, "core-driven qi regeneration")


func test_guard_halves_damage() -> void:
	var a := _battle([&"quill_bear"], 99)
	var b := _battle([&"quill_bear"], 99)
	b.party[0].guarding = true
	var maul := Db.skill(&"maul")
	var normal: int = a.execute(a.enemies[0], maul, [a.party[0]]).hits[0].amount
	var guarded: int = b.execute(b.enemies[0], maul, [b.party[0]]).hits[0].amount
	check(guarded < normal, "guarding reduces damage (%d vs %d)" % [guarded, normal])


func test_full_battle_simulation_finishes() -> void:
	# Baihua on autopilot: stellar when ready, heal when low, otherwise strike.
	for encounter_id: StringName in [&"ridge_wolves", &"ridge_bear", &"ridge_wolf_demon"]:
		var system := _battle(Db.encounter(encounter_id).enemies, 7)
		var turns := 0
		while system.outcome() == BattleSystem.Outcome.ONGOING and turns < 200:
			turns += 1
			var actor := system.advance_to_next_actor()
			system.begin_turn(actor)
			if not actor.is_alive() or system.outcome() != BattleSystem.Outcome.ONGOING:
				continue
			var skill: SkillData
			if actor.is_player:
				if actor.can_use(Db.skill(&"stellar_discharge")):
					skill = Db.skill(&"stellar_discharge")
				elif actor.hp < actor.data.max_hp * 0.4 and actor.can_use(Db.skill(&"nanobot_repair")):
					skill = Db.skill(&"nanobot_repair")
				else:
					skill = Db.skill(&"strike")
				system.execute(actor, skill, system.default_targets(actor, skill))
			else:
				var action := system.choose_enemy_action(actor)
				system.execute(actor, action.skill, action.targets)
		check(system.outcome() == BattleSystem.Outcome.VICTORY,
			"%s should be winnable on autopilot (outcome %d after %d turns)" % [encounter_id, system.outcome(), turns])
