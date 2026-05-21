extends EnemyState

func physics_update(delta: float) -> void:
	var direction := enemy.get_move_direction()
	if direction.length_squared() > 0.0001:
		enemy_state_machine.transition_to("flyingmoving")
		return

	enemy.velocity = Vector3.ZERO

	var face_direction := enemy.get_face_direction()
	var flat_face := Vector3(face_direction.x, 0.0, face_direction.z)
	if flat_face.length_squared() > 0.0001:
		enemy.smooth_rotate_toward(flat_face, delta)
