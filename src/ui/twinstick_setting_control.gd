class_name TwinstickSettingControl
extends Node

@export var checkbox: CheckButton


func _ready() -> void:
	if checkbox == null:
		return
	checkbox.button_pressed = GameplaySettings.is_twinstick_active()
	checkbox.toggled.connect(_on_toggled)


func _on_toggled(pressed: bool) -> void:
	GameplaySettings.set_twinstick_active(pressed)
