class_name Db
extends RefCounted
## Game content defined in code for the skeleton. Once the numbers settle this
## can move to .tres files so it's editable in the Godot inspector.

const GOLD := Color(1.0, 0.82, 0.45)
const VIOLET := Color(0.66, 0.5, 1.0)
const ACID := Color(0.6, 1.0, 0.35)
const BLOOD := Color(1.0, 0.35, 0.3)

static var _skills: Dictionary = {}
static var _combatants: Dictionary = {}
static var _encounters: Dictionary = {}


static func skill(id: StringName) -> SkillData:
	_ensure_loaded()
	return _skills[id]


static func combatant(id: StringName) -> CombatantData:
	_ensure_loaded()
	return _combatants[id]


## Baihua as the story has her at this point. Story flags:
##   cultivation        Chapter Fourteen: the encoded chassis carries real qi
##   technique_mapping  Chapter Seventeen: copies techniques she observes
## Before those she fights with the chassis, the core and the nanobot colony.
static func player_data(flags: Dictionary) -> CombatantData:
	_ensure_loaded()
	var base: CombatantData = _combatants[&"baihua"]
	var data: CombatantData = base.duplicate()
	var cultivation: bool = flags.get("cultivation", false) == true
	var mapping: bool = flags.get("technique_mapping", false) == true
	var kit: Array[SkillData] = []
	for s in base.skills:
		if s.requires_flag == &"" or flags.get(String(s.requires_flag), false) == true:
			kit.append(s)
	data.skills = kit
	data.max_qi = base.max_qi if cultivation else 0
	data.qi_regen = base.qi_regen if cultivation else 0
	data.qi_power = base.qi_power if cultivation else 0
	data.can_copy = mapping
	return data


static func encounter(id: StringName) -> Dictionary:
	_ensure_loaded()
	return _encounters[id]


static func _ensure_loaded() -> void:
	if not _skills.is_empty():
		return
	_define_skills()
	_define_combatants()
	_define_encounters()


static func _add_skill(id: StringName, display_name: String, kind: SkillData.Kind,
		target: SkillData.Target, power: float, fields := {}) -> void:
	var s := SkillData.new()
	s.id = id
	s.display_name = display_name
	s.kind = kind
	s.target = target
	s.power = power
	for key: String in fields:
		s.set(key, fields[key])
	_skills[id] = s


static func _define_skills() -> void:
	var K := SkillData.Kind
	var T := SkillData.Target
	# Baihua, from the crash onward: chassis, fusion core, nanobots, sensors.
	_add_skill(&"strike", "Precise Strike", K.PHYSICAL, T.ONE_ENEMY, 1.0, {
		description = "A chassis-powered strike. Effortless, exact.",
		heat_gain = 15, fx_color = Color.WHITE })
	_add_skill(&"core_surge", "Core Surge", K.PHYSICAL, T.ONE_ENEMY, 2.3, {
		description = "Draw a surge from the fusion core into her limbs. Spends 40 heat.",
		heat_cost = 40, fx_color = Color("ffb35c") })
	_add_skill(&"assess", "Sensor Sweep", K.MARK, T.ONE_ENEMY, 0.0, {
		description = "Map the target's structure. Her strikes on it land 35% harder for 3 turns.",
		inflicts = &"assessed", inflict_turns = 3, fx_color = Color("b8d8ff") })
	_add_skill(&"nanobot_repair", "Nanobot Repair", K.HEAL, T.SELF, 0.3, {
		description = "Deploy the maintenance colony. Restores 30% integrity; costs 25% colony mass.",
		nano_cost = 25, fx_color = Color(0.6, 0.9, 1.0) })
	_add_skill(&"stillness", "Stillness", K.GUARD, T.SELF, 0.5, {
		description = "Hold position and let the core settle. Halves incoming damage.",
		fx_color = VIOLET })
	_add_skill(&"stellar_discharge", "Stellar Discharge", K.STELLAR, T.ALL_ENEMIES, 4.0, {
		description = "Push past the regulator. Raw fusion output. Requires full heat.",
		heat_cost = 100, fx_color = GOLD })
	# Baihua, after the artificial path (Chapter Fourteen): genuine qi.
	_add_skill(&"qi_palm", "Qi Palm", K.QI, T.ONE_ENEMY, 1.6, {
		description = "Qi driven through the encoded channels. Dense, unaligned, pale gold.",
		qi_cost = 18, heat_gain = 15, requires_flag = &"cultivation", fx_color = GOLD })
	# After the plateau spar (Chapter Seventeen): copied Flame Path techniques.
	_add_skill(&"compression_palm", "Compression Palm", K.QI, T.ONE_ENEMY, 2.0, {
		description = "Palm strike with compression return cycle, copied from the Flame Path.",
		qi_cost = 22, heat_gain = 20, requires_flag = &"technique_mapping", fx_color = GOLD })
	_add_skill(&"thousand_year_ember", "Thousand-Year Ember", K.QI, T.ALL_ENEMIES, 1.3, {
		description = "Elder Shen's signature technique. Charge cycle: five seconds, not six.",
		qi_cost = 40, heat_gain = 25, requires_flag = &"technique_mapping", fx_color = Color(1.0, 0.55, 0.25) })
	# Monsters
	_add_skill(&"bite", "Bite", K.PHYSICAL, T.ONE_ENEMY, 1.0, { fx_color = Color.WHITE })
	_add_skill(&"acid_fang", "Acid Fang", K.PHYSICAL, T.ONE_ENEMY, 1.2, {
		description = "Corrosive saliva that etches armour.",
		copyable = true, inflicts = &"corroded", inflict_chance = 0.6, inflict_turns = 3,
		fx_color = ACID })
	_add_skill(&"maul", "Maul", K.PHYSICAL, T.ONE_ENEMY, 1.3, { fx_color = Color.WHITE })
	_add_skill(&"quill_volley", "Quill Volley", K.PHYSICAL, T.ALL_ENEMIES, 0.9, {
		description = "A spray of spine quills.", copyable = true, fx_color = Color(0.9, 0.8, 0.6) })
	_add_skill(&"rend", "Rend", K.PHYSICAL, T.ONE_ENEMY, 1.3, { fx_color = BLOOD })
	_add_skill(&"red_rush", "Red Rush", K.PHYSICAL, T.ONE_ENEMY, 1.7, {
		description = "A demon-fuelled lunge.", copyable = true, fx_color = BLOOD })


