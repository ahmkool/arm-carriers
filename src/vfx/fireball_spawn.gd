class_name FireballSpawn
extends Node3D

const FIREBALL_SCENE := preload("res://src/vfx/fireball.tscn")

@onready var _focus: GPUParticles3D = $Focus

var _launch_velocity := Vector3.ZERO

func setup(launch_velocity: Vector3) -> void:
	_launch_velocity = launch_velocity

func _ready() -> void:
	if _launch_velocity.length_squared() < 0.0001:
		queue_free()
		return
	_focus.emitting = true
	await get_tree().create_timer(_focus.lifetime).timeout
	_spawn_fireball()

func _spawn_fireball() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		queue_free()
		return

	var fireball := FIREBALL_SCENE.instantiate() as Fireball
	if fireball == null:
		queue_free()
		return

	scene_root.add_child(fireball)
	fireball.global_position = global_position
	fireball.launch(_launch_velocity)
	queue_free()
