extends PlayerState

func enter() -> void:
	player.velocity = Vector3.ZERO
	player.play_dead_animation()

func physics_update(_delta: float) -> void:
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.SPEED)
	player.velocity.z = move_toward(player.velocity.z, 0.0, player.SPEED)
