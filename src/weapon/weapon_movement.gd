class_name WeaponMovement
extends Node3D

@export var pick_and_drop_handler: PickAndDropHandler
@export var shoulder_height: float = 1.35
@export var min_carrier_distance: float = 1.6
@export var max_carrier_distance: float = 4.2
@export var carrier_drag_ratio: float = 0.2
@export var ground_collision_mask: int = 4
@export var ground_raycast_up: float = 0.5
@export var ground_raycast_down: float = 50.0

var _carrier_collision_exceptions: Array[PlayerLocal] = []
var _fixed_shooter_end_world: Vector3 = Vector3.ZERO
var _has_fixed_shooter_end: bool = false
var _fixed_direction_setter_end_world: Vector3 = Vector3.ZERO
var _has_fixed_direction_setter_end: bool = false
var _was_carried: bool = false
var _previous_carrier_count: int = 0
var _prev_shooter_feet: Vector3 = Vector3.ZERO
var _prev_direction_setter_feet: Vector3 = Vector3.ZERO
var _has_prev_dual_carry_positions: bool = false


func _ready() -> void:
	# Run after player movement so solo-carry range clamping sticks each frame.
	process_priority = -10


func _physics_process(delta: float) -> void:
	if pick_and_drop_handler == null:
		return

	var carry_info: CarryInfo = pick_and_drop_handler.get_carry_info()
	_update_carrier_collision_exceptions(carry_info)
	var has_shooter: bool = is_instance_valid(carry_info.main_carrier)
	var has_direction_setter: bool = is_instance_valid(carry_info.secondary_carrier)
	var is_carried: bool = has_shooter or has_direction_setter
	if not is_carried:
		_release_weapon_physics()
		_clear_fixed_endpoints()
		_clear_dual_carry_position_history()
		_was_carried = false
		_previous_carrier_count = 0
		return

	if not _was_carried:
		_prepare_weapon_for_carry()
	_was_carried = true

	var carrier_count: int = int(has_shooter) + int(has_direction_setter)
	if carrier_count == 1 and _previous_carrier_count == 2:
		_anchor_free_end_to_ground(has_shooter, has_direction_setter)
		_clear_dual_carry_position_history()
	_previous_carrier_count = carrier_count

	if has_shooter and has_direction_setter:
		_clear_fixed_endpoints()
		_enforce_carrier_distance(carry_info.main_carrier, carry_info.secondary_carrier, delta)
		var shooter_shoulder: Vector3 = _get_player_shoulder_position(carry_info.main_carrier)
		var direction_setter_shoulder: Vector3 = _get_player_shoulder_position(carry_info.secondary_carrier)
		_apply_pose_from_ends(shooter_shoulder, direction_setter_shoulder)
		_set_look_direction()
		return

	if has_shooter:
		_update_solo_shooter_carry(carry_info.main_carrier)
		return

	if has_direction_setter:
		_update_solo_direction_setter_carry(carry_info.secondary_carrier)


func _set_look_direction() -> void:
	var src: Node3D = pick_and_drop_handler.look_vector_source
	var tgt: Node3D = pick_and_drop_handler.look_vector_target
	var direction: Vector3 = tgt.global_position - src.global_position
	pick_and_drop_handler.look_direction = direction.normalized()


func _apply_pose_from_ends(shooter_end_world: Vector3, direction_setter_end_world: Vector3) -> void:
	var carry_direction: Vector3 = direction_setter_end_world - shooter_end_world
	if carry_direction.length_squared() < 0.0001:
		return

	var forward: Vector3 = carry_direction.normalized()
	var ref_up: Vector3 = Vector3.UP
	if absf(forward.dot(ref_up)) > 0.98:
		ref_up = Vector3.FORWARD

	var weapon: BigWeapon = _get_weapon()
	if weapon == null:
		return

	var right: Vector3 = ref_up.cross(forward).normalized()
	var corrected_up: Vector3 = forward.cross(right).normalized()
	var target_basis: Basis = Basis(right, corrected_up, forward).orthonormalized()

	var shooter_position_marker: Marker3D = pick_and_drop_handler.shooter_position_marker
	var shooter_local_offset: Vector3 = shooter_position_marker.position
	var target_origin: Vector3 = shooter_end_world - (target_basis * shooter_local_offset)
	weapon.global_transform = Transform3D(target_basis, target_origin)

	weapon.linear_velocity = Vector3.ZERO
	weapon.angular_velocity = Vector3.ZERO


