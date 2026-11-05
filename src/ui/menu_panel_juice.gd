class_name MenuPanelJuice
extends Node
## Shared menu feel: panels pop in, rows appear one after another, buttons and sliders react.
## Extend it and call watch_screen() and watch_controls() for each menu.

const SOUND_WOOD: Array[AudioStream] = [
	preload("res://assets/sounds/wood/WoodStep01.wav"),
	preload("res://assets/sounds/wood/WoodStep05.wav"),
	preload("res://assets/sounds/wood/WoodStep09.wav"),
]

const MAX_DELTA := 1.0 / 30.0
const ACTIVE_SCALE := 1.07
const PRESSED_SCALE := 0.9
const MAX_STAGGER_TOTAL := 0.35
const STAGGER_STEP := 0.04
const FOCUS_SOUND_LOCKOUT := 0.15
const SLIDER_TICK_INTERVAL := 0.06
const PANEL_START_SCALE := 0.8
const PANEL_POP_SECONDS := 0.3


class ButtonJuice:
	var button: BaseButton
	var size_spring := MenuSpring.new(1.0, 320.0, 0.42)
	var tilt_spring := MenuSpring.new(0.0, 240.0, 0.3)
	var hovered := false
	var held := false
	var entrance_delay := 0.0

	func _init(p_button: BaseButton) -> void:
		button = p_button

	func update(delta: float) -> void:
		button.pivot_offset = button.size * 0.5
		if entrance_delay > 0.0:
			entrance_delay -= delta
			button.scale = Vector2.ONE * size_spring.value
			return
		size_spring.target = _target_size()
		size_spring.step(delta)
		tilt_spring.step(delta)
		button.scale = Vector2.ONE * size_spring.value
		button.rotation_degrees = tilt_spring.value

	func _target_size() -> float:
		if held:
			return PRESSED_SCALE
		if hovered or button.has_focus():
			return ACTIVE_SCALE
		return 1.0


var _entries: Array[ButtonJuice] = []
var _focus_sound_unlock_time := 0.0
var _next_slider_tick_time := 0.0
var _panel_tween: Tween


func _process(delta: float) -> void:
	var step_delta := minf(delta, MAX_DELTA)
	for entry in _entries:
		_update_if_visible(entry, step_delta)


func watch_screen(root: Control) -> void:
	root.visibility_changed.connect(_on_screen_visibility_changed.bind(root))


func watch_controls(node: Node) -> void:
	_focus_sound_unlock_time = _now() + FOCUS_SOUND_LOCKOUT
	if node is BaseButton:
		_register_button(node as BaseButton)
	if node is Slider:
		_register_slider(node as Slider)
	for child in node.get_children():
		watch_controls(child)


func watch_navigator(navigator: GamepadMenuNavigator) -> void:
	navigator.cancel_pressed.connect(_on_cancel_pressed)


## Called once a screen is shown, before its panel starts popping in.
func _on_screen_opened(_root: Control) -> void:
	pass


## Called when any watched button is pressed.
func _on_button_activated(_button: BaseButton) -> void:
	_play_tick(1.0)


func _play_tick(pitch: float) -> void:
	_play_sound(SOUND_WOOD.pick_random(), -14.0, pitch * randf_range(0.95, 1.05))


