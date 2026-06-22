extends Node3D

const SLASH_SCENE := preload("res://src/vfx/enemy/skeleton_boss/axe_stub.tscn")
const SLASH_FLAME_SCENE := preload("res://src/vfx/enemy/skeleton_boss/axe_slash_flame.tscn")

var _phase_controller: BossPhaseController


func _ready() -> void:
	_phase_controller = BossPhaseController.from_enemy(get_parent())


func instantiate_impact() -> void:
	_spawn_impact(_get_slash_scene())


func _get_slash_scene() -> PackedScene:
	if _is_phase_two():
		return SLASH_FLAME_SCENE
	return SLASH_SCENE


func _is_phase_two() -> bool:
	if _phase_controller == null:
		return false
	return _phase_controller.is_phase_at_least(2)


func _get_trail_ground_y() -> float:
	var boss := get_parent() as Node3D
	if boss == null:
		return global_position.y
	return boss.global_position.y + 0.05


func _get_attack_direction() -> Vector3:
	var boss := get_parent() as Node3D
	if boss == null:
		return Vector3.FORWARD
	var forward := -boss.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


func _spawn_impact(scene: PackedScene) -> void:
	var impact := scene.instantiate() as Node3D
	if impact == null:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		impact.queue_free()
		return
	if impact is AxeSlashFlame:
		(impact as AxeSlashFlame).setup(_get_attack_direction(), _get_trail_ground_y())
	scene_root.add_child(impact)
	impact.global_position = global_position