func _clear_fixed_endpoints() -> void:
	_has_fixed_shooter_end = false
	_has_fixed_direction_setter_end = false


func _clear_dual_carry_position_history() -> void:
	_has_prev_dual_carry_positions = false


func _update_solo_shooter_carry(carrier: PlayerLocal) -> void:
	var direction_setter_marker: Marker3D = pick_and_drop_handler.direction_setter_position_marker
	_ensure_fixed_direction_setter_end(direction_setter_marker)
	_enforce_solo_carrier_range(carrier, _fixed_direction_setter_end_world)
	var shooter_shoulder: Vector3 = _get_player_shoulder_position(carrier)
	_apply_pose_from_ends(shooter_shoulder, _fixed_direction_setter_end_world)
	_set_look_direction()


func _update_solo_direction_setter_carry(carrier: PlayerLocal) -> void:
	var shooter_marker: Marker3D = pick_and_drop_handler.shooter_position_marker
	_ensure_fixed_shooter_end(shooter_marker)
	_enforce_solo_carrier_range(carrier, _fixed_shooter_end_world)
	var direction_setter_shoulder: Vector3 = _get_player_shoulder_position(carrier)
	_apply_pose_from_ends(_fixed_shooter_end_world, direction_setter_shoulder)
	_set_look_direction()


func _ensure_fixed_direction_setter_end(marker: Marker3D) -> void:
	if _has_fixed_direction_setter_end:
		return
	_fixed_direction_setter_end_world = _project_to_ground(marker.global_position)
	_has_fixed_direction_setter_end = true


func _ensure_fixed_shooter_end(marker: Marker3D) -> void:
	if _has_fixed_shooter_end:
		return
	_fixed_shooter_end_world = _project_to_ground(marker.global_position)
	_has_fixed_shooter_end = true


func _enforce_solo_carrier_range(carrier: PlayerLocal, anchored_end: Vector3) -> void:
	var feet: Vector3 = carrier.global_position
	var flat_offset: Vector2 = Vector2(feet.x - anchored_end.x, feet.z - anchored_end.z)
	var flat_distance: float = flat_offset.length()
	if flat_distance <= max_carrier_distance:
		return
	if flat_distance < 0.0001:
		return
	var flat_direction: Vector2 = flat_offset / flat_distance
	var clamped_flat: Vector2 = flat_direction * max_carrier_distance
	carrier.global_position = Vector3(
		anchored_end.x + clamped_flat.x,
		feet.y,
		anchored_end.z + clamped_flat.y
	)
	_clamp_velocity_away_from_anchor(carrier, anchored_end)


func _clamp_velocity_away_from_anchor(carrier: PlayerLocal, anchored_end: Vector3) -> void:
	var flat_offset: Vector2 = Vector2(
		carrier.global_position.x - anchored_end.x,
		carrier.global_position.z - anchored_end.z
	)
	if flat_offset.length_squared() < 0.0001:
		return
	var away: Vector3 = Vector3(flat_offset.x, 0.0, flat_offset.y).normalized()
	var velocity_away: float = carrier.velocity.dot(away)
	if velocity_away <= 0.0:
		return
	carrier.velocity -= away * velocity_away


func _anchor_free_end_to_ground(has_shooter: bool, has_direction_setter: bool) -> void:
	if has_shooter and not has_direction_setter:
		_ensure_fixed_direction_setter_end(pick_and_drop_handler.direction_setter_position_marker)
		return
	if has_direction_setter and not has_shooter:
		_ensure_fixed_shooter_end(pick_and_drop_handler.shooter_position_marker)


func _project_to_ground(world_pos: Vector3) -> Vector3:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var ray_start: Vector3 = world_pos + Vector3.UP * ground_raycast_up
	var ray_end: Vector3 = world_pos + Vector3.DOWN * ground_raycast_down
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collision_mask = ground_collision_mask
	var hit: Dictionary = space_state.intersect_ray(query)
	if hit.is_empty():
		return world_pos
	return hit.position


func _get_weapon() -> BigWeapon:
	return get_parent() as BigWeapon


func _prepare_weapon_for_carry() -> void:
	var weapon: BigWeapon = _get_weapon()
	if weapon == null:
		return
	weapon.freeze = true
	weapon.linear_velocity = Vector3.ZERO
	weapon.angular_velocity = Vector3.ZERO


