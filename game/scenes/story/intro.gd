extends Control
## Chapter One opening: illustrated panels with captions taken from the novel.
## Tap to advance (or to finish the current line); Skip jumps to the field.

const DIR := "res://assets/story/chapter-01/"

## Each panel: image, crop region (drops letterbox bars and the watermark),
## caption, and whether the caption is Baihua's diagnostic voice. Panels with
## text drawn into the art use a gentler "zoom" so the text stays on screen.
const PANELS := [
	{ "image": "01-falling-star-over-the-jade-canopy.webp", "region": Rect2(0, 0, 1300, 710),
	  "text": "The sky above the Jade Canopy Mountains split open without warning.", "diagnostic": false },
	{ "image": "02-impact-on-broken-tooth-ridge.webp", "region": Rect2(0, 0, 1300, 710),
	  "text": "The streak hit the eastern slope of Broken Tooth Ridge.", "diagnostic": false },
	{ "image": "03-waking-in-the-crater.webp", "region": Rect2(0, 0, 1300, 710),
	  "text": "At the center of the glass, half-buried in scorched earth, a girl lay on her back with her eyes closed.", "diagnostic": false },
	{ "image": "04-internal-query-designation-corrupted.webp", "region": Rect2(84, 0, 1250, 703), "zoom": 1.02,
	  "text": "She ran an internal query.", "diagnostic": false },
	{ "image": "05-rising-from-the-glass.webp", "region": Rect2(0, 0, 1300, 710),
	  "text": "4.3 tonnes of compacted sediment across her dorsal chassis.\nHer limbs could move beneath it if she chose to move them.", "diagnostic": true },
	{ "image": "06-dimensional-displacement-confirmed.webp", "region": Rect2(0, 96, 1270, 610),
	  "text": "She did not know how she knew this.", "diagnostic": false },
	{ "image": "07-system-check-integrity-91.webp", "region": Rect2(40, 60, 1260, 700), "zoom": 1.02,
	  "text": "Not memory. Something deeper, something that had survived whatever had destroyed everything else.", "diagnostic": false },
	{ "image": "08-leaving-the-crater.webp", "region": Rect2(0, 24, 1300, 686),
	  "text": "North was away from the crater. Away from the impact.\nShe began walking.", "diagnostic": false },
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
	band.offset_top = -118
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)

	_caption = Label.new()
	_caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -112
	_caption.offset_bottom = -12
	_caption.offset_left = 60
	_caption.offset_right = -60
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_size_override("font_size", 28)
	add_child(_caption)

	var skip := UITheme.button("Skip", _finish, 140)
	UITheme.pin_top_right(skip, 140, 72)
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
	var zoom: float = panel.get("zoom", 1.1)
	var drift := Vector2(-15 if _index % 2 else 15, -10) if zoom > 1.05 else Vector2.ZERO
	_art.show_image(DIR + panel.image, panel.region, 9.0, zoom, drift)
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
