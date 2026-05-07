extends PlayerState


func physics_update(delta: float) -> void:
	if not player.is_on_floor():
		player_state_machine.transition_to("falling")
		return
	if Input.is_action_just_pressed(player.action_accept):
		player.velocity.y = player.JUMP_VELOCITY
		player_state_machine.transition_to("falling")
		return
	var direction := player.get_move_direction()
	if direction.length_squared() > 0.0001:
		player_state_machine.transition_to("running")
		return
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.SPEED)
	player.velocity.z = move_toward(player.velocity.z, 0.0, player.SPEED)
	var carry_status := player.carrying_weapon_data.can_carry_status
	if carry_status == CarryingWeaponData.CanCarryStatus.CARRYING_SHOOTER or carry_status == CarryingWeaponData.CanCarryStatus.CARRYING_DIRECTION_SETTER:
		var world_node := player.get_parent().get_parent()
		var bazooka := world_node.get_node_or_null("Bazooka") as Bazooka
		if is_instance_valid(bazooka):
			var bazooka_direction := bazooka.get_carry_direction_flat()
			if bazooka_direction.length_squared() > 0.0001:
				player.look_at(player.global_position + bazooka_direction, Vector3.UP)
