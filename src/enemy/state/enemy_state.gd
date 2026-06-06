class_name EnemyState
extends Node

var enemy: EnemyLocal
var enemy_state_machine: EnemyStateMachine

func enter() -> void:
	_set_visual_visible(true)


func _set_visual_visible(is_visible: bool) -> void:
	if enemy == null:
		return
	var visual := _find_visual_root()
	if visual == null:
		return
	visual.visible = is_visible


func _find_visual_root() -> Node3D:
	for child in enemy.get_children():
		if not child is Node3D:
			continue
		if child is Area3D:
			continue
		if child is NavigationAgent3D:
			continue
		if child is GPUParticles3D:
			continue
		if child.name == "VFX":
			continue
		return child as Node3D
	return null

func exit() -> void:
	pass

func update(_delta: float) -> void:
	pass

func physics_update(_delta: float) -> void:
	pass