## Parented to the tree root so it survives scene changes and plays while the game is paused.
func _play_sound(stream: AudioStream, volume_db: float, pitch: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.finished.connect(player.queue_free)
	get_tree().root.add_child(player)
	player.play()


func _set_panel_scale(value: float, panel: Control) -> void:
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2.ONE * value


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _update_if_visible(entry: ButtonJuice, delta: float) -> void:
	if not entry.button.is_visible_in_tree():
		return
	entry.update(delta)


func _register_button(button: BaseButton) -> void:
	var entry := ButtonJuice.new(button)
	_entries.append(entry)
	button.mouse_entered.connect(_on_button_hover_changed.bind(entry, true))
	button.mouse_exited.connect(_on_button_hover_changed.bind(entry, false))
	button.focus_entered.connect(_on_button_focused.bind(entry))
	button.button_down.connect(_on_button_held_changed.bind(entry, true))
	button.button_up.connect(_on_button_held_changed.bind(entry, false))
	button.pressed.connect(_on_button_pressed.bind(entry))


func _register_slider(slider: Slider) -> void:
	slider.focus_entered.connect(_on_slider_focused)
	slider.value_changed.connect(_on_slider_value_changed.bind(slider))


func _on_screen_visibility_changed(root: Control) -> void:
	if not root.is_visible_in_tree():
		return
	_focus_sound_unlock_time = _now() + FOCUS_SOUND_LOCKOUT
	_on_screen_opened(root)
	_pop_panel(root.get_node("PanelContainer") as Control)
	_stagger_items(root)


func _pop_panel(panel: Control) -> void:
	if _panel_tween != null:
		_panel_tween.kill()
	panel.modulate.a = 0.0
	_set_panel_scale(PANEL_START_SCALE, panel)
	_panel_tween = create_tween().set_parallel()
	_panel_tween.tween_property(panel, "modulate:a", 1.0, 0.1)
	_panel_tween.tween_method(_set_panel_scale.bind(panel), PANEL_START_SCALE, 1.0, PANEL_POP_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _stagger_items(root: Control) -> void:
	var items := _visible_items(root)
	if items.is_empty():
		return
	var step := minf(STAGGER_STEP, MAX_STAGGER_TOTAL / items.size())
	for index in items.size():
		_reveal_item(items[index], step * index)


func _visible_items(root: Control) -> Array[Control]:
	var items: Array[Control] = []
	var lists := root.get_node("PanelContainer").find_children("*", "VBoxContainer", true, false)
	if lists.is_empty():
		return items
	for child in lists[0].get_children():
		if child is Control and (child as Control).visible:
			items.append(child as Control)
	return items


func _reveal_item(item: Control, delay: float) -> void:
	item.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_interval(delay)
	tween.tween_property(item, "modulate:a", 1.0, 0.1)
	var entry := _entry_for(item)
	if entry == null:
		return
	entry.entrance_delay = delay
	entry.held = false
	entry.hovered = false
	entry.size_spring.value = 0.55
	entry.size_spring.velocity = 0.0
	entry.tilt_spring.value = 0.0
	entry.tilt_spring.velocity = 0.0


func _entry_for(item: Control) -> ButtonJuice:
	for entry in _entries:
		if entry.button == item:
			return entry
	return null


func _on_button_hover_changed(entry: ButtonJuice, hovered: bool) -> void:
	entry.hovered = hovered
	if not hovered or entry.button.has_focus():
		return
	_wiggle(entry)
	_play_tick(1.5)


func _on_button_focused(entry: ButtonJuice) -> void:
	if _now() < _focus_sound_unlock_time:
		return
	_wiggle(entry)
	_play_tick(1.5)


func _on_button_held_changed(entry: ButtonJuice, held: bool) -> void:
	entry.held = held


func _on_button_pressed(entry: ButtonJuice) -> void:
	entry.size_spring.velocity -= 5.0
	_on_button_activated(entry.button)


func _on_slider_focused() -> void:
	if _now() < _focus_sound_unlock_time:
		return
	_play_tick(1.5)


## The tick rises with the value, so turning the SFX slider also previews the new volume.
func _on_slider_value_changed(_value: float, slider: Slider) -> void:
	if not slider.is_visible_in_tree():
		return
	var now := _now()
	if now < _next_slider_tick_time or now < _focus_sound_unlock_time:
		return
	_next_slider_tick_time = now + SLIDER_TICK_INTERVAL
	var ratio := inverse_lerp(slider.min_value, slider.max_value, slider.value)
	_play_tick(lerpf(0.8, 1.7, ratio))


func _on_cancel_pressed() -> void:
	_play_tick(0.8)


func _wiggle(entry: ButtonJuice) -> void:
	entry.tilt_spring.velocity += 34.0 * (1.0 if randf() < 0.5 else -1.0)
