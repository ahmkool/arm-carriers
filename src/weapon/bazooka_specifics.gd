class_name BazookaSpecifics
extends Node3D

@onready var players: Players = LevelNodes.get_players(self)
@export var pick_and_drop_handler: PickAndDropHandler
@onready var muzzle: Marker3D = $Muzzle

var _bazooka_bullet_scene: PackedScene = preload("res://src/weapon/bazooka_bullet_local.tscn")


const SHOULDER_HEIGHT := 1.35
const MIN_CARRIER_DISTANCE := 1.6
const MAX_CARRIER_DISTANCE := 4.2
const FIRE_COOLDOWN_SEC := 0.75
const GROUND_COLLISION_MASK := 4
const GROUND_RAYCAST_UP := 0.5
const GROUND_RAYCAST_DOWN := 50.0
var _carrier_collision_exceptions: Array[PlayerLocal] = []
var _fixed_shooter_end_world := Vector3.ZERO
var _has_fixed_shooter_end := false
var _fixed_direction_setter_end_world := Vector3.ZERO
var _has_fixed_direction_setter_end := false
var _fire_cooldown_remaining := 0.0
var _was_carried := false
var _previous_carrier_count := 0

# Called when the node enters the scene tree for the first time.
func _ready():
	# Run after player movement so solo-carry range clamping sticks each frame.
	process_priority = -10


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _physics_process(delta):
	_fire_cooldown_remaining = maxf(0.0, _fire_cooldown_remaining - delta)
	var carry_info = pick_and_drop_handler.get_carry_info()
	_update_carrier_collision_exceptions(carry_info)
	var has_shooter := is_instance_valid(carry_info.main_carrier)
	var has_direction_setter := is_instance_valid(carry_info.secondary_carrier)
	var is_carried := has_shooter or has_direction_setter
	if not is_carried:
		_release_weapon_physics()
		_clear_fixed_endpoints()
		_was_carried = false
		_previous_carrier_count = 0
		return

	if not _was_carried:
		_prepare_weapon_for_carry()
	_was_carried = true

	var carrier_count := int(has_shooter) + int(has_direction_setter)
	if carrier_count == 1 and _previous_carrier_count == 2:
		_anchor_free_end_to_ground(has_shooter, has_direction_setter)
	_previous_carrier_count = carrier_count

	if has_shooter and has_direction_setter:
		_clear_fixed_endpoints()
		_enforce_carrier_distance(carry_info.main_carrier, carry_info.secondary_carrier)
		var shooter_shoulder := _get_player_shoulder_position(carry_info.main_carrier)
		var direction_setter_shoulder := _get_player_shoulder_position(carry_info.secondary_carrier)
		_apply_pose_from_ends(shooter_shoulder, direction_setter_shoulder)
		_check_firing_bullet(carry_info)
		_set_look_direction()
		return
	
	if has_shooter:
		_update_solo_shooter_carry(carry_info.main_carrier)
		return

	if has_direction_setter:
		_update_solo_direction_setter_carry(carry_info.secondary_carrier)

func _set_look_direction() -> void:
	var src := pick_and_drop_handler.look_vector_source
	var tgt := pick_and_drop_handler.look_vector_target
	var direction := tgt.global_position - src.global_position
	#DebugDraw3D.draw_arrow(src.global_position, tgt.global_position)
	pick_and_drop_handler.look_direction = direction.normalized()

func _check_firing_bullet(carry_info: CarryInfo) -> void:
	if GameplayInput.is_locked():
		return
	if not Input.is_action_just_pressed(carry_info.main_carrier.action_shoot):
		return
	if _fire_cooldown_remaining > 0.0:
		return
	_request_fire_bullet()

func _request_fire_bullet() -> void:
	print("requesting to fire bullet")
	var bullet := _bazooka_bullet_scene.instantiate() as BazookaBulletLocal
	if bullet == null:
		return
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = muzzle.global_position
	bullet.global_rotation = global_rotation
	bullet.velocity = muzzle.global_transform.basis.z * 5.0
	_fire_cooldown_remaining = FIRE_COOLDOWN_SEC
	CameraFeedback.add_trauma_shot()


func _apply_pose_from_ends(shooter_end_world: Vector3, direction_setter_end_world: Vector3) -> void:
	var carry_direction := direction_setter_end_world - shooter_end_world
	if carry_direction.length_squared() < 0.0001:
		return

	var forward := carry_direction.normalized()
	# When forward ~ world up, cross(up, forward) degenerates; use another reference axis.
	var ref_up := Vector3.UP
	if absf(forward.dot(ref_up)) > 0.98:
		ref_up = Vector3.FORWARD

	var weapon: BigWeapon = get_parent() as BigWeapon

	var right := ref_up.cross(forward).normalized()
	var corrected_up := forward.cross(right).normalized()
	var target_basis := Basis(right, corrected_up, forward).orthonormalized()

	var shooter_position_marker = pick_and_drop_handler.shooter_position_marker
	var shooter_local_offset = shooter_position_marker.position
	var target_origin = shooter_end_world - (target_basis * shooter_local_offset)
	weapon.global_transform = Transform3D(target_basis, target_origin)

	# Keep physics stable while we drive the transform directly.
	weapon.linear_velocity = Vector3.ZERO
	weapon.angular_velocity = Vector3.ZERO


