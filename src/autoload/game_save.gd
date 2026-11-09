extends Node

const SAVE_PATH := "user://save.json"
## 3: progress is kept per level and weapon ("<level id>@<weapon id>"); see SaveMigration.
## 4: Level 2 was replaced by its medieval reskin; its progress moves over.
const SAVE_VERSION := 4
const WEAPON_SEPARATOR := "@"

var _levels: Dictionary = {}
var _completed: Dictionary = {}
## Character name per device_id, from the character select. Empty until both players picked.
var _character_picks: Array[String] = []
var _tracked_manager: CheckpointManager
var _tracked_level_id: String = ""
var _apply_save_on_next_load := true


func _ready() -> void:
	_load_from_disk()


static func resolve_level_id(level_scene_path: String, level_id: String) -> String:
	if not level_id.is_empty():
		return level_id
	return level_scene_path


## The key a level's progress is saved under when played with this weapon.
## A level without a weapon keeps its bare id.
static func level_key(level_id: String, weapon_id: String) -> String:
	if weapon_id.is_empty():
		return level_id
	return level_id + WEAPON_SEPARATOR + weapon_id


func set_apply_save_on_next_load(apply: bool) -> void:
	_apply_save_on_next_load = apply


func consume_apply_save_on_next_load() -> bool:
	var apply := _apply_save_on_next_load
	_apply_save_on_next_load = true
	return apply


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


func is_level_completed(level_id: String) -> bool:
	if level_id.is_empty():
		return false
	var completed: Variant = _completed.get(level_id, false)
	return completed == true


func mark_level_completed(level_id: String) -> void:
	if level_id.is_empty():
		return
	if is_level_completed(level_id):
		return
	_completed[level_id] = true
	save_to_disk()


func clear_level_completion(level_id: String) -> void:
	if level_id.is_empty():
		return
	if not _completed.has(level_id):
		return
	_completed.erase(level_id)
	save_to_disk()


func get_character_picks() -> Array[String]:
	return _character_picks.duplicate()


func set_character_picks(names: Array[String]) -> void:
	_character_picks = names.duplicate()
	save_to_disk()


func clear_all() -> void:
	_levels.clear()
	_completed.clear()
	save_to_disk()


func clear_level(level_id: String) -> void:
	if level_id.is_empty():
		return
	var changed := false
	if _levels.has(level_id):
		_levels.erase(level_id)
		changed = true
	if _completed.has(level_id):
		_completed.erase(level_id)
		changed = true
	if not changed:
		return
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
		"completed": _completed.duplicate(),
		"characters": _character_picks.duplicate(),
	}
	var json_text := JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("GameSave: failed to write %s (error %d)." % [SAVE_PATH, FileAccess.get_open_error()])
		return
	file.store_string(json_text)


func _load_from_disk() -> void:
	_levels.clear()
	_completed.clear()
	_character_picks.clear()
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
	if data.has("completed") and data["completed"] is Dictionary:
		_completed = (data["completed"] as Dictionary).duplicate()
	_load_character_picks(data.get("characters", []))
	_migrate_from(int(data.get("version", 1)))


## Renames keys in memory only; the file is rewritten in the new format on the next save.
func _migrate_from(version: int) -> void:
	if version >= SAVE_VERSION:
		return
	if version < 3:
		_levels = SaveMigration.migrate_v2_keys(_levels)
		_completed = SaveMigration.migrate_v2_keys(_completed)
	_levels = SaveMigration.migrate_v3_keys(_levels)
	_completed = SaveMigration.migrate_v3_keys(_completed)


func _load_character_picks(saved: Variant) -> void:
	if not saved is Array:
		return
	for entry in saved:
		_character_picks.append(str(entry))


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
