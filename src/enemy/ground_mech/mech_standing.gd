extends MechState
## On foot and standing: holds its ground with the gun on the target while awake, at ease while asleep.
## Walks off as soon as the behaviour wants to move.

@export var brake := 8.0


func physics_update(delta: float) -> void:
	if enemy.get_move_direction().length_squared() > 0.0001:
		enemy_state_machine.transition_to("walking")
		return
	var w := 1.0 - exp(-brake * delta)
	enemy.velocity.x = lerpf(enemy.velocity.x, 0.0, w)
	enemy.velocity.z = lerpf(enemy.velocity.z, 0.0, w)
	apply_gravity(delta)
	if enemy.is_offensive:
		aim_gun(delta)
		return
	turn_model_to_rest(delta)
	lean_visual(0.0, 0.0, delta)