func _release_weapon_physics() -> void:
	if not _was_carried:
		return
	var weapon: BigWeapon = _get_weapon()
	if weapon == null:
		return
	weapon.linear_velocity = Vector3.ZERO
	weapon.angular_velocity = Vector3.ZERO
	weapon.freeze = false


func _get_player_shoulder_position(player: PlayerLocal) -> Vector3:
	return player.global_position + Vector3.UP * shoulder_height


func _update_carrier_collision_exceptions(carry_info: CarryInfo) -> void:
	var desired_exceptions: Array[PlayerLocal] = []
	if is_instance_valid(carry_info.main_carrier):
		desired_exceptions.append(carry_info.main_carrier)
	if is_instance_valid(carry_info.secondary_carrier):
		desired_exceptions.append(carry_info.secondary_carrier)

	var weapon: BigWeapon = _get_weapon()
	if weapon == null:
		return

	for player in _carrier_collision_exceptions:
		if not is_instance_valid(player):
			continue
		if desired_exceptions.has(player):
			continue
		weapon.remove_collision_exception_with(player)

	for player in desired_exceptions:
		if _carrier_collision_exceptions.has(player):
			continue
		weapon.add_collision_exception_with(player)

	_carrier_collision_exceptions = desired_exceptions


func _enforce_carrier_distance(
	shooter: PlayerLocal,
	direction_setter: PlayerLocal,
	delta: float
) -> void:
	var shooter_pos: Vector3 = shooter.global_position
	var direction_setter_pos: Vector3 = direction_setter.global_position
	var carry_delta: Vector3 = _flat_delta(direction_setter_pos, shooter_pos)
	var carry_distance: float = carry_delta.length()
	if carry_distance < 0.0001:
		direction_setter.global_position = shooter_pos + Vector3.FORWARD * min_carrier_distance
		_store_dual_carry_positions(shooter, direction_setter)
		return

	if carry_distance >= min_carrier_distance and carry_distance <= max_carrier_distance:
		_store_dual_carry_positions(shooter, direction_setter)
		return

	var axis: Vector3 = carry_delta / carry_distance
	if carry_distance > max_carrier_distance:
		_resolve_carrier_distance_violation(
			shooter,
			direction_setter,
			axis,
			carry_distance,
			max_carrier_distance,
			true,
			delta
		)
		_store_dual_carry_positions(shooter, direction_setter)
		return

	_resolve_carrier_distance_violation(
		shooter,
		direction_setter,
		axis,
		carry_distance,
		min_carrier_distance,
		false,
		delta
	)
	_store_dual_carry_positions(shooter, direction_setter)


func _flat_delta(to_pos: Vector3, from_pos: Vector3) -> Vector3:
	return Vector3(to_pos.x - from_pos.x, 0.0, to_pos.z - from_pos.z)


func _store_dual_carry_positions(shooter: PlayerLocal, direction_setter: PlayerLocal) -> void:
	_prev_shooter_feet = shooter.global_position
	_prev_direction_setter_feet = direction_setter.global_position
	_has_prev_dual_carry_positions = true


func _resolve_carrier_distance_violation(
	shooter: PlayerLocal,
	direction_setter: PlayerLocal,
	axis: Vector3,
	carry_distance: float,
	target_distance: float,
	expanding: bool,
	delta: float
) -> void:
	if not _has_prev_dual_carry_positions:
		_hard_clamp_direction_setter_distance(shooter, direction_setter, axis, target_distance)
		return

	var leader: PlayerLocal = _resolve_distance_leader(shooter, direction_setter, axis, expanding)
	var follower: PlayerLocal = direction_setter if leader == shooter else shooter
	var leader_prev: Vector3 = _prev_shooter_feet if leader == shooter else _prev_direction_setter_feet
	var leader_move: Vector3 = _flat_delta(leader.global_position, leader_prev)
	var target_follower_pos: Vector3 = _follower_target_feet(
		leader,
		follower,
		shooter,
		axis,
		target_distance
	)
	var follower_pos: Vector3 = follower.global_position
	var drag_delta: Vector3 = _flat_delta(target_follower_pos, follower_pos)
	if drag_delta.length_squared() >= 0.0001:
		var max_drag: float = leader_move.length() * carrier_drag_ratio
		if max_drag < 0.0001:
			max_drag = absf(carry_distance - target_distance) * carrier_drag_ratio

		var applied_drag: Vector3 = drag_delta
		if applied_drag.length() > max_drag:
			applied_drag = applied_drag.normalized() * max_drag

		follower.global_position = Vector3(
			follower_pos.x + applied_drag.x,
			follower_pos.y,
			follower_pos.z + applied_drag.z
		)
		_sync_dragged_velocity(follower, applied_drag, delta)

	var axis_after: Vector3 = _current_carry_axis(shooter, direction_setter)
	if axis_after.length_squared() < 0.0001:
		return
	_clamp_leader_to_tether_distance(
		leader,
		follower,
		shooter,
		axis_after,
		target_distance,
		delta
	)


