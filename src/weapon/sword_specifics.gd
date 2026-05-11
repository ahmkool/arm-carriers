class_name SwordSpecifics
extends Node3D

@export var pick_and_drop_handler: PickAndDropHandler

const SHOULDER_HEIGHT := 1.35
const MIN_CARRIER_DISTANCE := 1.6
const MAX_CARRIER_DISTANCE := 3.2
## Min sword-origin movement per physics frame for a dash to count as a real strike.
## Free-dash per-frame movement at 60 Hz is ~0.42 m; a fully clamped dash is ~0 m.
const STRIKE_MOVEMENT_THRESHOLD := 0.1

var _carrier_collision_exceptions: Array[PlayerLocal] = []
var _fixed_main_end_world := Vector3.ZERO
var _has_fixed_main_end := false
var _fixed_secondary_end_world := Vector3.ZERO
var _has_fixed_secondary_end := false

## True for the physics frames where at least one carrier is dashing AND that dash
## actually translated the sword (i.e. wasn't fully blocked by carrier-distance clamping).
## Read by `hit_area.gd` to decide whether contacts deal damage.
var is_strike_active := false
var _last_origin := Vector3.ZERO
var _has_last_origin := false


# Called when the node enters the scene tree for the first time.
func _ready():
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func _physics_process(_delta: float) -> void:
	_update_pose()
	_set_look_direction()
	_update_strike_active()


func _set_look_direction() -> void:
	var src := pick_and_drop_handler.look_vector_source
	var tgt := pick_and_drop_handler.look_vector_target
	var direction := tgt.global_position - src.global_position
	pick_and_drop_handler.look_direction = direction.normalized()


func _update_pose() -> void:
	if pick_and_drop_handler == null:
		return
	var carry_info = pick_and_drop_handler.get_carry_info()
	_update_carrier_collision_exceptions(carry_info)
	var has_main := is_instance_valid(carry_info.main_carrier)
	var has_secondary := is_instance_valid(carry_info.secondary_carrier)
	if not has_main and not has_secondary:
		_clear_fixed_endpoints()
		return

	if has_main and has_secondary:
		_clear_fixed_endpoints()
		_enforce_carrier_distance(carry_info.main_carrier, carry_info.secondary_carrier)
		var main_shoulder := _get_player_shoulder_position(carry_info.main_carrier)
		var secondary_shoulder := _get_player_shoulder_position(carry_info.secondary_carrier)
		_apply_pose_from_ends(main_shoulder, secondary_shoulder)
		return

	var secondary_position_marker: Marker3D = pick_and_drop_handler.direction_setter_position_marker
	if has_main:
		if not _has_fixed_secondary_end:
			_fixed_secondary_end_world = secondary_position_marker.global_position
			_has_fixed_secondary_end = true
		var main_shoulder := _get_player_shoulder_position(carry_info.main_carrier)
		_apply_pose_from_ends(main_shoulder, _fixed_secondary_end_world)
		return

	var main_position_marker: Marker3D = pick_and_drop_handler.shooter_position_marker
	if has_secondary:
		if not _has_fixed_main_end:
			_fixed_main_end_world = main_position_marker.global_position
			_has_fixed_main_end = true
		var secondary_shoulder := _get_player_shoulder_position(carry_info.secondary_carrier)
		_apply_pose_from_ends(_fixed_main_end_world, secondary_shoulder)


func _update_strike_active() -> void:
	var weapon: BigWeapon = get_parent() as BigWeapon
	if weapon == null:
		is_strike_active = false
		_has_last_origin = false
		return

	var current_origin := weapon.global_transform.origin
	var origin_delta := 0.0
	if _has_last_origin:
		origin_delta = current_origin.distance_to(_last_origin)
	_last_origin = current_origin
	_has_last_origin = true

	var carry_info: CarryInfo = null
	if pick_and_drop_handler != null:
		carry_info = pick_and_drop_handler.get_carry_info()
	is_strike_active = _any_carrier_dashing(carry_info) and origin_delta > STRIKE_MOVEMENT_THRESHOLD


func _any_carrier_dashing(carry_info: CarryInfo) -> bool:
	if carry_info == null:
		return false
	if is_instance_valid(carry_info.main_carrier) and carry_info.main_carrier.is_dashing():
		return true
	if is_instance_valid(carry_info.secondary_carrier) and carry_info.secondary_carrier.is_dashing():
		return true
	return false


func _apply_pose_from_ends(main_end_world: Vector3, secondary_end_world: Vector3) -> void:
	var carry_direction := secondary_end_world - main_end_world
	if carry_direction.length_squared() < 0.0001:
		return

	var forward := carry_direction.normalized()
	var up := Vector3.UP
	var weapon: BigWeapon = get_parent() as BigWeapon
	if weapon == null:
		return

	# Prevent invalid basis when aiming almost straight up/down.
	if absf(forward.dot(up)) > 0.98:
		up = Vector3.FORWARD
	var right := up.cross(forward).normalized()
	var corrected_up := forward.cross(right).normalized()
	var target_basis := Basis(right, corrected_up, forward).orthonormalized()

	var main_position_marker: Marker3D = pick_and_drop_handler.shooter_position_marker
	var main_local_offset := main_position_marker.position
	var target_origin := main_end_world - (target_basis * main_local_offset)
	weapon.global_transform = Transform3D(target_basis, target_origin)

	# Keep physics stable while we drive the transform directly.
	weapon.linear_velocity = Vector3.ZERO
	weapon.angular_velocity = Vector3.ZERO


func _clear_fixed_endpoints() -> void:
	_has_fixed_main_end = false
	_has_fixed_secondary_end = false


func _get_player_shoulder_position(player: PlayerLocal) -> Vector3:
	return player.global_position + Vector3.UP * SHOULDER_HEIGHT


func _update_carrier_collision_exceptions(carry_info: CarryInfo) -> void:
	var desired_exceptions: Array[PlayerLocal] = []
	if is_instance_valid(carry_info.main_carrier):
		desired_exceptions.append(carry_info.main_carrier)
	if is_instance_valid(carry_info.secondary_carrier):
		desired_exceptions.append(carry_info.secondary_carrier)

	var weapon: BigWeapon = get_parent() as BigWeapon
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


func _enforce_carrier_distance(main_carrier: PlayerLocal, secondary_carrier: PlayerLocal) -> void:
	var main_pos := main_carrier.global_position
	var secondary_pos := secondary_carrier.global_position
	var carry_delta := secondary_pos - main_pos
	var carry_distance := carry_delta.length()
	if carry_distance < 0.0001:
		secondary_carrier.global_position = main_pos + Vector3.FORWARD * MIN_CARRIER_DISTANCE
		return

	if carry_distance >= MIN_CARRIER_DISTANCE and carry_distance <= MAX_CARRIER_DISTANCE:
		return

	var clamped_distance := clampf(carry_distance, MIN_CARRIER_DISTANCE, MAX_CARRIER_DISTANCE)
	var clamped_secondary_pos := main_pos + (carry_delta.normalized() * clamped_distance)
	secondary_carrier.global_position = clamped_secondary_pos
