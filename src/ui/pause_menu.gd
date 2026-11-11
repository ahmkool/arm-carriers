extends Node

const _PAUSE_BLOCKED_STATE_NAMES: Array[String] = [
	"resettingcheckpoint",
	"levelfinished",
	"gameoverlost",
]

@onready var _menu_root: Control = $Layer/MenuRoot
@onready var _pause_flow: PauseFlowNode = $PauseFlow
@onready var _juice: PauseMenuJuice = $PauseMenuJuice
@onready var _menu_navigator: GamepadMenuNavigator = $GamepadMenuNavigator
@onready var _main_root: Control = $Layer/MenuRoot/PauseMainRoot
@onready var _options_root: Control = $Layer/MenuRoot/PauseOptionsRoot
@onready var _controls_root: Control = $Layer/MenuRoot/PauseControlsRoot
@onready var _checkpoints_root: Control = $Layer/MenuRoot/PauseCheckpointsRoot
@onready var _continue_button: Button = $Layer/MenuRoot/PauseMainRoot/PanelContainer/MarginContainer/VBoxContainer/ContinueButton
@onready var _options_button: Button = $Layer/MenuRoot/PauseMainRoot/PanelContainer/MarginContainer/VBoxContainer/OptionsButton
@onready var _controls_button: Button = $Layer/MenuRoot/PauseMainRoot/PanelContainer/MarginContainer/VBoxContainer/ControlsButton
@onready var _restart_checkpoint_button: Button = $Layer/MenuRoot/PauseMainRoot/PanelContainer/MarginContainer/VBoxContainer/RestartCheckpointButton
@onready var _checkpoints_button: Button = $Layer/MenuRoot/PauseMainRoot/PanelContainer/MarginContainer/VBoxContainer/CheckpointsButton
@onready var _back_to_menu_button: Button = $Layer/MenuRoot/PauseMainRoot/PanelContainer/MarginContainer/VBoxContainer/BackToMenuButton
@onready var _options_back_button: Button = $Layer/MenuRoot/PauseOptionsRoot/PanelContainer/MarginContainer/VBoxContainer/BackButton
@onready var _controls_panel: ControlsInfoPanel = $Layer/MenuRoot/PauseControlsRoot/PanelContainer
@onready var _controls_back_button: Button = $Layer/MenuRoot/PauseControlsRoot/PanelContainer/MarginContainer/ScrollContainer/VBoxContainer/BackButton
@onready var _checkpoints_scroll: ScrollContainer = $Layer/MenuRoot/PauseCheckpointsRoot/PanelContainer/MarginContainer/VBoxContainer/ScrollContainer
@onready var _checkpoint_list: VBoxContainer = $Layer/MenuRoot/PauseCheckpointsRoot/PanelContainer/MarginContainer/VBoxContainer/ScrollContainer/ListMargin/CheckpointList
@onready var _checkpoints_back_button: Button = $Layer/MenuRoot/PauseCheckpointsRoot/PanelContainer/MarginContainer/VBoxContainer/BackButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_menu_navigator.process_mode = Node.PROCESS_MODE_ALWAYS
	_continue_button.pressed.connect(_on_continue_pressed)
	_options_button.pressed.connect(_on_options_pressed)
	_controls_button.pressed.connect(_on_controls_pressed)
	_restart_checkpoint_button.pressed.connect(_on_restart_checkpoint_pressed)
	_checkpoints_button.pressed.connect(_on_checkpoints_pressed)
	_back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	_options_back_button.pressed.connect(_on_options_back_pressed)
	_controls_back_button.pressed.connect(_on_controls_back_pressed)
	_checkpoints_back_button.pressed.connect(_on_checkpoints_back_pressed)
	_pause_flow.resume_requested.connect(_on_continue_pressed)
	_pause_flow.register_pause_ui(
		_main_root,
		_options_root,
		_controls_root,
		_menu_navigator,
		_continue_button,
		_options_back_button,
		_controls_back_button,
		_checkpoints_root,
		_checkpoints_back_button,
	)
	_refresh_checkpoints_button()
	_set_paused(false)


func _unhandled_input(event: InputEvent) -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null:
		return
	if tree.paused:
		_handle_paused_input(event)
		return
	if not _is_pause_input(event):
		return
	if not _can_open_pause():
		_mark_input_handled()
		return
	_set_paused(true)
	_mark_input_handled()


