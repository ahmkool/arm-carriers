extends EnemyState

@export var fireball_emitter: FireballEmitter

const CAST_DURATION_SECONDS := 2.0
const FIREBALL_DELAY_SECONDS := 1.0

var _cast_time_remaining := 0.0
var _fireball_delay_remaining := 0.0

func enter() -> void:
	super.enter()
	_cast_time_remaining = CAST_DURATION_SECONDS
	_fireball_delay_remaining = FIREBALL_DELAY_SECONDS
	enemy.velocity = Vector3.ZERO
	if enemy.footsteps_particles:
		enemy.footsteps_particles.emitting = false
	enemy.play_cast_animation()

func exit() -> void:
	pass

func physics_update(delta: float) -> void:
	if not enemy.is_on_floor():
		enemy_state_machine.transition_to("falling")
		return

	enemy.velocity = Vector3.ZERO
	_rotate_toward_target(delta)
	_tick_fireball_delay(delta)

	_cast_time_remaining -= delta
	if _cast_time_remaining > 0.0:
		return

	_finish_cast()

func _tick_fireball_delay(delta: float) -> void:
	if _fireball_delay_remaining <= 0.0:
		return
	_fireball_delay_remaining -= delta
	if _fireball_delay_remaining > 0.0:
		return
	_emit_fireball()

func _emit_fireball() -> void:
	if fireball_emitter == null:
		return
	fireball_emitter.spawn_fireball()

func _rotate_toward_target(delta: float) -> void:
	if not is_instance_valid(enemy.target_player):
		return
	var to_target := enemy.target_player.global_position - enemy.global_position
	var face := Vector3(to_target.x, 0.0, to_target.z)
	enemy.smooth_rotate_toward(face, delta)

func _finish_cast() -> void:
	if enemy.get_move_direction().length_squared() > 0.0001:
		enemy_state_machine.transition_to("running")
	else:
		enemy_state_machine.transition_to("idle")
