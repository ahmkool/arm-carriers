extends PlayerState


func physics_update(_delta: float) -> void:
	if not player.is_on_floor():
		player_state_machine.transition_to("falling")
		return
	if Input.is_action_just_pressed(player.action_accept):
		player.velocity.y = player.JUMP_VELOCITY
		player_state_machine.transition_to("falling")
		return
	var direction := player.get_move_direction()
	if direction.length_squared() < 0.0001:
		player_state_machine.transition_to("idle")
		return
	player.velocity.x = direction.x * player.SPEED
	player.velocity.z = direction.z * player.SPEED
	var look_direction := direction
	var carry_status := player.carrying_weapon_data.can_carry_status
	if carry_status == CarryingWeaponData.CanCarryStatus.CARRYING_SHOOTER or carry_status == CarryingWeaponData.CanCarryStatus.CARRYING_DIRECTION_SETTER:
		var world_node := player.get_parent().get_parent()
		var big_weapon_node: BigWeapon = world_node.get_node("Weapon").get_child(0) as BigWeapon
		var pick_and_drop_handler: PickAndDropHandler = big_weapon_node.get_node("PickAndDropHandler")
		if is_instance_valid(pick_and_drop_handler):
			var carry_direction := pick_and_drop_handler.get_carry_direction_flat()
			if carry_direction.length_squared() > 0.0001:
				look_direction = carry_direction
	player.look_at(player.global_position + look_direction, Vector3.UP)
