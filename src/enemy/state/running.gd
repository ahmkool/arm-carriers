extends EnemyState

func enter() -> void:
	if enemy.footsteps_particles:
		enemy.footsteps_particles.emitting = true

func exit() -> void:
	if enemy.footsteps_particles:
		enemy.footsteps_particles.emitting = false

func physics_update(_delta: float) -> void:
	if not enemy.is_on_floor():
		enemy_state_machine.transition_to("falling")
		return

	var direction := enemy.get_target_direction()
	if direction.length_squared() < 0.0001:
		enemy_state_machine.transition_to("idle")
		return

	enemy.velocity.x = direction.x * enemy.speed
	enemy.velocity.z = direction.z * enemy.speed
	enemy.look_at(enemy.global_position + direction, Vector3.UP)
