class_name Bazooka
extends RigidBody3D

@onready var players: Players = LevelNodes.get_players(self)
@onready var shooter_position_marker: Marker3D = $ShooterPosition
@onready var direction_setter_position_marker: Marker3D = $DirectionSetterPosition
@onready var muzzle: Marker3D = $Muzzle

var _bazooka_bullet_scene: PackedScene = preload("res://src/weapon/bazooka_bullet_local.tscn")


const SHOULDER_HEIGHT := 1.35
const MIN_CARRIER_DISTANCE := 1.6
const MAX_CARRIER_DISTANCE := 3.2
const FIRE_COOLDOWN_SEC := 0.75
var _carrier_collision_exceptions: Array[PlayerLocal] = []
var _fixed_shooter_end_world := Vector3.ZERO
var _has_fixed_shooter_end := false
var _fixed_direction_setter_end_world := Vector3.ZERO
var _has_fixed_direction_setter_end := false
var _fire_cooldown_remaining := 0.0

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func _physics_process(delta):
	_fire_cooldown_remaining = maxf(0.0, _fire_cooldown_remaining - delta)
	var carry_info = get_carry_info()
	_update_carrier_collision_exceptions(carry_info)
	var has_shooter := is_instance_valid(carry_info.shooter_player)
	var has_direction_setter := is_instance_valid(carry_info.direction_setter_player)
	if not has_shooter and not has_direction_setter:
		_clear_fixed_endpoints()
		return

	if has_shooter and has_direction_setter:
		_clear_fixed_endpoints()
		_enforce_carrier_distance(carry_info.shooter_player, carry_info.direction_setter_player)
		var shooter_shoulder := _get_player_shoulder_position(carry_info.shooter_player)
		var direction_setter_shoulder := _get_player_shoulder_position(carry_info.direction_setter_player)
		_apply_pose_from_ends(shooter_shoulder, direction_setter_shoulder)
		_check_firing_bullet(carry_info)
		return

	if has_shooter:
		if not _has_fixed_direction_setter_end:
			_fixed_direction_setter_end_world = direction_setter_position_marker.global_position
			_has_fixed_direction_setter_end = true
		var shooter_shoulder := _get_player_shoulder_position(carry_info.shooter_player)
		_apply_pose_from_ends(shooter_shoulder, _fixed_direction_setter_end_world)
		return

	if has_direction_setter:
		if not _has_fixed_shooter_end:
			_fixed_shooter_end_world = shooter_position_marker.global_position
			_has_fixed_shooter_end = true
		var direction_setter_shoulder := _get_player_shoulder_position(carry_info.direction_setter_player)
		_apply_pose_from_ends(_fixed_shooter_end_world, direction_setter_shoulder)

func _check_firing_bullet(carry_info: CarryInfo) -> void:
	if not Input.is_action_just_pressed(carry_info.shooter_player.action_shoot):
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


func _apply_pose_from_ends(shooter_end_world: Vector3, direction_setter_end_world: Vector3) -> void:
	var carry_direction := direction_setter_end_world - shooter_end_world
	if carry_direction.length_squared() < 0.0001:
		return

	var forward := carry_direction.normalized()
	var up := Vector3.UP
	# Prevent invalid basis when aiming almost straight up/down.
	if absf(forward.dot(up)) > 0.98:
		up = Vector3.FORWARD
	var right := up.cross(forward).normalized()
	var corrected_up := forward.cross(right).normalized()
	var target_basis := Basis(right, corrected_up, forward).orthonormalized()

	var shooter_local_offset := shooter_position_marker.position
	var target_origin := shooter_end_world - (target_basis * shooter_local_offset)
	global_transform = Transform3D(target_basis, target_origin)

	# Keep physics stable while we drive the transform directly.
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _clear_fixed_endpoints() -> void:
	_has_fixed_shooter_end = false
	_has_fixed_direction_setter_end = false

class CarryInfo:
	var shooter_player: PlayerLocal = null
	var direction_setter_player: PlayerLocal = null
	
func get_carry_info():
	var carry_info: CarryInfo = CarryInfo.new()
	if players == null:
		return carry_info
	for player in players.get_children():
		if player is PlayerLocal:
			if player.carrying_weapon_data.can_carry_status == CarryingWeaponData.CanCarryStatus.CARRYING_SHOOTER:
				carry_info.shooter_player = player
			elif player.carrying_weapon_data.can_carry_status == CarryingWeaponData.CanCarryStatus.CARRYING_DIRECTION_SETTER:
				carry_info.direction_setter_player = player
	return carry_info
	
func on_body_entered_shooter_zone(body: Node3D):
	if body is not PlayerLocal:
		return
	var player = body as PlayerLocal
	if _check_not_already_carrying(player):
		return
	player.carrying_weapon_data.can_carry_status = CarryingWeaponData.CanCarryStatus.CAN_CARRY_SHOOTER

func on_body_entered_direction_setter_zone(body: Node3D):
	if body is not PlayerLocal:
		return
	var player = body as PlayerLocal
	if _check_not_already_carrying(player):
		return
	player.carrying_weapon_data.can_carry_status = CarryingWeaponData.CanCarryStatus.CAN_CARRY_DIRECTION_SETTER

func on_body_exited_shooter_zone(body: Node3D):
	if body is not PlayerLocal:
		return
	var player = body as PlayerLocal
	if _check_not_already_carrying(player):
		return
	player.carrying_weapon_data.can_carry_status = CarryingWeaponData.CanCarryStatus.NO_WEAPON_AVAILABLE

func on_body_exited_direction_setter_zone(body: Node3D):
	if body is not PlayerLocal:
		return
	var player = body as PlayerLocal
	if _check_not_already_carrying(player):
		return
	player.carrying_weapon_data.can_carry_status = CarryingWeaponData.CanCarryStatus.NO_WEAPON_AVAILABLE

func _check_not_already_carrying(player: PlayerLocal):
	var carry_info = get_carry_info()
	if carry_info.shooter_player == player:
		return true
	if carry_info.direction_setter_player == player:
		return true
	return false


func _get_player_shoulder_position(player: PlayerLocal) -> Vector3:
	return player.global_position + Vector3.UP * SHOULDER_HEIGHT


func get_carry_direction_flat() -> Vector3:
	var direction := direction_setter_position_marker.global_position - shooter_position_marker.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return Vector3.ZERO
	return direction.normalized()


func _update_carrier_collision_exceptions(carry_info: CarryInfo) -> void:
	var desired_exceptions: Array[PlayerLocal] = []
	if is_instance_valid(carry_info.shooter_player):
		desired_exceptions.append(carry_info.shooter_player)
	if is_instance_valid(carry_info.direction_setter_player):
		desired_exceptions.append(carry_info.direction_setter_player)

	for player in _carrier_collision_exceptions:
		if not is_instance_valid(player):
			continue
		if desired_exceptions.has(player):
			continue
		remove_collision_exception_with(player)

	for player in desired_exceptions:
		if _carrier_collision_exceptions.has(player):
			continue
		add_collision_exception_with(player)

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