func _resolve_distance_leader(
	shooter: PlayerLocal,
	direction_setter: PlayerLocal,
	axis: Vector3,
	expanding: bool
) -> PlayerLocal:
	var shooter_delta: Vector3 = _flat_delta(shooter.global_position, _prev_shooter_feet)
	var setter_delta: Vector3 = _flat_delta(direction_setter.global_position, _prev_direction_setter_feet)
	if expanding:
		var shooter_expand: float = maxf(0.0, -shooter_delta.dot(axis))
		var setter_expand: float = maxf(0.0, setter_delta.dot(axis))
		if setter_expand >= shooter_expand:
			return direction_setter
		return shooter

	var shooter_compress: float = maxf(0.0, shooter_delta.dot(axis))
	var setter_compress: float = maxf(0.0, -setter_delta.dot(axis))
	if setter_compress >= shooter_compress:
		return direction_setter
	return shooter


func _follower_target_feet(
	leader: PlayerLocal,
	follower: PlayerLocal,
	shooter: PlayerLocal,
	axis: Vector3,
	target_distance: float
) -> Vector3:
	var leader_pos: Vector3 = leader.global_position
	var distance_sign: float = 1.0 if leader == shooter else -1.0
	return Vector3(
		leader_pos.x + axis.x * target_distance * distance_sign,
		follower.global_position.y,
		leader_pos.z + axis.z * target_distance * distance_sign
	)


func _current_carry_axis(shooter: PlayerLocal, direction_setter: PlayerLocal) -> Vector3:
	var carry_delta: Vector3 = _flat_delta(direction_setter.global_position, shooter.global_position)
	if carry_delta.length_squared() < 0.0001:
		return Vector3.ZERO
	return carry_delta.normalized()


func _leader_target_feet(
	leader: PlayerLocal,
	follower: PlayerLocal,
	shooter: PlayerLocal,
	axis: Vector3,
	target_distance: float
) -> Vector3:
	var follower_pos: Vector3 = follower.global_position
	if leader == shooter:
		return Vector3(
			follower_pos.x - axis.x * target_distance,
			leader.global_position.y,
			follower_pos.z - axis.z * target_distance
		)
	return Vector3(
		follower_pos.x + axis.x * target_distance,
		leader.global_position.y,
		follower_pos.z + axis.z * target_distance
	)


func _clamp_leader_to_tether_distance(
	leader: PlayerLocal,
	follower: PlayerLocal,
	shooter: PlayerLocal,
	axis: Vector3,
	target_distance: float,
	delta: float
) -> void:
	var leader_pos: Vector3 = leader.global_position
	var target_leader: Vector3 = _leader_target_feet(leader, follower, shooter, axis, target_distance)
	var clamp_delta: Vector3 = _flat_delta(target_leader, leader_pos)
	if clamp_delta.length_squared() < 0.0001:
		return
	leader.global_position = Vector3(
		target_leader.x,
		leader_pos.y,
		target_leader.z
	)
	_sync_dragged_velocity(leader, clamp_delta, delta)


func _hard_clamp_direction_setter_distance(
	shooter: PlayerLocal,
	direction_setter: PlayerLocal,
	axis: Vector3,
	target_distance: float
) -> void:
	var shooter_pos: Vector3 = shooter.global_position
	direction_setter.global_position = Vector3(
		shooter_pos.x + axis.x * target_distance,
		direction_setter.global_position.y,
		shooter_pos.z + axis.z * target_distance
	)


func _sync_dragged_velocity(player: PlayerLocal, flat_drag: Vector3, delta: float) -> void:
	if delta <= 0.0001:
		return
	var drag_velocity: Vector3 = flat_drag / delta
	player.velocity.x = drag_velocity.x
	player.velocity.z = drag_velocity.z
