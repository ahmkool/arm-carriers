class_name WorldLocal
extends Node3D

@onready var players = $Players
@onready var checkpoint_manager: Node = $CheckpointManager
const CARRIER_SHOULDER_HEIGHT := 1.35
# Called when the node enters the scene tree for the first time.

func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func restart_game() -> void:
	var game_state_machine = get_node_or_null("GameStateMachine") as GameStateMachine
	if game_state_machine == null:
		return

	players.reset_players_to_spawn()

	# Move active weapon to starting position.
	var weapon := _get_active_weapon()
	_place_weapon_and_carriers_at_checkpoint(weapon)

	# reset trial zones:
	for trial_zone in $Enemies.get_children():
		var trial_zone_node = trial_zone as TrialZone
		if trial_zone_node == null:
			continue
		trial_zone_node.reset()
	
	game_state_machine.transition_to("playing")


func _place_weapon_and_carriers_at_checkpoint(weapon: BigWeapon) -> void:
	if weapon == null:
		return

	# Fallback: keep old hardcoded placement if no checkpoint info available.
	if checkpoint_manager == null or not checkpoint_manager.has_method("get_spawn_transform") or not checkpoint_manager.has_method("get_shooter_transform"):
		weapon.global_position = Vector3(-7, 5, 0)
		weapon.global_rotation = Vector3.ZERO
		return

	var direction_setter_t: Transform3D = checkpoint_manager.call("get_spawn_transform")
	var shooter_t: Transform3D = checkpoint_manager.call("get_shooter_transform")

	var shooter_player: PlayerLocal = null
	var direction_setter_player: PlayerLocal = null
	for child in players.get_children():
		var pl := child as PlayerLocal
		if pl == null:
			continue
		if pl.player_id == 0:
			shooter_player = pl
		elif pl.player_id == 1:
			direction_setter_player = pl

	# Ensure players exist before forcing carry state.
	if shooter_player == null or direction_setter_player == null:
		weapon.global_position = Vector3(-7, 5, 0)
		weapon.global_rotation = Vector3.ZERO
		return

	# Put players at checkpoint markers (feet), then drive weapon pose from their shoulders.
	shooter_player.global_position = shooter_t.origin
	direction_setter_player.global_position = direction_setter_t.origin

	var shooter_shoulder := shooter_player.global_position + Vector3.UP * CARRIER_SHOULDER_HEIGHT
	var direction_setter_shoulder := direction_setter_player.global_position + Vector3.UP * CARRIER_SHOULDER_HEIGHT
	_apply_weapon_pose_from_ends(weapon, shooter_shoulder, direction_setter_shoulder)

	# Force both players to be carrying the weapon immediately.
	shooter_player.carrying_weapon_data.can_carry_status = CarryingWeaponData.CanCarryStatus.CARRYING_SHOOTER
	direction_setter_player.carrying_weapon_data.can_carry_status = CarryingWeaponData.CanCarryStatus.CARRYING_DIRECTION_SETTER
	shooter_player.weapon_carrier_pin_joint.set_node_b(weapon.get_path())
	direction_setter_player.weapon_carrier_pin_joint.set_node_b(weapon.get_path())


func _apply_weapon_pose_from_ends(weapon: BigWeapon, shooter_end_world: Vector3, direction_setter_end_world: Vector3) -> void:
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

	# Match weapon's internal shooter marker to the desired shooter end.
	var shooter_marker := weapon.get_node_or_null("ShooterPosition") as Marker3D
	if shooter_marker == null:
		return
	var shooter_local_offset := shooter_marker.position
	var target_origin := shooter_end_world - (target_basis * shooter_local_offset)
	weapon.global_transform = Transform3D(target_basis, target_origin)


func _get_active_weapon() -> BigWeapon:
	var weapon_root := get_node_or_null("Weapon")
	if weapon_root == null:
		return null
	for child in weapon_root.get_children():
		var weapon := child as BigWeapon
		if weapon != null:
			return weapon
	return null
