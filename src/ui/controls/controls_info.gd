class_name ControlsInfoPanel
extends PanelContainer

const SCROLL_STEP := 48.0
const STICK_SCROLL_SPEED := 480.0
const UP_ACTIONS: Array[StringName] = [&"ui_up", &"p0_up", &"p1_up"]
const DOWN_ACTIONS: Array[StringName] = [&"ui_down", &"p0_down", &"p1_down"]

@onready var _scroll: ScrollContainer = $MarginContainer/ScrollContainer

var _scroll_active := false


func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_scroll.resized.connect(_update_scroll_active)
	var content := _scroll_content()
	if content == null:
		return
	content.minimum_size_changed.connect(_update_scroll_active)
	content.resized.connect(_update_scroll_active)
	call_deferred("_update_scroll_active")


func _on_visibility_changed() -> void:
	set_process(is_visible_in_tree())
	if not is_visible_in_tree():
		return
	call_deferred("_update_scroll_active")


func _process(delta: float) -> void:
	if not _scroll_active:
		return
	var axis := _read_scroll_axis()
	if is_zero_approx(axis):
		return
	_scroll_by(axis * STICK_SCROLL_SPEED * delta)


func process_scroll_input(event: InputEvent) -> bool:
	if not _scroll_active:
		return false
	if not event.is_pressed():
		return false
	if event.is_echo():
		return false
	if _is_any_action(event, UP_ACTIONS):
		_scroll_by(-SCROLL_STEP)
		return true
	if _is_any_action(event, DOWN_ACTIONS):
		_scroll_by(SCROLL_STEP)
		return true
	return false


func _scroll_by(offset: float) -> void:
	var bar := _scroll.get_v_scroll_bar()
	bar.value = clampf(bar.value + offset, bar.min_value, bar.max_value)


func _read_scroll_axis() -> float:
	var axis := Input.get_axis(&"ui_up", &"ui_down")
	if not is_zero_approx(axis):
		return axis
	axis = Input.get_axis(&"p0_up", &"p0_down")
	if not is_zero_approx(axis):
		return axis
	return Input.get_axis(&"p1_up", &"p1_down")


func _update_scroll_active() -> void:
	var content := _scroll_content()
	if content == null:
		_scroll_active = false
		return
	_scroll_active = content.size.y > _scroll.size.y


func _scroll_content() -> Control:
	if _scroll.get_child_count() == 0:
		return null
	return _scroll.get_child(0) as Control


func _is_any_action(event: InputEvent, action_names: Array[StringName]) -> bool:
	for action_name in action_names:
		if event.is_action(action_name):
			return true
	return false
