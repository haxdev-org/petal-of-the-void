class_name UITheme
extends RefCounted
## Shared UI theme: ink-blue panels with gold trim, sized for touch
## (buttons at least 72 px tall at the 720 p reference resolution).

const INK := Color(0.07, 0.09, 0.2, 0.88)
const INK_HOVER := Color(0.12, 0.15, 0.32, 0.95)
const GOLD := Color("e8c872")
const TEXT := Color("f2f0ea")
const MUTED := Color(0.75, 0.75, 0.85)
const DIAGNOSTIC := Color("b8d8ff")

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 26

	var normal := _box(INK, GOLD.darkened(0.35))
	var hover := _box(INK_HOVER, GOLD)
	var pressed := _box(Color(0.2, 0.17, 0.35, 0.95), GOLD.lightened(0.2))
	var disabled := _box(Color(0.06, 0.06, 0.12, 0.7), Color(0.3, 0.3, 0.4))
	for state: String in ["normal", "focus"]:
		t.set_stylebox(state, "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD)
	t.set_color("font_pressed_color", "Button", GOLD)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.6))

	t.set_stylebox("panel", "PanelContainer", _box(INK, GOLD.darkened(0.4)))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0.03, 0.02, 0.08))
	t.set_constant("outline_size", "Label", 6)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.05, 0.05, 0.1, 0.9)
	bar_bg.set_corner_radius_all(4)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color("7fd18b")
	bar_fill.set_corner_radius_all(4)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	t.set_font_size("font_size", "ProgressBar", 14)
	_theme = t
	return t


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(10)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box


static func bar(fill: Color) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, 12)
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(4)
	pb.add_theme_stylebox_override("fill", style)
	return pb


## Pin a control to the top-right corner with a fixed size (safe from
## min-size changes when the theme font loads).
static func pin_top_right(control: Control, width: float, height: float, margin := 20.0) -> void:
	control.anchor_left = 1.0
	control.anchor_right = 1.0
	control.anchor_top = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = -width - margin
	control.offset_right = -margin
	control.offset_top = margin
	control.offset_bottom = margin + height


static func button(text: String, callback: Callable, min_width := 200) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 72)
	b.pressed.connect(callback)
	return b
