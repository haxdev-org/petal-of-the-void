extends Node
## Dev tool: visits each scene and saves screenshots for review.
##   godot --path game --rendering-method gl_compatibility res://tools/capture.tscn -- <out_dir>

const SHOTS := [
	{ "scene": SceneRouter.TITLE, "wait": 2.5, "name": "01-title" },
	{ "scene": SceneRouter.INTRO, "wait": 3.5, "name": "02-intro" },
	{ "scene": SceneRouter.FIELD, "wait": 2.5, "name": "03-field" },
	{ "scene": SceneRouter.BATTLE, "wait": 5.0, "name": "04-battle", "encounter": &"ridge_wolves" },
	{ "scene": SceneRouter.BATTLE, "wait": 5.0, "name": "05-battle-bear", "encounter": &"ridge_bear" },
	{ "scene": SceneRouter.BATTLE, "wait": 5.0, "name": "06-stellar-core", "encounter": &"ridge_wolves", "stellar": 1.25 },
]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	# Hand "current scene" to a placeholder so scene changes don't free this node.
	await get_tree().process_frame
	var placeholder := Node.new()
	get_tree().root.add_child(placeholder)
	get_tree().current_scene = placeholder
	Settings.quality = Settings.Quality.HIGH
	for shot: Dictionary in SHOTS:
		GameState.new_game()
		GameState.pending_encounter = { "id": shot.get("encounter", &"ridge_wolves") }
		get_tree().change_scene_to_file(shot.scene)
		await get_tree().create_timer(shot.wait).timeout
		if shot.has("stellar"):
			# Force the player's turn into a Stellar Discharge to preview the effect.
			var battle := get_tree().current_scene
			while not battle._command_panel.visible:
				await get_tree().create_timer(0.1).timeout
			battle.system.party[0].heat = Combatant.MAX_HEAT
			battle._command_chosen.emit(Db.skill(&"stellar_discharge"), null)
			await get_tree().create_timer(shot.stellar).timeout
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join(shot.name + ".png")
		get_viewport().get_texture().get_image().save_png(path)
		print("saved ", path)
	get_tree().quit()
