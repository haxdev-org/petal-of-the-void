class_name Combatant
extends RefCounted
## Runtime battle state for one party member or monster.

const MAX_HEAT := 100
const CT_READY := 100.0

var data: CombatantData
var is_player := false
var hp: int
var qi: int
var heat := 0
## Charge time; the combatant acts when it reaches CT_READY.
var ct := 0.0
var guarding := false
## status id -> turns remaining
var statuses: Dictionary = {}
## Copied per battle so learned techniques don't leak into the shared data.
var skills: Array[SkillData] = []


func _init(p_data: CombatantData, p_is_player := false) -> void:
	data = p_data
	is_player = p_is_player
	hp = data.max_hp
	qi = data.max_qi
	skills = data.skills.duplicate()


## Distinguishes duplicates, e.g. "Acid-Fang Wolf B".
var name_suffix := ""

var display_name: String:
	get: return data.display_name + name_suffix


func is_alive() -> bool:
	return hp > 0


func can_use(skill: SkillData) -> bool:
	return qi >= skill.qi_cost and heat >= skill.heat_cost


func knows(skill_id: StringName) -> bool:
	return skills.any(func(s: SkillData) -> bool: return s.id == skill_id)


func add_heat(amount: int) -> void:
	if data.has_heat:
		heat = clampi(heat + amount, 0, MAX_HEAT)
