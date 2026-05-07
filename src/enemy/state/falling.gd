extends EnemyState

func physics_update(delta: float) -> void:
	if enemy.is_on_floor():
		var grounded_direction := enemy.get_target_direction()
		if grounded_direction.length_squared() > 0.0001:
			enemy_state_machine.transition_to("running")
		else:
			enemy_state_machine.transition_to("idle")
		return

	enemy.velocity += enemy.get_gravity() * delta

	var direction := enemy.get_target_direction()
	if direction.length_squared() > 0.0001:
		enemy.velocity.x = direction.x * enemy.speed
		enemy.velocity.z = direction.z * enemy.speed
		enemy.look_at(enemy.global_position + direction, Vector3.UP)
	else:
		enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, enemy.speed)
		enemy.velocity.z = move_toward(enemy.velocity.z, 0.0, enemy.speed)
