extends Node

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

var _levels: Dictionary = {}
var _tracked_manager: CheckpointManager
var _tracked_level_id: String = ""


func _ready() -> void:
	_load_from_disk()


func get_saved_checkpoint(level_id: String) -> String:
	if level_id.is_empty():
		return ""
	var saved: Variant = _levels.get(level_id, "")
	if saved is String:
		return saved
	return ""


func set_saved_checkpoint(level_id: String, checkpoint_id: String) -> void:
	if level_id.is_empty() or checkpoint_id.is_empty():
		return
	_levels[level_id] = checkpoint_id


func clear_all() -> void:
	_levels.clear()
	save_to_disk()


func clear_level(level_id: String) -> void:
	if level_id.is_empty():
		return
	if not _levels.has(level_id):
		return
	_levels.erase(level_id)
	save_to_disk()


func apply_to_manager(manager: CheckpointManager, level_id: String) -> void:
	if manager == null or level_id.is_empty():
		return
	var saved_id := get_saved_checkpoint(level_id)
	if saved_id.is_empty():
		return
	manager.apply_saved_checkpoint(saved_id)


func track_manager(manager: CheckpointManager, level_id: String) -> void:
	if manager == null or level_id.is_empty():
		return
	_untrack_manager()
	_tracked_manager = manager
	_tracked_level_id = level_id
	manager.checkpoint_changed.connect(_on_checkpoint_changed)
	manager.tree_exiting.connect(_on_tracked_manager_exiting, CONNECT_ONE_SHOT)


func untrack_manager(manager: CheckpointManager) -> void:
	if _tracked_manager != manager:
		return
	_untrack_manager()


func save_to_disk() -> void:
	var data := {
		"version": SAVE_VERSION,
		"levels": _levels.duplicate(),
	}
	var json_text := JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("GameSave: failed to write %s (error %d)." % [SAVE_PATH, FileAccess.get_open_error()])
		return
	file.store_string(json_text)


func _load_from_disk() -> void:
	_levels.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("GameSave: failed to read %s (error %d)." % [SAVE_PATH, FileAccess.get_open_error()])
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed is Dictionary:
		push_error("GameSave: corrupt save file at %s." % SAVE_PATH)
		return
	var data: Dictionary = parsed
	if not data.has("levels") or not data["levels"] is Dictionary:
		push_error("GameSave: save file missing 'levels' section.")
		return
	_levels = (data["levels"] as Dictionary).duplicate()


func _on_checkpoint_changed(
	new_checkpoint: Checkpoint,
	_previous_checkpoint: Checkpoint,
	_entered_by: Node,
) -> void:
	if _tracked_manager == null or _tracked_level_id.is_empty():
		return
	if new_checkpoint == null:
		return
	var new_order: int = _tracked_manager.get_progress_order(new_checkpoint)
	var saved_order: int = _get_saved_progress_order(_tracked_manager, _tracked_level_id)
	if new_order <= saved_order:
		return
	set_saved_checkpoint(_tracked_level_id, new_checkpoint.get_save_id())
	save_to_disk()


func _get_saved_progress_order(manager: CheckpointManager, level_id: String) -> int:
	var saved_id := get_saved_checkpoint(level_id)
	if saved_id.is_empty():
		return -1
	var saved_checkpoint: Checkpoint = manager.get_checkpoint_by_id(saved_id)
	if saved_checkpoint == null:
		return -1
	return manager.get_progress_order(saved_checkpoint)


func _on_tracked_manager_exiting() -> void:
	_untrack_manager()


func _untrack_manager() -> void:
	if _tracked_manager == null:
		_tracked_level_id = ""
		return
	if _tracked_manager.checkpoint_changed.is_connected(_on_checkpoint_changed):
		_tracked_manager.checkpoint_changed.disconnect(_on_checkpoint_changed)
	_tracked_manager = null
	_tracked_level_id = ""
