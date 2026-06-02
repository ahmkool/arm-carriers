extends Node

const MENU_SCENE_PATH := "res://src/menu/menu.tscn"

@onready var menu_root: Control = $Layer/MenuRoot
@onready var continue_button: Button = $Layer/MenuRoot/PanelContainer/MarginContainer/VBoxContainer/ContinueButton
@onready var restart_checkpoint_button: Button = $Layer/MenuRoot/PanelContainer/MarginContainer/VBoxContainer/RestartCheckpointButton
@onready var back_to_menu_button: Button = $Layer/MenuRoot/PanelContainer/MarginContainer/VBoxContainer/BackToMenuButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	continue_button.pressed.connect(_on_continue_pressed)
	restart_checkpoint_button.pressed.connect(_on_restart_checkpoint_pressed)
	back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	_set_paused(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_pause_input(event):
		return
	_set_paused(not get_tree().paused)
	get_viewport().set_input_as_handled()


func _is_pause_input(event: InputEvent) -> bool:
	if not event.is_action("pause"):
		return false
	if not event.is_pressed():
		return false
	if event.is_echo():
		return false
	return true


func _on_continue_pressed() -> void:
	_set_paused(false)


func _on_restart_checkpoint_pressed() -> void:
	_set_paused(false)
	var world := _find_world_local()
	if world == null:
		return
	if world.has_method("restart_game"):
		world.call("restart_game")


func _on_back_to_menu_pressed() -> void:
	_set_paused(false)
	var err := get_tree().change_scene_to_file(MENU_SCENE_PATH)
	if err != OK:
		push_error("PauseMenu: failed to change to menu scene (error %d)." % err)


func _set_paused(should_pause: bool) -> void:
	get_tree().paused = should_pause
	menu_root.visible = should_pause


func _find_world_local() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene
