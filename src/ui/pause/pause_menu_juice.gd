class_name PauseMenuJuice
extends MenuPanelJuice
## Pause feel: blurs the game, muffles the music, slams the title in and animates the menu away on resume.

const DIM_SHADER := preload("res://src/ui/pause/pause_dim.gdshader")
const MUSIC_BUS := &"Music"
const MUSIC_CUTOFF_OPEN_HZ := 800.0
const MUSIC_CUTOFF_CLOSED_HZ := 20500.0
const OPEN_SECONDS := 0.22
const CLOSE_SECONDS := 0.14
const PANEL_CLOSE_SCALE := 0.86
const TITLE_START_SCALE := 1.7
const TITLE_PULSE := 0.025
const TITLE_PULSE_SPEED := 2.6

var _dim_material: ShaderMaterial
var _dim_strength := 0.0
var _music_filter: AudioEffectLowPassFilter
var _state_tween: Tween
var _close_tween: Tween
var _is_open := false
var _time := 0.0
var _title_spring := MenuSpring.new(1.0, 300.0, 0.4)

@onready var _menu_root: Control = $"../Layer/MenuRoot"
@onready var _title: Control = $"../Layer/MenuRoot/PauseMainRoot/PanelContainer/MarginContainer/VBoxContainer/TitleLabel"
@onready var _main_root: Control = $"../Layer/MenuRoot/PauseMainRoot"
@onready var _screens: Array[Control] = [
	_main_root,
	$"../Layer/MenuRoot/PauseOptionsRoot" as Control,
	$"../Layer/MenuRoot/PauseControlsRoot" as Control,
	$"../Layer/MenuRoot/PauseCheckpointsRoot" as Control,
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for root in _screens:
		watch_screen(root)
		watch_controls(root)
	watch_navigator($"../GamepadMenuNavigator" as GamepadMenuNavigator)
	_build_dim_material()
	_add_music_filter()
	_keep_music_playing_while_paused.call_deferred()


func _exit_tree() -> void:
	_remove_music_filter()


func _process(delta: float) -> void:
	super(delta)
	if not _title.is_visible_in_tree():
		return
	var step_delta := minf(delta, MAX_DELTA)
	_time += step_delta
	_title_spring.step(step_delta)
	_title.pivot_offset = _title.size * 0.5
	_title.scale = Vector2.ONE * (_title_spring.value + sin(_time * TITLE_PULSE_SPEED) * TITLE_PULSE)


func open() -> void:
	_kill_close_tween()
	_is_open = true
	_menu_root.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_INHERITED
	_menu_root.visible = true
	_animate_state(1.0, MUSIC_CUTOFF_OPEN_HZ, OPEN_SECONDS)
	_play_sound(SOUND_WOOD[0], -7.0, 0.55)


## Resuming is immediate; this only plays the menu's exit over the running game.
func close() -> void:
	if not _is_open:
		_menu_root.visible = false
		return
	_is_open = false
	_menu_root.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_DISABLED
	_animate_state(0.0, MUSIC_CUTOFF_CLOSED_HZ, CLOSE_SECONDS)
	_play_sound(SOUND_WOOD[1], -10.0, 0.85)
	_shrink_open_panel()


func _on_screen_opened(root: Control) -> void:
	if root != _main_root:
		return
	_title_spring.value = TITLE_START_SCALE
	_title_spring.velocity = 0.0


func _build_dim_material() -> void:
	_dim_material = ShaderMaterial.new()
	_dim_material.shader = DIM_SHADER
	($"../Layer/MenuRoot/DimOverlay" as ColorRect).material = _dim_material


func _animate_state(dim_strength: float, music_cutoff: float, seconds: float) -> void:
	if _state_tween != null:
		_state_tween.kill()
	_state_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE)
	_state_tween.tween_method(_set_dim_strength, _dim_strength, dim_strength, seconds)
	if _music_filter == null:
		return
	_state_tween.tween_property(_music_filter, "cutoff_hz", music_cutoff, seconds)


func _set_dim_strength(value: float) -> void:
	_dim_strength = value
	_dim_material.set_shader_parameter(&"strength", value)


func _shrink_open_panel() -> void:
	if _panel_tween != null:
		_panel_tween.kill()
	_close_tween = create_tween().set_parallel()
	_close_tween.finished.connect(_on_close_finished)
	var panel := _open_panel()
	if panel == null:
		_close_tween.tween_interval(CLOSE_SECONDS)
		return
	_close_tween.tween_property(panel, "modulate:a", 0.0, CLOSE_SECONDS)
	_close_tween.tween_method(_set_panel_scale.bind(panel), panel.scale.x, PANEL_CLOSE_SCALE, CLOSE_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)


func _open_panel() -> Control:
	for root in _screens:
		if root.visible:
			return root.get_node("PanelContainer") as Control
	return null


func _kill_close_tween() -> void:
	if _close_tween == null:
		return
	_close_tween.kill()
	_close_tween = null


func _on_close_finished() -> void:
	_menu_root.visible = false


## Music on the Music bus would otherwise stop with the paused tree, and the muffling could not be heard.
func _keep_music_playing_while_paused() -> void:
	for player: AudioStreamPlayer in get_tree().current_scene.find_children("*", "AudioStreamPlayer", true, false):
		_keep_playing_if_music(player)


func _keep_playing_if_music(player: AudioStreamPlayer) -> void:
	if player.bus != MUSIC_BUS:
		return
	player.process_mode = Node.PROCESS_MODE_ALWAYS


func _add_music_filter() -> void:
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	if bus < 0:
		return
	_music_filter = AudioEffectLowPassFilter.new()
	_music_filter.cutoff_hz = MUSIC_CUTOFF_CLOSED_HZ
	AudioServer.add_bus_effect(bus, _music_filter)


func _remove_music_filter() -> void:
	var bus := AudioServer.get_bus_index(MUSIC_BUS)
	if bus < 0 or _music_filter == null:
		return
	for index in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, index) == _music_filter:
			AudioServer.remove_bus_effect(bus, index)
			return
