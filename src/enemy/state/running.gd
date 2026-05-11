extends EnemyState

## Higher = faster turn toward move direction (roughly “how many times per second” to ease toward the target).
const ROTATION_SMOOTH_LAMBDA := 12.0

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
	var target_basis := Basis.looking_at(direction.normalized(), Vector3.UP)
	var w := 1.0 - exp(-ROTATION_SMOOTH_LAMBDA * _delta)
	enemy.global_basis = enemy.global_basis.slerp(target_basis, w).orthonormalized()
