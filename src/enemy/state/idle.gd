extends EnemyState

func physics_update(_delta: float) -> void:
	if not enemy.is_on_floor():
		enemy_state_machine.transition_to("falling")
		return

	var direction: Vector3 = enemy.get_move_direction()
	if direction.length_squared() > 0.0001:
		enemy_state_machine.transition_to("running")
		return

	enemy.velocity.x = move_toward(enemy.velocity.x, 0.0, enemy.speed)
	enemy.velocity.z = move_toward(enemy.velocity.z, 0.0, enemy.speed)

	var face_direction: Vector3 = enemy.get_face_direction()
	if face_direction.length_squared() > 0.0001:
		enemy.smooth_rotate_toward(face_direction, _delta)
