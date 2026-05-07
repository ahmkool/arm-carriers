extends EnemyState

func physics_update(_delta: float) -> void:
	if not enemy.is_on_floor():
		enemy_state_machine.transition_to("falling")
		return

	var direction := enemy.get_target_direction()
	if direction.length_squared() > 0.0001:
		enemy_state_machine.transition_to("running")
		return

	enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, enemy.speed)
	enemy.velocity.z = move_toward(enemy.velocity.z, 0.0, enemy.speed)
