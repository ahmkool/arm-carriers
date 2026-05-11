extends Button

@export_file("*.tscn") var level_scene_path: String = ""


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	if level_scene_path.is_empty():
		push_warning("LevelButton: no level_scene_path assigned.")
		return
	var err := get_tree().change_scene_to_file(level_scene_path)
	if err != OK:
		push_error("LevelButton: failed to change scene (error %d)." % err)
