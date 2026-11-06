class_name LavaVent
extends Node3D
## A crack in the ground on a fixed cycle: quiet, then a warning that fills the marked circle,
## then an eruption that burns anything standing inside it, enemies included.

signal burned(body: Node3D)

const ERUPTION_SOUND := preload("res://assets/sounds/explosion/Small Explosion 2_1.wav")
const LIGHT_ENERGY := 5.0

@export var period_seconds: float = 4.0
@export var warning_seconds: float = 1.3
@export var eruption_seconds: float = 0.9
## Where in its cycle the vent starts, from 0 to 1. Staggering this makes waves across a field.
@export_range(0.0, 1.0) var phase: float = 0.0
## How far an eruption reaches. The rim drawn on the ground has the same radius.
@export var radius: float = 1.45
## Scenery vents out in the lava leave this off.
@export var is_dangerous: bool = true

var _elapsed := 0.0
var _erupting := false

@onready var _ground: MeshInstance3D = $Ground
@onready var _ground_material: ShaderMaterial = _ground.mesh.surface_get_material(0)
@onready var _column: MeshInstance3D = $Column
@onready var _globs: GPUParticles3D = $Globs
@onready var _light: OmniLight3D = $Light
@onready var _reach: Area3D = $Reach


func _ready() -> void:
	_elapsed = phase * period_seconds
	_ground.scale = Vector3(radius, 1.0, radius)
	_ground.visible = is_dangerous
	_reach.monitoring = is_dangerous
	_column.visible = false
	_light.visible = false
	_globs.emitting = false


func is_erupting() -> bool:
	return _erupting


func _physics_process(delta: float) -> void:
	_elapsed = fposmod(_elapsed + delta, period_seconds)
	if _elapsed < warning_seconds:
		_show_warning(_elapsed / warning_seconds)
		return
	if _elapsed < warning_seconds + eruption_seconds:
		_show_eruption((_elapsed - warning_seconds) / eruption_seconds)
		_burn_what_is_inside()
		return
	_show_quiet()


func _show_warning(progress: float) -> void:
	_end_eruption()
	_ground_material.set_shader_parameter("fill", progress)
	_ground_material.set_shader_parameter("heat", progress * progress)


func _show_quiet() -> void:
	_end_eruption()
	_ground_material.set_shader_parameter("fill", 0.0)
	_ground_material.set_shader_parameter("heat", 0.0)


func _show_eruption(progress: float) -> void:
	if not _erupting:
		_start_eruption()
	var rise := minf(progress / 0.12, 1.0)
	var fall := minf((1.0 - progress) / 0.2, 1.0)
	_column.scale = Vector3(lerpf(0.5, 1.0, rise) * fall, rise, lerpf(0.5, 1.0, rise) * fall)
	_light.light_energy = LIGHT_ENERGY * fall
	_ground_material.set_shader_parameter("fill", 1.0)
	_ground_material.set_shader_parameter("heat", 1.0)


func _start_eruption() -> void:
	_erupting = true
	_column.visible = true
	_light.visible = true
	_globs.emitting = true
	_play_sound()


func _end_eruption() -> void:
	if not _erupting:
		return
	_erupting = false
	_column.visible = false
	_light.visible = false
	_globs.emitting = false


func _burn_what_is_inside() -> void:
	if not is_dangerous:
		return
	for body in _reach.get_overlapping_bodies():
		_burn_if_inside(body)


func _burn_if_inside(body: Node3D) -> void:
	if body is not PlayerLocal and body is not EnemyLocal:
		return
	var offset := body.global_position - global_position
	if Vector2(offset.x, offset.z).length() > radius:
		return
	burned.emit(body)
	Health.apply_damage(body, 9999, global_position)


func _play_sound() -> void:
	if not is_dangerous:
		return
	var sfx := $Sound as AudioStreamPlayer3D
	sfx.stream = ERUPTION_SOUND
	sfx.play()
