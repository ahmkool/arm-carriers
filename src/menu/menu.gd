extends Control

@onready var _menu_navigator: GamepadMenuNavigator = $GamepadMenuNavigator


func _ready() -> void:
	_menu_navigator.set_active(true)
