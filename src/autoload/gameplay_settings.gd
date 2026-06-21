extends Node

signal twinstick_active_changed(active: bool)

const SETTINGS_PATH := "user://gameplay_settings.json"
const SAVE_VERSION := 1

var _twinstick_active: bool = true


func _ready() -> void:
	_load_from_disk()


func is_twinstick_active() -> bool:
	return _twinstick_active


func set_twinstick_active(active: bool) -> void:
	if _twinstick_active == active:
		return
	_twinstick_active = active
	_save_to_disk()
	twinstick_active_changed.emit(active)


func _load_from_disk() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		push_error("GameplaySettings: failed to read %s (error %d)." % [SETTINGS_PATH, FileAccess.get_open_error()])
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed is Dictionary:
		push_error("GameplaySettings: corrupt settings file at %s." % SETTINGS_PATH)
		return
	var data: Dictionary = parsed
	if data.has("twinstick_active"):
		_twinstick_active = bool(data["twinstick_active"])


func _save_to_disk() -> void:
	var data := {
		"version": SAVE_VERSION,
		"twinstick_active": _twinstick_active,
	}
	var json_text := JSON.stringify(data, "\t")
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("GameplaySettings: failed to write %s (error %d)." % [SETTINGS_PATH, FileAccess.get_open_error()])
		return
	file.store_string(json_text)
