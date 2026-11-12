class_name FireballSpawn
extends Node3D

const FIREBALL_SCENE := preload("res://src/vfx/fireball.tscn")

## The projectile launched once the charge-up ends. It must use fireball.gd.
@export var projectile_scene: PackedScene = FIREBALL_SCENE

@onready var _focus: GPUParticles3D = $Focus
@onready var _burst: GPUParticles3D = $GPUParticles3D
@onready var _sfx: AudioStreamPlayer3D = $AudioStreamPlayer3D

var _launch_velocity := Vector3.ZERO
var _damage := -1

## `damage` -1 keeps the projectile scene's own damage.
func setup(launch_velocity: Vector3, damage := -1) -> void:
	_launch_velocity = launch_velocity
	_damage = damage

func _ready() -> void:
	add_to_group(Checkpoint.ENEMY_PROJECTILE_GROUP)
	if _launch_velocity.length_squared() < 0.0001:
		queue_free()
		return
	_focus.emitting = true
	_sfx.play()
	await get_tree().create_timer(_focus.lifetime).timeout
	_spawn_fireball()

func _spawn_fireball() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		queue_free()
		return

	_play_spawn_burst()

	var fireball := projectile_scene.instantiate() as Fireball
	if fireball == null:
		_schedule_cleanup()
		return

	if _damage >= 0:
		fireball.damage = _damage
	scene_root.add_child(fireball)
	fireball.global_position = global_position
	fireball.launch(_launch_velocity)
	_schedule_cleanup()


func _play_spawn_burst() -> void:
	_burst.emitting = true


func _schedule_cleanup() -> void:
	var sfx_remaining := maxf(0.0, _estimate_sfx_duration() - _focus.lifetime)
	var delay := maxf(_burst.lifetime + 0.15, sfx_remaining)
	get_tree().create_timer(delay).timeout.connect(queue_free, CONNECT_ONE_SHOT)


func _estimate_sfx_duration() -> float:
	if _sfx.stream == null:
		return 0.0
	return _sfx.stream.get_length() / _sfx.pitch_scale
