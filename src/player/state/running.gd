extends PlayerState

const STEP_INTERVAL_SEC := 0.38
const CARRY_STEP_PITCH := 0.8
const CARRY_STEP_VOLUME_BOOST_DB := 2.5
const CARRY_STEP_DUST_DENSITY := 0.25

var _step_timer := 0.0
var _base_step_volume_db := 0.0
var _has_base_step_volume := false


func enter() -> void:
	if player.footsteps_particles:
		player.footsteps_particles.emitting = true
	_step_timer = 0.0
	_play_footstep()

func exit() -> void:
	if player.footsteps_particles:
		player.footsteps_particles.emitting = false

func physics_update(delta: float) -> void:
	if not player.is_on_floor():
		player_state_machine.transition_to("falling")
		return
	if Input.is_action_just_pressed(player.action_dash):
		player_state_machine.transition_to("dashing")
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
	_update_footsteps(delta)


func _update_footsteps(delta: float) -> void:
	_step_timer += delta
	if _step_timer < STEP_INTERVAL_SEC:
		return
	_step_timer -= STEP_INTERVAL_SEC
	_play_footstep()


func _play_footstep() -> void:
	if not player.footsteps_sound:
		return
	_remember_base_step_volume()
	var is_carrying := player.carrying_weapon_data.is_carrying()
	player.footsteps_sound.pitch_scale = CARRY_STEP_PITCH if is_carrying else 1.0
	var step_volume_db := _base_step_volume_db + (CARRY_STEP_VOLUME_BOOST_DB if is_carrying else 0.0)
	player.footsteps_sound.play_step(FootstepSurface.under(player), step_volume_db)
	if not is_carrying:
		return
	ImpactFeedback.spawn_dust(player.global_position, CARRY_STEP_DUST_DENSITY)


func _remember_base_step_volume() -> void:
	if _has_base_step_volume:
		return
	_base_step_volume_db = player.footsteps_sound.volume_db
	_has_base_step_volume = true
