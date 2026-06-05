extends Node

@onready var menu_root: Control = $Layer/MenuRoot
@onready var menu_navigator: GamepadMenuNavigator = $GamepadMenuNavigator
@onready var continue_button: Button = $Layer/MenuRoot/PanelContainer/MarginContainer/VBoxContainer/ContinueButton
@onready var restart_checkpoint_button: Button = $Layer/MenuRoot/PanelContainer/MarginContainer/VBoxContainer/RestartCheckpointButton
@onready var back_to_menu_button: Button = $Layer/MenuRoot/PanelContainer/MarginContainer/VBoxContainer/BackToMenuButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	menu_navigator.process_mode = Node.PROCESS_MODE_ALWAYS
	menu_navigator.cancel_pressed.connect(_on_continue_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	restart_checkpoint_button.pressed.connect(_on_restart_checkpoint_pressed)
	back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	_set_paused(false)


func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	if tree.paused:
		if _is_pause_input(event):
			_set_paused(false)
			_mark_input_handled()
			return
		if menu_navigator.process_input_event(event):
			_mark_input_handled()
		return
	if not _is_pause_input(event):
		return
	_set_paused(true)
	_mark_input_handled()


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
	SessionFlow.go_to_main_menu()


func _set_paused(should_pause: bool) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = should_pause
	menu_root.visible = should_pause
	menu_navigator.set_active(should_pause)


func _mark_input_handled() -> void:
	var viewport := menu_root.get_viewport() if menu_root.is_inside_tree() else null
	if viewport == null:
		return
	viewport.set_input_as_handled()


func _find_world_local() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.current_scene
