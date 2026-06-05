extends Button

@export_file("*.tscn") var level_scene_path: String = ""
@export var level_id: String = ""


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	if level_scene_path.is_empty():
		push_warning("LevelButton: no level_scene_path assigned.")
		return
	SessionFlow.request_level(level_scene_path, level_id)
