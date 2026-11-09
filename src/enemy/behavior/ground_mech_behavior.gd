class_name GroundMechBehavior
extends EnemyBehavior
## The Combat Mech on foot: holds a firing distance from the nearer carrier, walking in when they are far and
## backing off when they close in, and stops to attack. The gunner fires the winged mech's gun bursts
## (`src/enemy/mech/mech_shooting.gd`); the grenadier lobs grenades (`mech_lobbing.gd`). `attack_state` picks which.
## Walking and standing states are in `src/enemy/ground_mech/`.

## The state that attacks: &"shooting" for the gunner, &"lobbing" for the grenadier.
@export var attack_state := &"shooting"

## Walks in when the target is further than this, flat.
@export var approach_distance := 9.0
## Backs away when the target is closer than this, flat.
@export var retreat_distance := 4.5
## How far a retreat aims to go, so it doesn't stop and start.
@export var retreat_step := 4.0
## The gun only fires at a target within this flat distance.
@export var shoot_max_distance := 12.0
## Seconds after waking before the first burst.
@export var first_shot_delay := 1.0
@export var shot_cooldown_min := 1.8
@export var shot_cooldown_max := 3.0

var _cooldown_remaining := 0.0
var _was_offensive := false


func _think(delta: float) -> void:
	if enemy == null or _is_busy():
		return
	if not enemy.is_offensive:
		_was_offensive = false
		return
	_on_wake_up()
	enemy.update_target_player()
	if not is_instance_valid(enemy.target_player):
		return
	_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
	var to_target := enemy.target_player.global_position - enemy.global_position
	var distance := Vector2(to_target.x, to_target.z).length()
	intent.face_direction = Vector3(to_target.x, 0.0, to_target.z)
	if distance > approach_distance:
		var path := enemy.get_path_direction_to(enemy.target_player.global_position)
		# Stuck at the end of its path (on an island the carriers aren't on) but in range: fight from there.
		if path.length_squared() > 0.0001 or distance > shoot_max_distance:
			intent.move_direction = path
			return
	if distance < retreat_distance:
		intent.move_direction = enemy.get_flee_path_direction_from(enemy.target_player.global_position, retreat_step)
		return
	_try_shoot(distance)


func _is_busy() -> bool:
	var machine := enemy.enemy_state_machine
	if machine == null:
		return true
	return machine.is_in_state("dead") or machine.is_in_state(String(attack_state))


func _on_wake_up() -> void:
	if _was_offensive:
		return
	_was_offensive = true
	_cooldown_remaining = first_shot_delay


func _try_shoot(distance: float) -> void:
	if _cooldown_remaining > 0.0:
		return
	if distance > shoot_max_distance:
		return
	_cooldown_remaining = randf_range(shot_cooldown_min, shot_cooldown_max)
	intent.requested_locomotion = attack_state
