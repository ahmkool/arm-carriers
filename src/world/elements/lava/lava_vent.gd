class_name LavaVent
extends Node3D
## A crack in the ground on a fixed cycle: quiet, then a warning that fills the marked circle,
## then an eruption that burns anything standing inside it, enemies included.
## A dormant vent is a magma pocket instead: it has no cycle and glows a slow, pale pulse until an explosion lands
## within its reach. Then it bursts after a short warning, and its burst sets off the other pockets near it, so one
## shot can run a chain of eruptions through a crowd, or back towards the carriers. It re-arms after a while.

signal burned(body: Node3D)

const ERUPTION_SOUND := preload("res://assets/sounds/explosion/Small Explosion 2_1.wav")
const LIGHT_ENERGY := 5.0
const POCKET_GROUP := &"magma_pockets"
## The column and its light are sized for this radius, and scaled up for bigger vents.
const BASE_RADIUS := 1.45
const POCKET_RIM_COLOR := Color(1.0, 0.78, 0.25)

@export var period_seconds: float = 4.0
@export var warning_seconds: float = 1.3
@export var eruption_seconds: float = 0.9
## Where in its cycle the vent starts, from 0 to 1. Staggering this makes waves across a field.
@export_range(0.0, 1.0) var phase: float = 0.0
## How far an eruption reaches. The rim drawn on the ground has the same radius.
@export var radius: float = 1.45
## Scenery vents out in the lava leave this off.
@export var is_dangerous: bool = true
@export_group("Magma pocket")
@export var dormant := false
## How long a pocket warns between being set off and bursting.
@export var ignite_warning_seconds := 0.55
## A bursting pocket sets off every other pocket whose centre is this close.
@export var chain_reach := 6.6
## How long a pocket stays spent after bursting before it can be set off again.
@export var recharge_seconds := 10.0
@export_group("")

var _elapsed := 0.0
var _erupting := false
## Pockets only: seconds left until it bursts, or negative when it hasn't been set off.
var _ignite_in := -1.0
## Pockets only: seconds since its burst began, or negative when it isn't bursting.
var _burst_time := -1.0
var _spent_for := 0.0
var _pulse := 0.0

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
	if dormant:
		add_to_group(POCKET_GROUP)
		_ground_material.set_shader_parameter("idle_rim_color", POCKET_RIM_COLOR)


func is_erupting() -> bool:
	return _erupting


## Pockets only: whether an explosion would set it off now.
func is_armed() -> bool:
	return dormant and _ignite_in < 0.0 and _burst_time < 0.0 and _spent_for <= 0.0


## Called for every explosion: sets off the armed pockets whose reach it touches.
static func explode_near(tree: SceneTree, at_position: Vector3, blast_radius: float) -> void:
	for node in tree.get_nodes_in_group(POCKET_GROUP):
		var pocket := node as LavaVent
		var offset := pocket.global_position - at_position
		if Vector2(offset.x, offset.z).length() <= pocket.radius + blast_radius * 0.5 and absf(offset.y) < 3.0:
			pocket.ignite()


## Pockets only: bursts after its warning. Does nothing unless armed.
func ignite() -> void:
	if not is_armed():
		return
	_ignite_in = ignite_warning_seconds


func _physics_process(delta: float) -> void:
	if dormant:
		_pocket_process(delta)
		return
	_elapsed = fposmod(_elapsed + delta, period_seconds)
	if _elapsed < warning_seconds:
		_show_warning(_elapsed / warning_seconds)
		return
	if _elapsed < warning_seconds + eruption_seconds:
		_show_eruption((_elapsed - warning_seconds) / eruption_seconds)
		_burn_what_is_inside()
		return
	_show_quiet()


func _pocket_process(delta: float) -> void:
	if _ignite_in >= 0.0:
		_ignite_in -= delta
		_show_warning(1.0 - maxf(_ignite_in, 0.0) / ignite_warning_seconds)
		if _ignite_in < 0.0:
			_burst_time = 0.0
			_chain()
		return
	if _burst_time >= 0.0:
		_burst_time += delta
		if _burst_time < eruption_seconds:
			_show_eruption(_burst_time / eruption_seconds)
			_burn_what_is_inside()
			return
		_burst_time = -1.0
		_spent_for = recharge_seconds
	if _spent_for > 0.0:
		_spent_for -= delta
		_show_quiet()
		return
	_pulse = fposmod(_pulse + delta, 1.6)
	_end_eruption()
	_ground_material.set_shader_parameter("fill", 0.0)
	_ground_material.set_shader_parameter("heat", 0.2 + 0.25 * sin(_pulse / 1.6 * TAU))


func _chain() -> void:
	for node in get_tree().get_nodes_in_group(POCKET_GROUP):
		var other := node as LavaVent
		if other != self and other.global_position.distance_to(global_position) <= chain_reach:
			other.ignite()


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
	var width := lerpf(0.5, 1.0, rise) * fall * radius / BASE_RADIUS
	_column.scale = Vector3(width, rise, width)
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
