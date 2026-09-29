class_name TouchJoystick
extends Control
## Floating on-screen joystick. It appears wherever a touch starts inside the
## left-hand activation zone; the field scene routes touches here.

const RADIUS := 90.0

var vector := Vector2.ZERO
var touch_index := -1
var _origin := Vector2.ZERO
var _knob := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Touches starting in the lower-left 40% x 55% of the screen drive the stick.
func in_activation_zone(pos: Vector2) -> bool:
	var size := get_viewport_rect().size
	return pos.x < size.x * 0.4 and pos.y > size.y * 0.45


func start(index: int, pos: Vector2) -> void:
	touch_index = index
	_origin = pos
	_knob = pos
	vector = Vector2.ZERO
	queue_redraw()


func drag(index: int, pos: Vector2) -> void:
	if index != touch_index:
		return
	var offset := (pos - _origin).limit_length(RADIUS)
	_knob = _origin + offset
	vector = offset / RADIUS
	queue_redraw()


func release(index: int) -> void:
	if index != touch_index:
		return
	touch_index = -1
	vector = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	if touch_index < 0:
		return
	draw_circle(_origin, RADIUS, Color(0.07, 0.09, 0.2, 0.45))
	draw_arc(_origin, RADIUS, 0, TAU, 48, Color(0.91, 0.78, 0.45, 0.7), 3.0, true)
	draw_circle(_knob, 36, Color(0.95, 0.94, 0.92, 0.8))
