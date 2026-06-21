class_name FullscreenSettingControl
extends Node

@export var checkbox: CheckButton


func _ready() -> void:
	if checkbox == null:
		return
	checkbox.button_pressed = DisplaySettings.is_fullscreen()
	checkbox.toggled.connect(_on_toggled)
	DisplaySettings.fullscreen_changed.connect(_on_fullscreen_changed)


func _on_toggled(pressed: bool) -> void:
	DisplaySettings.set_fullscreen(pressed)


func _on_fullscreen_changed(active: bool) -> void:
	if checkbox.button_pressed == active:
		return
	checkbox.set_block_signals(true)
	checkbox.button_pressed = active
	checkbox.set_block_signals(false)
