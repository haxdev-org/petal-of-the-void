extends Node
## Graphics quality and input setup. Quality is picked once at startup and can
## be changed from menus later; scenes read it through `Settings.quality`.

signal quality_changed(level: int)

enum Quality { LOW, MEDIUM, HIGH }

const SETTINGS_PATH := "user://settings.cfg"

var quality: int = Quality.HIGH


func _ready() -> void:
	_register_input_actions()
	quality = _default_quality()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		quality = cfg.get_value("graphics", "quality", quality)


func set_quality(level: int) -> void:
	quality = clampi(level, Quality.LOW, Quality.HIGH)
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.save(SETTINGS_PATH)
	quality_changed.emit(quality)


func _default_quality() -> int:
	# The Compatibility renderer is the fallback for older phones; treat it as low-end.
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		return Quality.LOW
	return Quality.HIGH


func _register_input_actions() -> void:
	var keys := {
		&"move_left": [KEY_A, KEY_LEFT],
		&"move_right": [KEY_D, KEY_RIGHT],
		&"move_up": [KEY_W, KEY_UP],
		&"move_down": [KEY_S, KEY_DOWN],
	}
	for action: StringName in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode: Key in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)
