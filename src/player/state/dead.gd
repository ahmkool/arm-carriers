extends PlayerState

func enter() -> void:
	player.velocity = Vector3.ZERO
	if not player._animate_on_dead_enter:
		return
	player.play_dead_animation()

func physics_update(delta: float) -> void:
	if not player.is_on_floor():
		player.velocity += player.get_gravity() * delta
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.SPEED)
	player.velocity.z = move_toward(player.velocity.z, 0.0, player.SPEED)
