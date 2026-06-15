extends Node

const _PAUSE_BLOCKED_STATE_NAMES: Array[String] = [
	"resettingcheckpoint",
	"levelfinished",
	"gameoverlost",
]

@onready var _menu_root: Control = $Layer/MenuRoot
@onready var _pause_flow: PauseFlowNode = $PauseFlow
@onready var _menu_navigator: GamepadMenuNavigator = $GamepadMenuNavigator
@onready var _main_root: Control = $Layer/MenuRoot/PauseMainRoot
@onready var _options_root: Control = $Layer/MenuRoot/PauseOptionsRoot
@onready var _controls_root: Control = $Layer/MenuRoot/PauseControlsRoot
@onready var _continue_button: Button = $Layer/MenuRoot/PauseMainRoot/PanelContainer/MarginContainer/VBoxContainer/ContinueButton
@onready var _options_button: Button = $Layer/MenuRoot/PauseMainRoot/PanelContainer/MarginContainer/VBoxContainer/OptionsButton
@onready var _controls_button: Button = $Layer/MenuRoot/PauseMainRoot/PanelContainer/MarginContainer/VBoxContainer/ControlsButton
@onready var _restart_checkpoint_button: Button = $Layer/MenuRoot/PauseMainRoot/PanelContainer/MarginContainer/VBoxContainer/RestartCheckpointButton
@onready var _back_to_menu_button: Button = $Layer/MenuRoot/PauseMainRoot/PanelContainer/MarginContainer/VBoxContainer/BackToMenuButton
@onready var _options_back_button: Button = $Layer/MenuRoot/PauseOptionsRoot/PanelContainer/MarginContainer/VBoxContainer/BackButton
@onready var _controls_panel: ControlsInfoPanel = $Layer/MenuRoot/PauseControlsRoot/PanelContainer
@onready var _controls_back_button: Button = $Layer/MenuRoot/PauseControlsRoot/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/BackButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_navigator.process_mode = Node.PROCESS_MODE_ALWAYS
	_continue_button.pressed.connect(_on_continue_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_controls_button.pressed.connect(_on_controls_pressed)
	_restart_checkpoint_button.pressed.connect(_on_restart_checkpoint_pressed)
	_back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	_options_back_button.pressed.connect(_on_options_back_pressed)
	_controls_back_button.pressed.connect(_on_controls_back_pressed)
	_pause_flow.resume_requested.connect(_on_continue_pressed)
	_pause_flow.register_pause_ui(
		_main_root,
		_options_root,
		_controls_root,
		_menu_navigator,
		_continue_button,
		_options_back_button,
		_controls_back_button,
	)
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
		if _try_controls_scroll_input(event):
			return
		if _menu_navigator.process_input_event(event):
			_mark_input_handled()
		return
	if not _is_pause_input(event):
		return
	if not _can_open_pause():
		_mark_input_handled()
		return
	_set_paused(true)
	_mark_input_handled()


func _try_controls_scroll_input(event: InputEvent) -> bool:
	if not _controls_root.visible:
		return false
	if not _controls_panel.process_scroll_input(event):
		return false
	_mark_input_handled()
	return true


func _can_open_pause() -> bool:
	var world := _find_world_local() as WorldLocal
	if world == null:
		return true
	var gsm := world.get_node_or_null("GameStateMachine") as GameStateMachine
	if gsm == null or gsm.current == null:
		return true
	return gsm.current.name.to_lower() not in _PAUSE_BLOCKED_STATE_NAMES


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


func _on_options_pressed() -> void:
	_pause_flow.transition_to("options")


func _on_controls_pressed() -> void:
	_pause_flow.transition_to("controls")


func _on_options_back_pressed() -> void:
	_pause_flow.transition_to("main")


func _on_controls_back_pressed() -> void:
	_pause_flow.transition_to("main")


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
	_menu_root.visible = should_pause
	if not should_pause:
		_menu_navigator.set_active(false)
		return
	_pause_flow.start()
	_menu_navigator.set_active(true)


func _mark_input_handled() -> void:
	var viewport := _menu_root.get_viewport() if _menu_root.is_inside_tree() else null
	if viewport == null:
		return
	viewport.set_input_as_handled()


func _find_world_local() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.current_scene
