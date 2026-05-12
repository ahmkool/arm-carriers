extends PlayerState

const DASH_DURATION_SEC := 0.07
const DASH_SPEED := 30.0
const GHOST_SCENE := preload("res://src/vfx/ghost.tscn")
const DASH_PARTICLES_SCENE := preload("res://src/vfx/dash_particles.tscn")
const DASH_GHOST_COUNT := 5

var _dash_time_remaining := 0.0
var _dash_direction := Vector3.ZERO
## How many trailing ghosts have spawned (first ghost is spawned in `enter`).
var _dash_late_ghost_index := 0


func enter() -> void:
	CameraFeedback.add_trauma_dash()
	_dash_time_remaining = DASH_DURATION_SEC
	_dash_late_ghost_index = 0
	_dash_direction = _get_dash_direction()
	player.velocity.y = 0.0
	player.velocity.x = _dash_direction.x * DASH_SPEED
	player.velocity.z = _dash_direction.z * DASH_SPEED
	_spawn_dash_particles()
	_spawn_dash_ghost()


func exit() -> void:
	_dash_time_remaining = 0.0
	_dash_late_ghost_index = 0


func physics_update(delta: float) -> void:
	if not player.is_on_floor():
		player_state_machine.transition_to("falling")
		return

	var dash_elapsed := DASH_DURATION_SEC - _dash_time_remaining
	_dash_time_remaining = maxf(0.0, _dash_time_remaining - delta)
	player.velocity.x = _dash_direction.x * DASH_SPEED
	player.velocity.z = _dash_direction.z * DASH_SPEED
	if _dash_direction.length_squared() > 0.0001:
		player.look_at(player.global_position + _dash_direction, Vector3.UP)

	while _dash_late_ghost_index < DASH_GHOST_COUNT - 1:
		var threshold := _late_ghost_spawn_fraction(_dash_late_ghost_index) * DASH_DURATION_SEC
		if dash_elapsed < threshold:
			break
		_spawn_dash_ghost()
		_dash_late_ghost_index += 1

	if _dash_time_remaining > 0.0:
		return

	var direction := player.get_move_direction()
	if direction.length_squared() > 0.0001:
		player_state_machine.transition_to("running")
		return
	player_state_machine.transition_to("idle")


func _get_dash_direction() -> Vector3:
	var direction := player.get_move_direction()
	if direction.length_squared() > 0.0001:
		return direction
	var facing_forward := -player.global_transform.basis.z
	facing_forward.y = 0.0
	if facing_forward.length_squared() > 0.0001:
		return facing_forward.normalized()
	return Vector3.FORWARD


func _late_ghost_spawn_fraction(late_index: int) -> float:
	var late_count := DASH_GHOST_COUNT - 1
	if late_count <= 0:
		return 1.0
	var span := maxi(late_count - 1, 1)
	return lerpf(0.62, 0.98, float(late_index) / float(span))


func _spawn_dash_particles() -> void:
	var particles := DASH_PARTICLES_SCENE.instantiate() as GPUParticles3D
	player.get_tree().current_scene.add_child(particles)
	particles.global_transform = player.global_transform
	particles.emitting = true


func _spawn_dash_ghost() -> void:
	var ghost := GHOST_SCENE.instantiate() as Node3D
	player.get_tree().current_scene.add_child(ghost)
	ghost.global_transform = player.global_transform
