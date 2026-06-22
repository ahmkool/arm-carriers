extends Node3D

const STEP_SCENE := preload("res://src/vfx/enemy/skeleton_boss/step.tscn")


func instantiate_step() -> void:
	_spawn_step()


func _spawn_step() -> void:
	var step := STEP_SCENE.instantiate() as Node3D
	if step == null:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		step.queue_free()
		return
	scene_root.add_child(step)
	step.global_position = global_position
