extends EnemyState

@export var hit_duration_seconds := 0.45

var _time_remaining := 0.0


func enter() -> void:
	super.enter()
	_begin_hit_reaction()


func refresh_hit() -> void:
	_begin_hit_reaction()


func _begin_hit_reaction() -> void:
	_time_remaining = hit_duration_seconds
	enemy.velocity = Vector3.ZERO
	if enemy.footsteps_particles:
		enemy.footsteps_particles.emitting = false
	enemy.play_hit_animation()


func physics_update(delta: float) -> void:
	if not enemy.is_on_floor():
		enemy_state_machine.transition_to("falling")
		return
	enemy.velocity = Vector3.ZERO
	_time_remaining -= delta
	if _time_remaining > 0.0:
		return
	enemy.resume_state_after_hit()
