extends MechState
## On foot and moving: walks the behaviour's path direction, facing where it goes, gun lowered to the run pose.

## How quickly it gets up to speed, per second. A heavy machine: slower to start than the robots.
@export var acceleration := 6.0


func physics_update(delta: float) -> void:
	var direction := enemy.get_move_direction()
	if direction.length_squared() < 0.0001:
		enemy_state_machine.transition_to("standing")
		return
	var desired := direction * enemy.speed
	var w := 1.0 - exp(-acceleration * delta)
	enemy.velocity.x = lerpf(enemy.velocity.x, desired.x, w)
	enemy.velocity.z = lerpf(enemy.velocity.z, desired.z, w)
	apply_gravity(delta)
	face_flat(direction, delta)
	turn_model_to_rest(delta)
	lean_visual(0.0, 0.0, delta)
