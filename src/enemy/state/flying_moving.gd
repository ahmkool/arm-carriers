extends EnemyState

func physics_update(delta: float) -> void:
	var direction := enemy.get_move_direction()
	if direction.length_squared() < 0.0001:
		enemy_state_machine.transition_to("flyingidle")
		return

	enemy.velocity = direction * enemy.speed
	var face := Vector3(direction.x, 0.0, direction.z)
	if face.length_squared() > 0.0001:
		enemy.smooth_rotate_toward(face, delta)
