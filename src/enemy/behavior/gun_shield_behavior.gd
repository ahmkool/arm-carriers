class_name GunShieldBehavior
extends EnemyBehavior
## A shield carrier with a gun on his shield: he keeps the shield turned toward the nearest carrier,
## holds a firing band, and shoots bursts over the rim. He walks forward when the carriers are far and
## backs off, shield first, when they crowd him.

@export var min_distance := 5.0
@export var max_distance := 13.0
@export var fire_cooldown := 2.2
@export var retreat_distance := 3.0

var _fire_cooldown_remaining := 1.0


func _think(delta: float) -> void:
	_fire_cooldown_remaining = maxf(_fire_cooldown_remaining - delta, 0.0)
	if not _can_act():
		return
	var to_target := enemy.target_player.global_position - enemy.global_position
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var distance := flat.length()
	if distance < 0.0001:
		return
	var toward_player := flat / distance
	intent.face_direction = toward_player
	if distance > max_distance:
		intent.move_direction = enemy.get_path_direction_to(enemy.target_player.global_position)
		return
	if distance < min_distance:
		intent.move_direction = enemy.get_flee_path_direction_from(enemy.target_player.global_position, retreat_distance)
		return
	_request_fire()


func _can_act() -> bool:
	if enemy == null or not enemy.is_offensive:
		return false
	if enemy.enemy_state_machine != null and enemy.enemy_state_machine.is_in_state("shieldfiring"):
		return false
	_refresh_target()
	return is_instance_valid(enemy.target_player)


func _refresh_target() -> void:
	if not is_instance_valid(enemy.target_player) or enemy.target_player.is_dead:
		enemy.update_target_player()


func _request_fire() -> void:
	if _fire_cooldown_remaining > 0.0:
		return
	intent.requested_locomotion = &"shieldfiring"
	_fire_cooldown_remaining = fire_cooldown