static func _add_combatant(id: StringName, display_name: String, skill_ids: Array, fields: Dictionary) -> void:
	var c := CombatantData.new()
	c.id = id
	c.display_name = display_name
	for key: String in fields:
		c.set(key, fields[key])
	var list: Array[SkillData] = []
	for skill_id: StringName in skill_ids:
		list.append(_skills[skill_id])
	c.skills = list
	_combatants[id] = c


static func _define_combatants() -> void:
	# Baihua's full kit; player_data() trims it to what the story has unlocked.
	_add_combatant(&"baihua", "Baihua",
		[&"strike", &"core_surge", &"assess", &"nanobot_repair", &"stillness", &"stellar_discharge",
		 &"qi_palm", &"compression_palm", &"thousand_year_ember"],
		{ max_hp = 420, max_qi = 120, attack = 40, qi_power = 46, defense = 30, resistance = 26,
		  speed = 14, qi_regen = 8, max_nano = 100, nano_regen = 4, can_copy = true, has_heat = true, sprite_id = &"baihua" })
	_add_combatant(&"acid_fang_wolf", "Acid-Fang Wolf", [&"bite", &"acid_fang"],
		{ max_hp = 70, attack = 24, defense = 8, resistance = 5, speed = 12,
		  sprite_id = &"wolf", reward_stones = 2 })
	_add_combatant(&"quill_bear", "Quill-Bear", [&"maul", &"quill_volley"],
		{ max_hp = 260, attack = 32, defense = 18, resistance = 10, speed = 8,
		  sprite_id = &"quill_bear", sprite_scale = 1.5, reward_stones = 8 })
	_add_combatant(&"wolf_demon", "Wolf-Demon", [&"rend", &"red_rush"],
		{ max_hp = 380, attack = 38, defense = 20, resistance = 15, speed = 13,
		  sprite_id = &"wolf_demon", sprite_scale = 1.9, reward_stones = 15 })


static func _define_encounters() -> void:
	_encounters[&"ridge_wolves"] = {
		"name": "Acid-Fang Pack",
		"enemies": [&"acid_fang_wolf", &"acid_fang_wolf", &"acid_fang_wolf", &"acid_fang_wolf"],
		"flag": &"beat_ridge_wolves",
	}
	_encounters[&"ridge_bear"] = {
		"name": "Displaced Quill-Bear",
		"enemies": [&"quill_bear"],
		"flag": &"beat_ridge_bear",
	}
	_encounters[&"ridge_wolf_demon"] = {
		"name": "Wolf-Demon",
		"enemies": [&"wolf_demon", &"acid_fang_wolf"],
		"flag": &"beat_ridge_wolf_demon",
	}
