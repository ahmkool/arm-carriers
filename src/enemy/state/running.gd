extends EnemyState

func enter() -> void:
	super.enter()
	if enemy.footsteps_particles:
		enemy.footsteps_particles.emitting = true

func exit() -> void:
	if enemy.footsteps_particles:
		enemy.footsteps_particles.emitting = false

func physics_update(_delta: float) -> void:
	if not enemy.is_on_floor():
		enemy_state_machine.transition_to("falling")
		return

	var direction: Vector3 = enemy.get_move_direction()
	if direction.length_squared() < 0.0001:
		enemy_state_machine.transition_to("idle")
		return

	enemy.velocity.x = direction.x * enemy.speed
	enemy.velocity.z = direction.z * enemy.speed
	var face_direction: Vector3 = enemy.get_face_direction()
	if face_direction.length_squared() < 0.0001:
		face_direction = direction
	enemy.smooth_rotate_toward(face_direction, _delta)
