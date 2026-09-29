extends Control
## Title screen over the cultivation key art, with drifting petals.

const KEY_ART := "res://assets/key-art/cultivation-violet-petals.webp"
## Crop out the watermark in the bottom-right corner.
const KEY_ART_REGION := Rect2(0, 0, 1300, 710)

var _continue_button: Button


func _ready() -> void:
	theme = UITheme.get_theme()
	var art := Illustration.new()
	add_child(art)
	art.show_image(KEY_ART, KEY_ART_REGION, 30.0, 1.12, Vector2(0, -20))
	Illustration.add_petals(self, 50)

	# Darken the lower third so the buttons read clearly.
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.02, 0.02, 0.08, 0.0))
	grad.set_color(1, Color(0.02, 0.02, 0.08, 0.85))
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0, 0.35)
	grad_tex.fill_to = Vector2(0, 1)
	shade.texture = grad_tex
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

	var title := Label.new()
	title.text = "Petal of the Void"
	title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	title.position.y -= 250
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 68)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.add_theme_constant_override("outline_size", 12)
	add_child(title)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 24)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	buttons.grow_horizontal = Control.GROW_DIRECTION_BOTH
	buttons.position.y -= 130
	add_child(buttons)
	buttons.add_child(UITheme.button("New Game", _on_new_game, 260))
	_continue_button = UITheme.button("Continue", _on_continue, 260)
	_continue_button.disabled = not GameState.has_save()
	buttons.add_child(_continue_button)

	for node: CanvasItem in [title, buttons]:
		node.modulate.a = 0.0
		var t := node.create_tween()
		t.tween_interval(0.6 if node == title else 1.2)
		t.tween_property(node, "modulate:a", 1.0, 1.2)


func _on_new_game() -> void:
	GameState.new_game()
	SceneRouter.go_to(SceneRouter.INTRO)


func _on_continue() -> void:
	if GameState.load_game():
		SceneRouter.go_to(SceneRouter.FIELD)
