extends Node

signal fullscreen_changed(active: bool)

const SETTINGS_PATH := "user://display_settings.json"
const SAVE_VERSION := 1

var _fullscreen: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_from_disk()
	_apply_fullscreen(_fullscreen)


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_full_screen"):
		return
	toggle_fullscreen()
	get_viewport().set_input_as_handled()


func is_fullscreen() -> bool:
	return _fullscreen


func set_fullscreen(active: bool) -> void:
	if _fullscreen == active:
		return
	_fullscreen = active
	_apply_fullscreen(_fullscreen)
	_save_to_disk()
	fullscreen_changed.emit(_fullscreen)


func toggle_fullscreen() -> void:
	set_fullscreen(not _fullscreen)


func _apply_fullscreen(active: bool) -> void:
	if active:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _load_from_disk() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		push_error("DisplaySettings: failed to read %s (error %d)." % [SETTINGS_PATH, FileAccess.get_open_error()])
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed is Dictionary:
		push_error("DisplaySettings: corrupt settings file at %s." % SETTINGS_PATH)
		return
	var data: Dictionary = parsed
	if data.has("fullscreen"):
		_fullscreen = bool(data["fullscreen"])


func _save_to_disk() -> void:
	var data := {
		"version": SAVE_VERSION,
		"fullscreen": _fullscreen,
	}
	var json_text := JSON.stringify(data, "\t")
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("DisplaySettings: failed to write %s (error %d)." % [SETTINGS_PATH, FileAccess.get_open_error()])
		return
	file.store_string(json_text)
