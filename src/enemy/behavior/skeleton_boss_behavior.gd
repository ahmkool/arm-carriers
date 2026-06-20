class_name SkeletonBossBehavior
extends EnemyBehavior

@export var attack_min_distance := 1.2
@export var attack_max_distance := 3.5
@export var chase_max_distance := 14.0
@export var attack_cooldown := 1.5
@export var target_refresh_interval := 0.5

var _attack_cooldown_remaining := 0.0
var _target_refresh_remaining := 0.0


func _think(delta: float) -> void:
	if enemy == null or not enemy.is_offensive:
		return

	_tick_target_refresh(delta)

	if _is_attacking():
		return

	_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - delta, 0.0)

	if not _has_valid_target():
		return

	var flat_to_target := _get_flat_to_target()
	if flat_to_target.length_squared() < 0.0001:
		return

	var distance := flat_to_target.length()
	var direction := flat_to_target / distance

	if _can_request_attack(distance):
		_request_attack(direction)
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


func _tick_target_refresh(delta: float) -> void:
	if _needs_immediate_target_refresh():
		_refresh_target()
		return

	_target_refresh_remaining -= delta
	if _target_refresh_remaining > 0.0:
		return
	_refresh_target()


func _refresh_target() -> void:
	enemy.update_target_player()
	_target_refresh_remaining = target_refresh_interval


func _needs_immediate_target_refresh() -> bool:
	if not is_instance_valid(enemy.target_player):
		return true
	if enemy.target_player.is_dead:
		return true
	return false


func _has_valid_target() -> bool:
	if not is_instance_valid(enemy.target_player):
		return false
	return not enemy.target_player.is_dead


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


func _request_attack(face_direction: Vector3) -> void:
	intent.face_direction = face_direction
	intent.requested_attack = _pick_attack()
	intent.requested_locomotion = &"attacking"
	_attack_cooldown_remaining = attack_cooldown


func _pick_attack() -> StringName:
	if randi() % 2 == 0:
		return &"slash"
	return &"stab"
