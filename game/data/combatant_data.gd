class_name CombatantData
extends Resource
## Static definition of a party member or monster.

@export var id: StringName
@export var display_name: String
@export var max_hp := 100
@export var max_qi := 0
@export var attack := 10
@export var qi_power := 10
@export var defense := 10
@export var resistance := 10
@export var speed := 10
@export var skills: Array[SkillData] = []
## Qi restored at the start of each turn (Baihua's core-driven regeneration).
@export var qi_regen := 0
## Nanobot colony mass (percent). 0 = no colony.
@export var max_nano := 0
## Colony mass regrown each turn.
@export var nano_regen := 0
## Can observe and copy enemy techniques.
@export var can_copy := false
## Has a stellar core heat gauge.
@export var has_heat := false
## Key into PixelArt placeholder sprites (swap for real art later).
@export var sprite_id: StringName
@export var sprite_scale := 1.0
@export var reward_stones := 0
