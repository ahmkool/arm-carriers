extends GameState

const CARRIER_SHOULDER_HEIGHT := 1.35
const RESET_CHECKPOINT_DELAY := 0.5
const CHECKPOINT_FADE_DURATION := 0.15
const BOSS_HEALTH_BAR_PATH := "UI/BossHealthBar"

var _checkpoint_reset_timer: float = 0.0
var _world_reset_timer: float = 0.0
var _checkpoint_reset_applied: bool = false
var _world_reset_applied: bool = false

func enter():
	ScreenFade.fade_to_black(CHECKPOINT_FADE_DURATION)
	_hide_boss_health_bar()
	_checkpoint_reset_timer = CHECKPOINT_FADE_DURATION
	_world_reset_timer = CHECKPOINT_FADE_DURATION + RESET_CHECKPOINT_DELAY
	_checkpoint_reset_applied = false
	_world_reset_applied = false

func exit():
	ScreenFade.fade_from_black(CHECKPOINT_FADE_DURATION)

func _hide_boss_health_bar() -> void:
	var bar := world.get_node_or_null(BOSS_HEALTH_BAR_PATH) as BossHealthBar
	if bar == null:
		return
	bar.hide_bar()

func _apply_checkpoint_reset() -> void:
	var world_local := world as WorldLocal
	if world_local == null:
		push_error("ResettingCheckpointState: world is not WorldLocal")
		return
	var players = world_local.players as Players
	if players == null:
		push_error("ResettingCheckpointState: players is not found")
		return
	players.reset_players_to_spawn()

	# Move active weapon to starting position.
	var weapon := world_local.get_active_weapon() as BigWeapon
	_place_weapon_and_carriers_at_checkpoint(weapon)

func _apply_world_reset() -> void:
	var current_checkpoint = world.checkpoint_manager.current_checkpoint
	if current_checkpoint != null:
		current_checkpoint.set_world_at_checkpoint_state()

func _place_weapon_and_carriers_at_checkpoint(weapon: BigWeapon) -> void:
	if weapon == null:
		return
	var checkpoint_manager = world.checkpoint_manager as CheckpointManager
	var players = world.players as Players

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

	var shooter_shoulder = shooter_player.global_position + Vector3.UP * CARRIER_SHOULDER_HEIGHT
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


func physics_update(delta: float) -> void:
	if not _checkpoint_reset_applied:
		_checkpoint_reset_timer -= delta
		if _checkpoint_reset_timer <= 0.0:
			_checkpoint_reset_applied = true
			_apply_checkpoint_reset()

	if _world_reset_applied:
		return

	_world_reset_timer -= delta
	if _world_reset_timer > 0.0:
		return
	_world_reset_applied = true
	_apply_world_reset()
	game_state_machine.transition_to("playing")
