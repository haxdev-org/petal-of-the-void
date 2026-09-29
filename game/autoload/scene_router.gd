extends CanvasLayer
## Scene changes with a fade. The flash colour can be overridden for battle
## transitions (e.g. a gold flash when an encounter starts).

const TITLE := "res://scenes/title/title.tscn"
const FIELD := "res://scenes/field/field.tscn"
const BATTLE := "res://scenes/battle/battle.tscn"
const INTRO := "res://scenes/story/intro.tscn"

var _fade: ColorRect
var _busy := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0.02, 0.02, 0.06, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)


func go_to(path: String, color := Color(0.02, 0.02, 0.06), duration := 0.45) -> void:
	if _busy:
		return
	_busy = true
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade.color = Color(color, 0.0)
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, duration)
	await tween.finished
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	tween = create_tween()
	tween.tween_property(_fade, "color:a", 0.0, duration)
	await tween.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_busy = false
