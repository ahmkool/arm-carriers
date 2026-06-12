extends Button

@export_file("*.tscn") var level_scene_path: String = ""
@export var level_id: String = ""
@export var completed_indicator: String = " ✓"

var _base_text: String = ""


func _ready() -> void:
	_base_text = text
	pressed.connect(_on_pressed)
	_refresh_completion_visual()


func _on_pressed() -> void:
	if level_scene_path.is_empty():
		push_warning("LevelButton: no level_scene_path assigned.")
		return
	SessionFlow.request_level(level_scene_path, level_id)


func _refresh_completion_visual() -> void:
	var resolved_id := GameSave.resolve_level_id(level_scene_path, level_id)
	if resolved_id.is_empty():
		text = _base_text
		return
	if GameSave.is_level_completed(resolved_id):
		text = _base_text + completed_indicator
		return
	text = _base_text
