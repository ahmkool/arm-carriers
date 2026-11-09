extends MechState
## Default state: drift along the behaviour's orbit direction at the hover altitude, gun on the target.

## How quickly the horizontal velocity catches up with the orbit direction, per second. Low keeps it floaty.
@export var acceleration := 3.0


func physics_update(delta: float) -> void:
	var behavior := mech_behavior()
	if behavior == null:
		return
	var desired := enemy.get_move_direction() * enemy.speed * behavior.speed_scale
	var w := 1.0 - exp(-acceleration * delta)
	enemy.velocity.x = lerpf(enemy.velocity.x, desired.x, w)
	enemy.velocity.z = lerpf(enemy.velocity.z, desired.z, w)
	enemy.velocity.y = altitude_velocity(behavior.desired_altitude)
	if enemy.is_offensive:
		aim_gun(delta)
		return
	turn_model_to_rest(delta)
	lean_with_velocity(delta)
