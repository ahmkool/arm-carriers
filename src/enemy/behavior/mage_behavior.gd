class_name MageBehavior
extends EnemyBehavior

enum Mobility {
	MOBILE,
	STATIONARY,
}

@export var mobility: Mobility = Mobility.MOBILE
@export var flee_distance := 3.0
@export var flee_retreat_distance := 4.0
@export var cast_min_distance := 5.0
@export var cast_max_distance := 30.0
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

	if mobility == Mobility.STATIONARY:
		_think_stationary(distance, direction)
		return

	var flee_distance_sq := flee_distance * flee_distance
	var distance_sq := distance * distance

	if distance_sq < flee_distance_sq:
		_set_flee_intent(direction)
		return

	if distance >= cast_min_distance and distance <= cast_max_distance:
		_apply_cast_band_intent(direction)
		return

	if distance > cast_max_distance:
		intent.move_direction = enemy.get_path_direction_to(target.global_position)
		return

	if distance < cast_min_distance:
		_set_flee_intent(direction)
		return


func _think_stationary(distance: float, toward_player: Vector3) -> void:
	intent.face_direction = toward_player
	if distance > cast_max_distance:
		return
	_apply_cast_band_intent(toward_player)


func _apply_cast_band_intent(toward_player: Vector3) -> void:
	intent.face_direction = toward_player
	if _cast_cooldown_remaining > 0.0:
		return
	intent.requested_locomotion = &"casting"
	_cast_cooldown_remaining = cast_cooldown


func _set_flee_intent(toward_player: Vector3) -> void:
	intent.move_direction = enemy.get_flee_path_direction_from(
		enemy.target_player.global_position,
		flee_retreat_distance
	)
	intent.face_direction = toward_player
