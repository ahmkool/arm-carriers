extends EnemyState

@export var fireball_emitter: FireballEmitter

const ROTATION_SMOOTH_LAMBDA := 12.0
const CAST_DURATION_SECONDS := 2.0

var _cast_time_remaining := 0.0

func enter() -> void:
	_cast_time_remaining = CAST_DURATION_SECONDS
	enemy.velocity = Vector3.ZERO
	if enemy.footsteps_particles:
		enemy.footsteps_particles.emitting = false
	_face_target(1.0)
	enemy.play_cast_animation()

func exit() -> void:
	pass

func physics_update(delta: float) -> void:
	if not enemy.is_on_floor():
		enemy_state_machine.transition_to("falling")
		return

	enemy.velocity = Vector3.ZERO
	_face_target(delta)

	_cast_time_remaining -= delta
	if _cast_time_remaining > 0.0:
		return

	_finish_cast()

func _face_target(delta: float) -> void:
	if not is_instance_valid(enemy.target_player):
		return
	var to_target := enemy.target_player.global_position - enemy.global_position
	var face := Vector3(to_target.x, 0.0, to_target.z)
	if face.length_squared() < 0.0001:
		return
	var target_basis := Basis.looking_at(face.normalized(), Vector3.UP)
	var w := 1.0 - exp(-ROTATION_SMOOTH_LAMBDA * delta)
	enemy.global_basis = enemy.global_basis.slerp(target_basis, w).orthonormalized()

func _finish_cast() -> void:
	if enemy.get_move_direction().length_squared() > 0.0001:
		enemy_state_machine.transition_to("running")
	else:
		enemy_state_machine.transition_to("idle")
