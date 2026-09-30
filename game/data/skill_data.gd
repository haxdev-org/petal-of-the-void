class_name SkillData
extends Resource
## A battle action: basic strikes, qi techniques, nanobot repair, the stellar
## discharge, and the monster techniques Baihua can copy.

enum Kind { PHYSICAL, QI, HEAL, GUARD, STELLAR, MARK }
enum Target { ONE_ENEMY, ALL_ENEMIES, SELF }

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var kind: Kind = Kind.PHYSICAL
@export var target: Target = Target.ONE_ENEMY
## Damage multiplier for attacks; fraction of max HP for heals.
@export var power := 1.0
@export var qi_cost := 0
## Nanobot colony mass consumed (percent).
@export var nano_cost := 0
## Story flag that unlocks the skill for Baihua (empty = always available).
@export var requires_flag: StringName = &""
## Stellar core heat gained by using the skill.
@export var heat_gain := 0
## Heat required (and consumed) to use the skill.
@export var heat_cost := 0
## Monster techniques Baihua's cognitive core can map and reproduce.
@export var copyable := false
@export var inflicts: StringName = &""
@export_range(0.0, 1.0) var inflict_chance := 0.0
@export var inflict_turns := 0
## Colour used for effects and damage numbers.
@export var fx_color := Color.WHITE
## Set on copies produced by Baihua's technique mapping.
@export var optimized := false


func is_qi_technique() -> bool:
	return kind == Kind.QI or optimized


func is_offensive() -> bool:
	return kind in [Kind.PHYSICAL, Kind.QI, Kind.STELLAR]


## Baihua's cognitive core runs copied patterns through its optimisation
## filters (Chapter Seventeen): slightly stronger and cheaper than the source.
func make_optimized_copy() -> SkillData:
	var copy: SkillData = duplicate()
	copy.optimized = true
	copy.power = snappedf(power * 1.1, 0.01)
	copy.qi_cost = maxi(0, ceili(maxf(qi_cost, 10) * 0.85))
	copy.heat_gain = heat_gain if heat_gain > 0 else 15
	copy.copyable = false
	copy.description = "%s\n[Mapped and optimised by cognitive core.]" % description
	return copy
