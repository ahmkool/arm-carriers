extends EnemyState
## Stands behind the shield and fires a short burst from the gun mounted on it, still turning
## (at the enemy's capped turn speed) to keep the shield on the target.

@export var emitter: FireballEmitter
@export var wind_up_seconds := 0.45
@export var burst_count := 3
@export var shot_interval_seconds := 0.28
@export var recover_seconds := 0.5

var _shots_left := 0
var _next_shot_in := 0.0
var _recover_left := 0.0


func enter() -> void:
	super.enter()
	enemy.velocity = Vector3.ZERO
	if enemy.footsteps_particles:
		enemy.footsteps_particles.emitting = false
	_shots_left = burst_count
	_next_shot_in = wind_up_seconds
	_recover_left = recover_seconds


func physics_update(delta: float) -> void:
	if not enemy.is_on_floor():
		enemy_state_machine.transition_to("falling")
		return
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0
	_rotate_toward_target(delta)
	if _shots_left > 0:
		_tick_burst(delta)
		return
	_recover_left -= delta
	if _recover_left > 0.0:
		return
	_finish()


func _tick_burst(delta: float) -> void:
	_next_shot_in -= delta
	if _next_shot_in > 0.0:
		return
	_shots_left -= 1
	_next_shot_in = shot_interval_seconds
	if emitter == null:
		return
	emitter.spawn_fireball()


func _rotate_toward_target(delta: float) -> void:
	if not is_instance_valid(enemy.target_player):
		return
	var to_target := enemy.target_player.global_position - enemy.global_position
	enemy.smooth_rotate_toward(Vector3(to_target.x, 0.0, to_target.z), delta)


func _finish() -> void:
	if enemy.get_move_direction().length_squared() > 0.0001:
		enemy_state_machine.transition_to("running")
		return
	enemy_state_machine.transition_to("idle")
