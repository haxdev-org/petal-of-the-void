extends Node
## Persistent game state: story flags, overworld position and the pending
## battle handoff. Saved as JSON in user://.

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

var flags: Dictionary = {}
var spirit_stones: int = 0
var field_position := Vector3.ZERO
var has_field_position := false
var play_time := 0.0

## Set by the field before switching to the battle scene.
var pending_encounter: Dictionary = {}


func _process(delta: float) -> void:
	play_time += delta


func new_game() -> void:
	flags = {}
	spirit_stones = 0
	field_position = Vector3.ZERO
	has_field_position = false
	play_time = 0.0
	pending_encounter = {}


func set_flag(flag: StringName, value: Variant = true) -> void:
	flags[String(flag)] = value


func has_flag(flag: StringName) -> bool:
	return flags.get(String(flag), false) == true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	var data := {
		"version": SAVE_VERSION,
		"flags": flags,
		"spirit_stones": spirit_stones,
		"field_position": [field_position.x, field_position.y, field_position.z],
		"play_time": play_time,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Could not write save: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


func load_game() -> bool:
	if not has_save():
		return false
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Save file is corrupted.")
		return false
	new_game()
	flags = data.get("flags", {})
	spirit_stones = int(data.get("spirit_stones", 0))
	var pos: Array = data.get("field_position", [])
	if pos.size() == 3:
		field_position = Vector3(pos[0], pos[1], pos[2])
		has_field_position = true
	play_time = float(data.get("play_time", 0.0))
	return true
