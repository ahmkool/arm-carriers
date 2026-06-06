extends Node

const SETTINGS_PATH := "user://audio_settings.json"
const SAVE_VERSION := 1
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

var _music_volume: float = 1.0
var _sfx_volume: float = 1.0


func _ready() -> void:
	_validate_buses()
	_load_from_disk()
	_apply_all()


func get_music_volume() -> float:
	return _music_volume


func get_sfx_volume() -> float:
	return _sfx_volume


func set_music_volume(linear: float) -> void:
	print("set_music_volume: %s" % linear)
	_music_volume = clampf(linear, 0.0, 1.0)
	_apply_bus_volume(BUS_MUSIC, _music_volume)
	_save_to_disk()


func set_sfx_volume(linear: float) -> void:
	_sfx_volume = clampf(linear, 0.0, 1.0)
	_apply_bus_volume(BUS_SFX, _sfx_volume)
	_save_to_disk()


func volume_to_slider_percent(linear: float) -> float:
	return linear * 100.0


func slider_percent_to_volume(percent: float) -> float:
	return clampf(percent / 100.0, 0.0, 1.0)


func _apply_all() -> void:
	_apply_bus_volume(BUS_MUSIC, _music_volume)
	_apply_bus_volume(BUS_SFX, _sfx_volume)


func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		push_error("AudioSettings: bus not found: %s" % bus_name)
		return
	if linear <= 0.0:
		AudioServer.set_bus_mute(bus_index, true)
		return
	AudioServer.set_bus_mute(bus_index, false)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear))


func _validate_buses() -> void:
	if AudioServer.get_bus_index(BUS_MUSIC) < 0:
		push_error("AudioSettings: Music bus missing from project audio layout.")
	if AudioServer.get_bus_index(BUS_SFX) < 0:
		push_error("AudioSettings: SFX bus missing from project audio layout.")


func _load_from_disk() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		push_error("AudioSettings: failed to read %s (error %d)." % [SETTINGS_PATH, FileAccess.get_open_error()])
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed == null or not parsed is Dictionary:
		push_error("AudioSettings: corrupt settings file at %s." % SETTINGS_PATH)
		return
	var data: Dictionary = parsed
	if data.has("music_volume"):
		_music_volume = clampf(float(data["music_volume"]), 0.0, 1.0)
	if data.has("sfx_volume"):
		_sfx_volume = clampf(float(data["sfx_volume"]), 0.0, 1.0)


func _save_to_disk() -> void:
	var data := {
		"version": SAVE_VERSION,
		"music_volume": _music_volume,
		"sfx_volume": _sfx_volume,
	}
	var json_text := JSON.stringify(data, "\t")
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_error("AudioSettings: failed to write %s (error %d)." % [SETTINGS_PATH, FileAccess.get_open_error()])
		return
	file.store_string(json_text)