func _handle_paused_input(event: InputEvent) -> void:
	if _is_pause_input(event):
		_set_paused(false)
		_mark_input_handled()
		return
	if _try_controls_scroll_input(event):
		return
	if _menu_navigator.process_input_event(event):
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


func _on_checkpoints_pressed() -> void:
	if not _should_show_checkpoints_button():
		return
	var focus_target := _populate_checkpoint_buttons()
	_pause_flow.checkpoints_focus = focus_target
	_pause_flow.transition_to("checkpoints")
	_scroll_to_checkpoint_focus(focus_target)


func _on_checkpoints_back_pressed() -> void:
	_pause_flow.transition_to("main")


func _on_checkpoint_selected(checkpoint: Checkpoint) -> void:
	_set_paused(false)
	var world := _find_world_local() as WorldLocal
	if world == null:
		return
	world.jump_to_checkpoint(checkpoint)


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
	if not should_pause:
		_menu_navigator.set_active(false)
		_juice.close()
		return
	_refresh_checkpoints_button()
	_menu_root.visible = false
	_pause_flow.start()
	_juice.open()
	_menu_navigator.set_active(true)


func _refresh_checkpoints_button() -> void:
	_checkpoints_button.visible = _should_show_checkpoints_button()


func _should_show_checkpoints_button() -> bool:
	if not DevSettings.has_checkpoint_selector():
		return false
	return not _get_world_checkpoints().is_empty()


func _populate_checkpoint_buttons() -> Control:
	_clear_checkpoint_buttons()
	var manager := _find_checkpoint_manager()
	var checkpoints := _get_world_checkpoints()
	if manager == null or checkpoints.is_empty():
		return _checkpoints_back_button
	var buttons: Array[Control] = []
	var focus_target: Control = null
	for index in checkpoints.size():
		var checkpoint := checkpoints[index]
		var is_current := checkpoint == manager.current_checkpoint
		var button := _create_checkpoint_button(checkpoint, index + 1, is_current)
		_checkpoint_list.add_child(button)
		_juice.watch_controls(button)
		button.pressed.connect(_on_checkpoint_selected.bind(checkpoint))
		buttons.append(button)
		if is_current:
			focus_target = button
	buttons.append(_checkpoints_back_button)
	_wire_focus_chain(buttons)
	if focus_target != null:
		return focus_target
	return buttons[0]


func _clear_checkpoint_buttons() -> void:
	for child in _checkpoint_list.get_children():
		_checkpoint_list.remove_child(child)
		child.queue_free()


func _create_checkpoint_button(checkpoint: Checkpoint, number: int, is_current: bool) -> Button:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.text = _format_checkpoint_label(checkpoint, number, is_current)
	var style_source := _continue_button if is_current else _restart_checkpoint_button
	_copy_button_styles(style_source, button)
	return button


func _format_checkpoint_label(checkpoint: Checkpoint, number: int, is_current: bool) -> String:
	var base := "%d. %s" % [number, checkpoint.get_save_id()]
	if not is_current:
		return base
	return "%s (Current)" % base


func _copy_button_styles(source: Button, target: Button) -> void:
	for style_name in ["normal", "pressed", "hover", "focus"]:
		var style := source.get_theme_stylebox(style_name)
		if style != null:
			target.add_theme_stylebox_override(style_name, style)


func _wire_focus_chain(controls: Array[Control]) -> void:
	var count := controls.size()
	if count == 0:
		return
	for index in count:
		var current_control := controls[index]
		var prev_control := controls[(index - 1 + count) % count]
		var next_control := controls[(index + 1) % count]
		var prev_path := current_control.get_path_to(prev_control)
		var next_path := current_control.get_path_to(next_control)
		current_control.focus_neighbor_top = prev_path
		current_control.focus_previous = prev_path
		current_control.focus_neighbor_bottom = next_path
		current_control.focus_next = next_path


func _scroll_to_checkpoint_focus(focus_target: Control) -> void:
	if focus_target == null or focus_target == _checkpoints_back_button:
		return
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(focus_target):
		return
	_checkpoints_scroll.ensure_control_visible(focus_target)


func _get_world_checkpoints() -> Array[Checkpoint]:
	var manager := _find_checkpoint_manager()
	if manager == null:
		return []
	return manager.get_checkpoints()


func _find_checkpoint_manager() -> CheckpointManager:
	var world := _find_world_local() as WorldLocal
	if world == null:
		return null
	return world.checkpoint_manager as CheckpointManager


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
