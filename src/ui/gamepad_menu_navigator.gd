class_name GamepadMenuNavigator
extends Node

signal cancel_pressed

const DOWN_ACTIONS: Array[StringName] = [&"ui_down", &"p0_down", &"p1_down"]
const UP_ACTIONS: Array[StringName] = [&"ui_up", &"p0_up", &"p1_up"]
const ACCEPT_ACTIONS: Array[StringName] = [&"ui_accept", &"p0_accept", &"p1_accept"]
const CANCEL_ACTIONS: Array[StringName] = [&"ui_cancel"]

@export_node_path("Control") var menu_root_path: NodePath
@export_node_path("Control") var default_focus_path: NodePath
@export var enabled_on_ready: bool = false
@export var emit_cancel_on_back: bool = false
## When false, call process_input_event() from a parent (e.g. while the tree is paused).
@export var listen_for_unhandled_input: bool = true

var _menu_root: Control
var _default_focus: Control
var _is_active := false


func _ready() -> void:
	_menu_root = _resolve_control(menu_root_path, "menu_root_path")
	_default_focus = _resolve_control(default_focus_path, "default_focus_path")
	set_active(enabled_on_ready)


func set_active(active: bool) -> void:
	_is_active = active
	set_process_unhandled_input(active and listen_for_unhandled_input)
	if not active:
		_release_focus()
		return
	call_deferred("_grab_default_focus")


func process_input_event(event: InputEvent) -> bool:
	if not _is_active:
		return false
	if not _can_handle(event):
		return false
	if _try_cancel(event):
		return true
	if _try_move_focus(1, event):
		return true
	if _try_move_focus(-1, event):
		return true
	if _try_accept(event):
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not process_input_event(event):
		return
	_mark_input_handled()


func _can_handle(event: InputEvent) -> bool:
	if not is_inside_tree():
		return false
	if not event.is_pressed():
		return false
	if event.is_echo():
		return false
	return true


func _try_cancel(event: InputEvent) -> bool:
	if not emit_cancel_on_back:
		return false
	if not _is_any_action(event, CANCEL_ACTIONS):
		return false
	cancel_pressed.emit()
	return true


func _try_move_focus(direction: int, event: InputEvent) -> bool:
	var actions := DOWN_ACTIONS if direction > 0 else UP_ACTIONS
	if not _is_any_action(event, actions):
		return false
	_move_focus(direction)
	return true


func _try_accept(event: InputEvent) -> bool:
	if not _is_any_action(event, ACCEPT_ACTIONS):
		return false
	_activate_focused_button()
	return true


func _move_focus(direction: int) -> void:
	var viewport := _ui_viewport()
	if viewport == null:
		return
	var focused := viewport.gui_get_focus_owner() as Control
	if focused == null:
		_grab_default_focus()
		return
	var next_focus: Control = focused.find_next_valid_focus() if direction > 0 else focused.find_prev_valid_focus()
	if next_focus == null:
		return
	next_focus.grab_focus()


func _activate_focused_button() -> void:
	var viewport := _ui_viewport()
	if viewport == null:
		return
	var focused := viewport.gui_get_focus_owner()
	if focused is BaseButton:
		(focused as BaseButton).pressed.emit()


func _grab_default_focus() -> void:
	if _default_focus == null:
		return
	_default_focus.grab_focus()


func _release_focus() -> void:
	var viewport := _ui_viewport()
	if viewport == null:
		return
	viewport.gui_release_focus()


func _ui_viewport() -> Viewport:
	if _menu_root != null and is_instance_valid(_menu_root) and _menu_root.is_inside_tree():
		var viewport: Viewport = _menu_root.get_viewport()
		if viewport != null:
			return viewport
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root


func _mark_input_handled() -> void:
	var viewport := _ui_viewport()
	if viewport == null:
		return
	viewport.set_input_as_handled()


func _resolve_control(path: NodePath, label: String) -> Control:
	if path.is_empty():
		push_error("GamepadMenuNavigator: %s is empty." % label)
		return null
	var node := get_node_or_null(path) as Control
	if node != null:
		return node
	push_error("GamepadMenuNavigator: no Control at %s (%s)." % [path, label])
	return null


func _is_any_action(event: InputEvent, action_names: Array[StringName]) -> bool:
	for action_name in action_names:
		if event.is_action(action_name):
			return true
	return false
