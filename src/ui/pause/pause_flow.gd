class_name PauseFlowNode
extends Node

signal resume_requested

var current: PauseState
var _states: Dictionary = {}
var _current_state_name := ""

var main_root: Control
var options_root: Control
var controls_root: Control
var menu_navigator: GamepadMenuNavigator
var main_focus: Control
var options_focus: Control
var controls_focus: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_state("main", PauseMainState.new())
	_register_state("options", PauseOptionsState.new())
	_register_state("controls", PauseControlsState.new())


func register_pause_ui(
	main: Control,
	options: Control,
	controls: Control,
	navigator: GamepadMenuNavigator,
	main_default_focus: Control,
	options_default_focus: Control,
	controls_default_focus: Control,
) -> void:
	main_root = main
	options_root = options
	controls_root = controls
	menu_navigator = navigator
	main_focus = main_default_focus
	options_focus = options_default_focus
	controls_focus = controls_default_focus
	_connect_menu_cancel()


func start() -> void:
	transition_to("main")


func transition_to(state_name: String) -> void:
	var key := state_name.to_lower()
	if not _states.has(key):
		push_error("PauseFlow: state not found: %s" % state_name)
		return
	if current != null:
		current.exit()
	current = _states[key]
	_current_state_name = key
	current.enter()


func show_pause_screen(screen_name: String) -> void:
	var key := screen_name.to_lower()
	set_main_visible(key == "main")
	set_options_visible(key == "options")
	set_controls_visible(key == "controls")


func set_main_visible(visible: bool) -> void:
	if main_root == null:
		return
	main_root.visible = visible


func set_options_visible(visible: bool) -> void:
	if options_root == null:
		return
	options_root.visible = visible


func set_controls_visible(visible: bool) -> void:
	if controls_root == null:
		return
	controls_root.visible = visible


func set_menu_navigation_active(active: bool, focus: Control = null) -> void:
	if menu_navigator == null:
		return
	if focus != null:
		menu_navigator.set_default_focus(focus)
	menu_navigator.set_active(active)


func set_menu_cancel_enabled(enabled: bool) -> void:
	if menu_navigator == null:
		return
	menu_navigator.emit_cancel_on_back = enabled


func _connect_menu_cancel() -> void:
	if menu_navigator == null:
		return
	if menu_navigator.cancel_pressed.is_connected(_on_menu_cancel):
		return
	menu_navigator.cancel_pressed.connect(_on_menu_cancel)


func _on_menu_cancel() -> void:
	if _current_state_name == "main":
		resume_requested.emit()
		return
	if _current_state_name == "options":
		transition_to("main")
		return
	if _current_state_name == "controls":
		transition_to("main")
		return


func _register_state(state_name: String, state: PauseState) -> void:
	state.pause_flow = self
	_states[state_name.to_lower()] = state
