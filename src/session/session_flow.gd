class_name SessionFlowNode
extends Node

const MENU_SCENE_PATH := "res://src/menu/menu.tscn"

var current: SessionState
var _states: Dictionary = {}
var _current_state_name := ""
var _resume_state := "pressstart"

var _pending_level_path := ""
var _pending_level_id := ""
var pending_saved_checkpoint_id := ""

var press_start_root: Control
var home_menu_root: Control
var settings_menu_root: Control
var main_menu_root: Control
var level_start_choice_root: Control
var menu_navigator: GamepadMenuNavigator
var home_menu_focus: Control
var settings_menu_focus: Control
var level_picker_focus: Control
var level_start_choice_focus: Control
var level_start_choice_prompt: Label


func _ready() -> void:
	_register_state("pressstart", PressStartState.new())
	_register_state("homemenu", HomeMenuState.new())
	_register_state("settingsmenu", SettingsMenuState.new())
	_register_state("mainmenu", MainMenuState.new())
	_register_state("levelstartchoice", LevelStartChoiceState.new())


func _unhandled_input(event: InputEvent) -> void:
	if current == null:
		return
	if not current.handle_input(event):
		return
	get_viewport().set_input_as_handled()


func register_menu_ui(
	press_start: Control,
	home_menu: Control,
	settings_menu: Control,
	main_menu: Control,
	level_start_choice: Control,
	navigator: GamepadMenuNavigator,
	home_focus: Control,
	settings_focus: Control,
	level_focus: Control,
	level_start_focus: Control,
	level_start_prompt: Label,
) -> void:
	press_start_root = press_start
	home_menu_root = home_menu
	settings_menu_root = settings_menu
	main_menu_root = main_menu
	level_start_choice_root = level_start_choice
	menu_navigator = navigator
	home_menu_focus = home_focus
	settings_menu_focus = settings_focus
	level_picker_focus = level_focus
	level_start_choice_focus = level_start_focus
	level_start_choice_prompt = level_start_prompt
	_connect_menu_cancel()


func start() -> void:
	transition_to(_resume_state)


func transition_to(state_name: String) -> void:
	var key := state_name.to_lower()
	if not _states.has(key):
		push_error("SessionFlow: state not found: %s" % state_name)
		return
	if current != null:
		current.exit()
	current = _states[key]
	_current_state_name = key
	current.enter()


func request_level(level_scene_path: String, level_id: String = "") -> void:
	if level_scene_path.is_empty():
		push_warning("SessionFlow: empty level scene path.")
		return
	var resolved_level_id := level_id
	if resolved_level_id.is_empty():
		resolved_level_id = level_scene_path
	_pending_level_path = level_scene_path
	_pending_level_id = resolved_level_id
	var saved_checkpoint_id := GameSave.get_saved_checkpoint(resolved_level_id)
	if saved_checkpoint_id.is_empty():
		load_level_with_choice(false)
		return
	pending_saved_checkpoint_id = saved_checkpoint_id
	transition_to("levelstartchoice")


func load_level_with_choice(apply_save: bool) -> void:
	if _pending_level_path.is_empty():
		push_warning("SessionFlow: no pending level to load.")
		return
	GameSave.set_apply_save_on_next_load(apply_save)
	load_level(_pending_level_path)
	_clear_pending_level()


func update_level_start_choice_prompt() -> void:
	if level_start_choice_prompt == null:
		return
	if pending_saved_checkpoint_id.is_empty():
		level_start_choice_prompt.text = "Saved progress found."
		return
	level_start_choice_prompt.text = "Continue from %s?" % pending_saved_checkpoint_id


func load_level(level_scene_path: String) -> void:
	if level_scene_path.is_empty():
		push_warning("SessionFlow: empty level scene path.")
		return
	_resume_state = "homemenu"
	var tree := get_tree()
	if tree == null:
		return
	var err := tree.change_scene_to_file(level_scene_path)
	if err != OK:
		push_error("SessionFlow: failed to load level (error %d)." % err)


func go_to_main_menu() -> void:
	_resume_state = "homemenu"
	_clear_pending_level()
	var tree := get_tree()
	if tree == null:
		return
	var err := tree.change_scene_to_file(MENU_SCENE_PATH)
	if err != OK:
		push_error("SessionFlow: failed to load menu (error %d)." % err)


func quit_game() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.quit()


func show_menu_screen(screen_name: String) -> void:
	var key := screen_name.to_lower()
	set_press_start_visible(key == "pressstart")
	set_home_menu_visible(key == "homemenu")
	set_settings_menu_visible(key == "settingsmenu")
	set_main_menu_visible(key == "mainmenu")
	set_level_start_choice_visible(key == "levelstartchoice")


func set_press_start_visible(visible: bool) -> void:
	if press_start_root == null:
		return
	press_start_root.visible = visible


func set_home_menu_visible(visible: bool) -> void:
	if home_menu_root == null:
		return
	home_menu_root.visible = visible


func set_settings_menu_visible(visible: bool) -> void:
	if settings_menu_root == null:
		return
	settings_menu_root.visible = visible


func set_main_menu_visible(visible: bool) -> void:
	if main_menu_root == null:
		return
	main_menu_root.visible = visible


func set_level_start_choice_visible(visible: bool) -> void:
	if level_start_choice_root == null:
		return
	level_start_choice_root.visible = visible


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
	if _current_state_name == "homemenu":
		transition_to("pressstart")
		return
	if _current_state_name == "settingsmenu":
		transition_to("homemenu")
		return
	if _current_state_name == "mainmenu":
		transition_to("homemenu")
		return
	if _current_state_name == "levelstartchoice":
		_clear_pending_level()
		transition_to("mainmenu")


func _clear_pending_level() -> void:
	_pending_level_path = ""
	_pending_level_id = ""
	pending_saved_checkpoint_id = ""


func _register_state(state_name: String, state: SessionState) -> void:
	state.session_flow = self
	_states[state_name.to_lower()] = state
