extends EnemyState
## One of the Shuriken Master's gestures, standing still: Launching (KayKit `Throw`, letting a big star fly) or
## Pulling (KayKit `Interact`, calling one home). It plays `oneshot_request` on the animation tree, calls
## `behavior_method` on `ShurikenMasterBehavior` at `release_sec`, and goes back to idle at `end_sec`.

@export var oneshot_request: StringName = &"parameters/OneShot 2/request"
@export var behavior_method: StringName = &"release_launch"
@export var release_sec := 0.45
@export var end_sec := 0.9

var _time := 0.0
var _released := false


func enter() -> void:
	super.enter()
	_time = 0.0
	_released = false
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0
	if enemy.footsteps_particles:
		enemy.footsteps_particles.emitting = false
	if enemy.animation_tree != null:
		enemy.animation_tree.set(oneshot_request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func physics_update(delta: float) -> void:
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0
	var face := enemy.get_face_direction()
	if face.length_squared() > 0.0001:
		enemy.smooth_rotate_toward(face, delta)
	_time += delta
	if _time >= release_sec and not _released:
		_released = true
		enemy.behavior.call(behavior_method)
	if _time < end_sec:
		return
	enemy_state_machine.transition_to("idle")
