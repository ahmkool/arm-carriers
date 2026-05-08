class_name PickAndDropHandler
extends Node3D

@onready var players: Players = LevelNodes.get_players(self)
@onready var shooter_position_marker = $ShooterPosition
@onready var direction_setter_position_marker = $DirectionSetterPosition

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
	if carry_info.main_carrier == player:
		return true
	if carry_info.secondary_carrier == player:
		return true
	return false
	
func get_carry_info():
	var carry_info: CarryInfo = CarryInfo.new()
	if players == null:
		return carry_info
	for player in players.get_children():
		if player is PlayerLocal:
			if player.carrying_weapon_data.can_carry_status == CarryingWeaponData.CanCarryStatus.CARRYING_SHOOTER:
				carry_info.main_carrier = player
			elif player.carrying_weapon_data.can_carry_status == CarryingWeaponData.CanCarryStatus.CARRYING_DIRECTION_SETTER:
				carry_info.secondary_carrier = player
	return carry_info

func get_carry_direction_flat() -> Vector3:
	var direction = direction_setter_position_marker.global_position - shooter_position_marker.global_position
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		return Vector3.ZERO
	return direction.normalized()
