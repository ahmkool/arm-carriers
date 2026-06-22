class_name AxeSlashFlame
extends Node3D

const TRAIL_SCENE := preload("res://src/vfx/enemy/skeleton_boss/axe_fire_slash_trail.tscn")

var _direction := Vector3.FORWARD
var _ground_y := 0.0


func setup(direction: Vector3, ground_y: float) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		return
	_direction = flat.normalized()
	_ground_y = ground_y


func _ready() -> void:
	call_deferred("_spawn_trail")


func _spawn_trail() -> void:
	var trail := TRAIL_SCENE.instantiate() as AxeFireSlashTrail
	if trail == null:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		trail.queue_free()
		return
	scene_root.add_child(trail)
	trail.global_position = _get_trail_spawn_position()
	trail.launch(_direction)


func _get_trail_spawn_position() -> Vector3:
	return Vector3(global_position.x, _ground_y, global_position.z)
