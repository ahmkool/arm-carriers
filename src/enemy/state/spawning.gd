extends EnemyState

var _spawn_started := false


func enter() -> void:
	_spawn_started = false
	enemy.velocity = Vector3.ZERO
	if enemy.footsteps_particles:
		enemy.footsteps_particles.emitting = false
	enemy.play_spawn_animation()


func physics_update(delta: float) -> void:
	_apply_gravity_and_zero_horizontal(delta)
	if enemy.is_spawn_animation_playing():
		_spawn_started = true
		return
	if not _spawn_started:
		return
	_transition_after_spawn()


func _apply_gravity_and_zero_horizontal(delta: float) -> void:
	if not enemy.is_on_floor():
		enemy.velocity += enemy.get_gravity() * delta
	enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, enemy.speed)
	enemy.velocity.z = move_toward(enemy.velocity.z, 0.0, enemy.speed)


func _transition_after_spawn() -> void:
	if enemy.is_on_floor():
		enemy_state_machine.transition_to("idle")
		return
	enemy_state_machine.transition_to("falling")
