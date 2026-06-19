class_name SkeletonBossBehavior
extends EnemyBehavior

@export var attack_min_distance := 1.2
@export var attack_max_distance := 3.5
@export var stab_preferred_distance := 2.0
@export var chase_max_distance := 14.0
@export var attack_cooldown := 1.5

var _attack_cooldown_remaining := 0.0


func _think(delta: float) -> void:
	if enemy == null or not enemy.is_offensive:
		return
	if _is_attacking():
		return

	_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - delta, 0.0)

	if not _ensure_target():
		return

	var flat_to_target := _get_flat_to_target()
	if flat_to_target.length_squared() < 0.0001:
		return

	var distance := flat_to_target.length()
	var direction := flat_to_target / distance

	if _can_request_attack(distance):
		_request_attack(distance, direction)
		return

	if distance > attack_max_distance and distance <= chase_max_distance:
		intent.move_direction = enemy.get_path_direction_to(enemy.target_player.global_position)
		intent.face_direction = direction
		return

	if distance <= chase_max_distance:
		intent.face_direction = direction


func _is_attacking() -> bool:
	if enemy.enemy_state_machine == null:
		return false
	return enemy.enemy_state_machine.is_in_state("attacking")


func _ensure_target() -> bool:
	if not is_instance_valid(enemy.target_player):
		enemy.update_target_player()
	if is_instance_valid(enemy.target_player) and enemy.target_player.is_dead:
		enemy.update_target_player()
	return is_instance_valid(enemy.target_player)


func _get_flat_to_target() -> Vector3:
	var to_target := enemy.target_player.global_position - enemy.global_position
	return Vector3(to_target.x, 0.0, to_target.z)


func _can_request_attack(distance: float) -> bool:
	if _attack_cooldown_remaining > 0.0:
		return false
	if distance < attack_min_distance:
		return false
	if distance > attack_max_distance:
		return false
	return true


func _request_attack(distance: float, face_direction: Vector3) -> void:
	intent.face_direction = face_direction
	intent.requested_attack = _pick_attack(distance)
	intent.requested_locomotion = &"attacking"
	_attack_cooldown_remaining = attack_cooldown


func _pick_attack(distance: float) -> StringName:
	if distance <= stab_preferred_distance:
		return &"stab"
	return &"slash"
