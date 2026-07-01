extends Node

signal fullscreen_changed(active: bool)
signal portrait_recording_changed(active: bool)

const SETTINGS_PATH := "user://display_settings.json"
const SAVE_VERSION := 1
const LANDSCAPE_SIZE := Vector2i(1920, 1080)
const PORTRAIT_SIZE := Vector2i(1080, 1920)

var _fullscreen: bool = false
var _portrait_recording: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_from_disk()
	_reconcile_loaded_settings()
	_apply_display_state()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("toggle_full_screen"):
		return
	toggle_fullscreen()
	get_viewport().set_input_as_handled()


func is_fullscreen() -> bool:
	return _fullscreen


func is_portrait_recording() -> bool:
	if not DevSettings.is_active():
		return false
	return _portrait_recording


func set_fullscreen(active: bool) -> void:
	if _fullscreen == active:
		return
	_fullscreen = active
	if active:
		_clear_portrait_recording()
	_apply_display_state()
	_save_to_disk()
	fullscreen_changed.emit(_fullscreen)


func set_portrait_recording(active: bool) -> void:
	if not DevSettings.is_active():
		return
	if _portrait_recording == active:
		return
	_portrait_recording = active
	if active:
		_fullscreen = false
		fullscreen_changed.emit(false)
	_apply_display_state()
	_save_to_disk()
	portrait_recording_changed.emit(_portrait_recording)


func toggle_fullscreen() -> void:
	set_fullscreen(not _fullscreen)


func _clear_portrait_recording() -> void:
	if not _portrait_recording:
		return
	_portrait_recording = false
	portrait_recording_changed.emit(false)


func _apply_display_state() -> void:
	if _should_use_portrait_window():
		_apply_windowed_size(PORTRAIT_SIZE)
		return
	if _fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	_apply_windowed_size(LANDSCAPE_SIZE)


func _should_use_portrait_window() -> bool:
	if not DevSettings.is_active():
		return false
	return _portrait_recording


func _reconcile_loaded_settings() -> void:
	if not _should_use_portrait_window():
		return
	_fullscreen = false


func _apply_windowed_size(size: Vector2i) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	get_tree().root.size = size


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
	if data.has("portrait_recording"):
		_portrait_recording = bool(data["portrait_recording"])


func _save_to_disk() -> void:
	var data := {
		"version": SAVE_VERSION,
		"fullscreen": _fullscreen,
		"portrait_recording": _portrait_recording,
	}
	var json_text := JSON.stringify(data, "\t")
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("DisplaySettings: failed to write %s (error %d)." % [SETTINGS_PATH, FileAccess.get_open_error()])
		return
	file.store_string(json_text)
