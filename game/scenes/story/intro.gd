extends Control
## Chapter One opening: illustrated panels with captions taken from the novel.
## Tap to advance (or to finish the current line); Skip jumps to the field.

const DIR := "res://assets/story/chapter-01/"

## Each panel: image, crop region (drops letterbox bars and the watermark),
## caption, and whether the caption is Baihua's diagnostic voice.
const PANELS := [
	{ "image": "01-impact-on-broken-tooth-ridge.png", "region": Rect2(0, 0, 1300, 710),
	  "text": "The sky above the Jade Canopy Mountains split open without warning.", "diagnostic": false },
	{ "image": "02-waking-in-the-crater.png", "region": Rect2(0, 0, 1300, 710),
	  "text": "DESIGNATION: [ERROR: FILE CORRUPTED]\nHOME COORDINATE: [ERROR: NAVIGATION MATRIX OFFLINE]", "diagnostic": true },
	{ "image": "03-rising-from-the-glass.png", "region": Rect2(0, 0, 1300, 710),
	  "text": "Structural integrity: 91%. Cognitive core: stable. Fusion core output: nominal.\nMemory architecture: severe damage.", "diagnostic": true },
	{ "image": "04-dimensional-displacement-confirmed.png", "region": Rect2(0, 96, 1270, 610),
	  "text": "Dimensional displacement confirmed. She did not know how she knew this.", "diagnostic": false },
	{ "image": "05-leaving-the-crater.png", "region": Rect2(0, 24, 1300, 686),
	  "text": "Dimensional variance high. Treat all data as provisional.\nShe began walking north.", "diagnostic": true },
]

var _index := -1
var _art: Illustration
var _caption: Label
var _typing: Tween


func _ready() -> void:
	theme = UITheme.get_theme()
	_art = Illustration.new()
	add_child(_art)

	var band := ColorRect.new()
	band.color = Color(0.02, 0.02, 0.07, 0.72)
	band.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_top = -150
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)

	_caption = Label.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -140
	_caption.offset_bottom = -20
	_caption.offset_left = 60
	_caption.offset_right = -60
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 28)
	add_child(_caption)

	var skip := UITheme.button("Skip", _finish, 140)
	skip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 20)
	add_child(skip)
	_next()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _typing and _typing.is_running():
			_typing.kill()
			_caption.visible_ratio = 1.0
		else:
			_next()


func _next() -> void:
	_index += 1
	if _index >= PANELS.size():
		_finish()
		return
	var panel: Dictionary = PANELS[_index]
	_art.show_image(DIR + panel.image, panel.region, 9.0, 1.1, Vector2(-15 if _index % 2 else 15, -10))
	_art.modulate.a = 0.0
	_art.create_tween().tween_property(_art, "modulate:a", 1.0, 0.7)
	_caption.text = panel.text
	_caption.add_theme_color_override("font_color", UITheme.DIAGNOSTIC if panel.diagnostic else UITheme.TEXT)
	_caption.visible_ratio = 0.0
	_typing = _caption.create_tween()
	_typing.tween_interval(0.5)
	_typing.tween_property(_caption, "visible_ratio", 1.0, panel.text.length() * 0.03)


func _finish() -> void:
	SceneRouter.go_to(SceneRouter.FIELD)
