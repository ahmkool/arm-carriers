class_name PortraitRecordingSettingControl
extends Node

@export var checkbox: CheckButton


func _ready() -> void:
	if not DevSettings.is_active():
		_hide_setting_row()
		return
	if checkbox == null:
		return
	checkbox.button_pressed = DisplaySettings.is_portrait_recording()
	checkbox.toggled.connect(_on_toggled)
	DisplaySettings.portrait_recording_changed.connect(_on_portrait_recording_changed)


func _hide_setting_row() -> void:
	if checkbox == null:
		return
	var row := checkbox.get_parent()
	if row == null:
		return
	row.get_parent().remove_child(row)
	row.queue_free()


func _on_toggled(pressed: bool) -> void:
	DisplaySettings.set_portrait_recording(pressed)


func _on_portrait_recording_changed(active: bool) -> void:
	if checkbox.button_pressed == active:
		return
	checkbox.set_block_signals(true)
	checkbox.button_pressed = active
	checkbox.set_block_signals(false)
