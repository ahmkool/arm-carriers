class_name BossAxeFireVisual
extends Node

const ENRAGE_BURST_SCENE := preload("res://src/vfx/boss_axe_enrage_burst.tscn")
const BLADE_SURFACE_INDEX := 1
const FIRE_INTENSITY_PARAM := &"fire_intensity"
const FADE_IN_DURATION_SEC := 0.6
const PULSE_MIN := 0.8
const PULSE_MAX := 1.0

@export var fade_in_duration_sec := FADE_IN_DURATION_SEC
@export var pulse_speed := 2.5
@export var light_energy_at_full := 1.1
@export var light_range := 2.5

@onready var _blade_light: OmniLight3D = $BladeLight

var _axe_mesh: MeshInstance3D
var _blade_material: ShaderMaterial
var _fade_tween: Tween
var _pulsing := false
var _pulse_time := 0.0


func _ready() -> void:
	_bind_axe_mesh()
	_configure_blade_light()
	_reset_blade_intensity()


func start_enrage() -> void:
	_spawn_enrage_burst()
	if not _ensure_blade_material():
		return
	_kill_fade_tween()
	_pulsing = false
	_pulse_time = 0.0
	set_process(false)
	_set_fire_intensity(0.0)
	_start_fade_in()


func stop_enrage() -> void:
	_kill_fade_tween()
	_pulsing = false
	_pulse_time = 0.0
	set_process(false)
	_reset_blade_intensity()


func _process(delta: float) -> void:
	if not _pulsing:
		return
	if _blade_material == null:
		return
	_pulse_time += delta
	var midpoint := (PULSE_MIN + PULSE_MAX) * 0.5
	var amplitude := (PULSE_MAX - PULSE_MIN) * 0.5
	var pulse := midpoint + amplitude * sin(_pulse_time * pulse_speed)
	_set_fire_intensity(pulse)


func _spawn_enrage_burst() -> void:
	var burst := ENRAGE_BURST_SCENE.instantiate() as Node3D
	if burst == null:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		burst.queue_free()
		return
	scene_root.add_child(burst)
	burst.global_position = _get_burst_spawn_position()


func _get_burst_spawn_position() -> Vector3:
	if _blade_light != null:
		return _blade_light.global_position
	if _axe_mesh == null:
		_bind_axe_mesh()
	if _axe_mesh != null:
		return _axe_mesh.global_position
	return Vector3.ZERO


func _bind_axe_mesh() -> void:
	_axe_mesh = get_parent() as MeshInstance3D


func _configure_blade_light() -> void:
	if _blade_light == null:
		return
	_blade_light.omni_range = light_range
	_blade_light.shadow_enabled = false
	_set_blade_light_intensity(0.0)


func _ensure_blade_material() -> bool:
	if _blade_material != null:
		return true
	if _axe_mesh == null:
		_bind_axe_mesh()
	if _axe_mesh == null:
		return false
	var material := _axe_mesh.get_surface_override_material(BLADE_SURFACE_INDEX)
	if material == null:
		return false
	if material is ShaderMaterial:
		_blade_material = material.duplicate() as ShaderMaterial
		_axe_mesh.set_surface_override_material(BLADE_SURFACE_INDEX, _blade_material)
		return true
	return false


func _reset_blade_intensity() -> void:
	if not _ensure_blade_material():
		return
	_set_fire_intensity(0.0)


func _set_fire_intensity(value: float) -> void:
	if _blade_material != null:
		_blade_material.set_shader_parameter(FIRE_INTENSITY_PARAM, value)
	_set_blade_light_intensity(value)


func _set_blade_light_intensity(intensity: float) -> void:
	if _blade_light == null:
		return
	if intensity <= 0.001:
		_blade_light.visible = false
		_blade_light.light_energy = 0.0
		return
	_blade_light.visible = true
	_blade_light.light_energy = light_energy_at_full * intensity


func _start_fade_in() -> void:
	_fade_tween = create_tween()
	_fade_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_fade_tween.tween_method(_set_fire_intensity, 0.0, 1.0, fade_in_duration_sec)
	_fade_tween.finished.connect(_on_fade_in_finished, CONNECT_ONE_SHOT)


func _on_fade_in_finished() -> void:
	_fade_tween = null
	_pulsing = true
	_pulse_time = 0.0
	set_process(true)


func _kill_fade_tween() -> void:
	if _fade_tween == null:
		return
	_fade_tween.kill()
	_fade_tween = null
