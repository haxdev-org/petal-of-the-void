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
	# Baihua
	_add_skill(&"strike", "Precise Strike", K.PHYSICAL, T.ONE_ENEMY, 1.0, {
		description = "A chassis-powered strike. Effortless, exact.",
		heat_gain = 15, fx_color = Color.WHITE })
	_add_skill(&"compression_palm", "Compression Palm", K.QI, T.ONE_ENEMY, 1.7, {
		description = "Palm strike with compression return cycle, copied from the Flame Path.",
		qi_cost = 18, heat_gain = 20, fx_color = GOLD })
	_add_skill(&"thousand_year_ember", "Thousand-Year Ember", K.QI, T.ALL_ENEMIES, 1.3, {
		description = "Elder Shen's signature technique. Charge cycle: five seconds, not six.",
		qi_cost = 40, heat_gain = 25, fx_color = Color(1.0, 0.55, 0.25) })
	_add_skill(&"nanobot_repair", "Nanobot Repair", K.HEAL, T.SELF, 0.3, {
		description = "Deploy the maintenance colony. Restores 30% integrity.",
		qi_cost = 25, fx_color = Color(0.6, 0.9, 1.0) })
	_add_skill(&"stillness", "Stillness", K.GUARD, T.SELF, 0.5, {
		description = "Hold position and let the core settle. Halves damage; restores qi.",
		fx_color = VIOLET })
	_add_skill(&"stellar_discharge", "Stellar Discharge", K.STELLAR, T.ALL_ENEMIES, 4.0, {
		description = "Push past the regulator. Raw fusion output. Requires full heat.",
		heat_cost = 100, fx_color = GOLD })
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
	_add_combatant(&"baihua", "Baihua",
		[&"strike", &"compression_palm", &"thousand_year_ember", &"nanobot_repair", &"stillness", &"stellar_discharge"],
		{ max_hp = 420, max_qi = 120, attack = 40, qi_power = 46, defense = 30, resistance = 26,
		  speed = 14, qi_regen = 8, can_copy = true, has_heat = true, sprite_id = &"baihua" })
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
