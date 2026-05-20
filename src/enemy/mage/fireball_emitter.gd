class_name FireballEmitter
extends Marker3D

const FIREBALL_SCENE := preload("res://src/vfx/fireball.tscn")

@export var speed := 8.0

func spawn_fireball() -> void:
	var direction := _get_launch_direction()
	if direction.length_squared() < 0.0001:
		return

	var fireball := FIREBALL_SCENE.instantiate() as Fireball
	if fireball == null:
		return

	var scene_root := get_tree().current_scene
	if scene_root == null:
		fireball.queue_free()
		return

	scene_root.add_child(fireball)
	fireball.global_position = global_position
	fireball.launch(direction * speed)

func _get_launch_direction() -> Vector3:
	var enemy := get_parent() as EnemyLocal
	if enemy != null and is_instance_valid(enemy.target_player):
		var to_target := enemy.target_player.global_position - global_position
		var flat := Vector3(to_target.x, 0.0, to_target.z)
		if flat.length_squared() > 0.0001:
			return flat.normalized()

	var forward := Vector3(-global_basis.z.x, 0.0, -global_basis.z.z)
	if forward.length_squared() > 0.0001:
		return forward.normalized()
	return Vector3.ZERO
