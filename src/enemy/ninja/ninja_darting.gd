extends EnemyState
## A quick run straight to the spot `NinjaPeekerBehavior` picks, at full speed from the first frame and
## stopping dead on it, so a peek out from cover is short and sharp. Ignores the navmesh: the spots are
## a couple of metres apart on open roof.

const DART_SPEED := 6.0


func enter() -> void:
	super.enter()
	if enemy.footsteps_particles:
		enemy.footsteps_particles.emitting = true


func exit() -> void:
	if enemy.footsteps_particles:
		enemy.footsteps_particles.emitting = false


func physics_update(delta: float) -> void:
	if not enemy.is_on_floor():
		enemy_state_machine.transition_to("falling")
		return
	var behavior := enemy.behavior as NinjaPeekerBehavior
	if behavior == null:
		enemy_state_machine.transition_to("idle")
		return
	var offset := behavior.get_dart_target() - enemy.global_position
	offset.y = 0.0
	var distance := offset.length()
	var step := DART_SPEED * delta
	if distance <= step:
		_stop_on(behavior.get_dart_target())
		return
	var direction := offset / distance
	enemy.velocity.x = direction.x * DART_SPEED
	enemy.velocity.z = direction.z * DART_SPEED
	enemy.smooth_rotate_toward(direction, delta)


## Lands exactly on the spot, already stopped, so the idle state has nothing to brake.
func _stop_on(target: Vector3) -> void:
	enemy.global_position = Vector3(target.x, enemy.global_position.y, target.z)
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0
	enemy_state_machine.transition_to("idle")