func _clear_fixed_endpoints() -> void:
	_has_fixed_shooter_end = false
	_has_fixed_direction_setter_end = false


func _update_solo_shooter_carry(carrier: PlayerLocal) -> void:
	var direction_setter_marker: Marker3D = pick_and_drop_handler.direction_setter_position_marker
	_ensure_fixed_direction_setter_end(direction_setter_marker)
	_enforce_solo_carrier_range(carrier, _fixed_direction_setter_end_world)
	var shooter_shoulder := _get_player_shoulder_position(carrier)
	_apply_pose_from_ends(shooter_shoulder, _fixed_direction_setter_end_world)
	_set_look_direction()


func _update_solo_direction_setter_carry(carrier: PlayerLocal) -> void:
	var shooter_marker: Marker3D = pick_and_drop_handler.shooter_position_marker
	_ensure_fixed_shooter_end(shooter_marker)
	_enforce_solo_carrier_range(carrier, _fixed_shooter_end_world)
	var direction_setter_shoulder := _get_player_shoulder_position(carrier)
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
	var feet := carrier.global_position
	var flat_offset := Vector2(feet.x - anchored_end.x, feet.z - anchored_end.z)
	var flat_distance := flat_offset.length()
	if flat_distance <= MAX_CARRIER_DISTANCE:
		return
	if flat_distance < 0.0001:
		return
	var flat_direction := flat_offset / flat_distance
	var clamped_flat := flat_direction * MAX_CARRIER_DISTANCE
	carrier.global_position = Vector3(
		anchored_end.x + clamped_flat.x,
		feet.y,
		anchored_end.z + clamped_flat.y
	)
	_clamp_velocity_away_from_anchor(carrier, anchored_end)


func _clamp_velocity_away_from_anchor(carrier: PlayerLocal, anchored_end: Vector3) -> void:
	var flat_offset := Vector2(
		carrier.global_position.x - anchored_end.x,
		carrier.global_position.z - anchored_end.z
	)
	if flat_offset.length_squared() < 0.0001:
		return
	var away := Vector3(flat_offset.x, 0.0, flat_offset.y).normalized()
	var velocity_away := carrier.velocity.dot(away)
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
	var space_state := get_world_3d().direct_space_state
	var ray_start := world_pos + Vector3.UP * GROUND_RAYCAST_UP
	var ray_end := world_pos + Vector3.DOWN * GROUND_RAYCAST_DOWN
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collision_mask = GROUND_COLLISION_MASK
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return world_pos
	return hit.position


func _get_weapon() -> BigWeapon:
	return get_parent() as BigWeapon


func _prepare_weapon_for_carry() -> void:
	var weapon := _get_weapon()
	if weapon == null:
		return
	weapon.freeze = true
	weapon.linear_velocity = Vector3.ZERO
	weapon.angular_velocity = Vector3.ZERO


func _release_weapon_physics() -> void:
	if not _was_carried:
		return
	var weapon := _get_weapon()
	if weapon == null:
		return
	weapon.linear_velocity = Vector3.ZERO
	weapon.angular_velocity = Vector3.ZERO
	weapon.freeze = false


func _get_player_shoulder_position(player: PlayerLocal) -> Vector3:
	return player.global_position + Vector3.UP * SHOULDER_HEIGHT


func _update_carrier_collision_exceptions(carry_info: CarryInfo) -> void:
	var desired_exceptions: Array[PlayerLocal] = []
	if is_instance_valid(carry_info.main_carrier):
		desired_exceptions.append(carry_info.main_carrier)
	if is_instance_valid(carry_info.secondary_carrier):
		desired_exceptions.append(carry_info.secondary_carrier)

	var weapon: BigWeapon = get_parent() as BigWeapon
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


func _enforce_carrier_distance(shooter: PlayerLocal, direction_setter: PlayerLocal) -> void:
	var shooter_pos := shooter.global_position
	var direction_setter_pos := direction_setter.global_position
	var carry_delta := direction_setter_pos - shooter_pos
	var carry_distance := carry_delta.length()
	if carry_distance < 0.0001:
		direction_setter.global_position = shooter_pos + Vector3.FORWARD * MIN_CARRIER_DISTANCE
		return

	if carry_distance >= MIN_CARRIER_DISTANCE and carry_distance <= MAX_CARRIER_DISTANCE:
		return

	var clamped_distance := clampf(carry_distance, MIN_CARRIER_DISTANCE, MAX_CARRIER_DISTANCE)
	var clamped_direction_setter_pos := shooter_pos + (carry_delta.normalized() * clamped_distance)
	direction_setter.global_position = clamped_direction_setter_pos
