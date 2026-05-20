class_name MageBehavior
extends EnemyBehavior

@export var flee_distance := 3.0
@export var cast_min_distance := 5.0
@export var cast_max_distance := 12.0
@export var cast_cooldown := 2.5

var _cast_cooldown_remaining := 0.0

func _think(delta: float) -> void:
	if enemy == null or not enemy.is_offensive:
		return

	if enemy.enemy_state_machine != null and enemy.enemy_state_machine.is_in_state("casting"):
		return

	_cast_cooldown_remaining = maxf(_cast_cooldown_remaining - delta, 0.0)

	if not is_instance_valid(enemy.target_player):
		enemy.update_target_player()
	if is_instance_valid(enemy.target_player) and enemy.target_player.is_dead:
		enemy.update_target_player()
	if not is_instance_valid(enemy.target_player):
		return

	var target := enemy.target_player
	var to_target := target.global_position - enemy.global_position
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var distance := flat.length()
	if distance < 0.0001:
		return

	var direction := flat / distance
	var flee_distance_sq := flee_distance * flee_distance
	var distance_sq := distance * distance

	if distance_sq < flee_distance_sq:
		intent.move_direction = -direction
		intent.face_direction = -direction
		return

	if distance >= cast_min_distance and distance <= cast_max_distance and _cast_cooldown_remaining <= 0.0:
		intent.requested_locomotion = &"casting"
		intent.face_direction = direction
		_cast_cooldown_remaining = cast_cooldown
		return

	if distance > cast_max_distance:
		intent.move_direction = enemy.get_path_direction_to(target.global_position)
		return

	if distance < cast_min_distance:
		intent.move_direction = -direction
		intent.face_direction = -direction
