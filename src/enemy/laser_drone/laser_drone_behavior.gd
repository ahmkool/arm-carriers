class_name LaserDroneBehavior
extends EnemyBehavior
## Behavior for the flying Laser Drone:
## 1. Alternates targeting Player 1 and Player 2, flying directly above that player's head.
## 2. Once overhead (or after `max_pursue_duration`), locks both its hover position and cannon
##    aim in place for a `telegraph_duration` dodge window, then fires for `fire_duration`.
## 3. Unlocks for a brief cooldown, switches to the other player, and repeats.
##
## When `lock_vertical_beam` is true, the locked laser points straight down (Vector3.DOWN),
## making a clean vertical column that players dodge and reflect straight back up with a flat
## (90°) mirror. Turning `lock_vertical_beam` off (or using `AimMode.FIXED_DIRECTION`) lets
## future sections aim and lock the articulated cannon in any 3D direction.

const LaserDroneCannonScript := preload("res://src/enemy/laser_drone/laser_drone_cannon.gd")

enum AimMode {
	TRACK_PLAYERS,
	FIXED_DIRECTION,
}

enum Phase {
	PURSUE,
	LOCKED_TELEGRAPH,
	LOCKED_FIRE,
	UNLOCK_COOLDOWN,
}

@export_group("Hover & Pursuit")
@export var hover_speed: float = 6.2
## Horizontal radius around spawn point the drone stays within (keeps locks over the island).
@export var leash_radius: float = 9.0
## Distance from directly over the target player's head to trigger the lock-on.
@export var lock_arrival_radius: float = 0.55
## Failsafe cap on pursuit so players can't kite the drone forever without it ever locking.
@export var max_pursue_duration: float = 3.2
@export var bob_amplitude: float = 0.22
@export var bob_period_seconds: float = 3.0
@export var body_turn_speed_degrees: float = 110.0
@export var halo_spin_degrees_per_sec: float = 55.0

@export_group("Lock & Fire Cycle")
@export var telegraph_duration: float = 0.75
@export var fire_duration: float = 2.8
@export var unlock_cooldown_duration: float = 0.65
## When true, fires straight down (exact Vector3.DOWN) when locked overhead for clean 90° reflections.
@export var lock_vertical_beam: bool = true

@export_group("Cannon Aim")
@export var aim_mode: AimMode = AimMode.TRACK_PLAYERS
## Used when `aim_mode == FIXED_DIRECTION`; can point in any 3D direction.
@export var fixed_aim_direction: Vector3 = Vector3.DOWN
@export var aim_target_height_offset: float = 0.65
@export var track_turn_speed_degrees: float = 200.0

var _home_position := Vector3.ZERO
var _home_captured := false
var _bob_time := 0.0
var _phase: Phase = Phase.PURSUE
var _phase_timer := 0.0
var _target_player_index := 0
var _locked_aim_direction := Vector3.DOWN
var _locked_position := Vector3.ZERO
var _was_offensive := false

var _cannon: LaserDroneCannonScript
var _hover_ring: Node3D
var _visual: Node3D


func _ready() -> void:
	super._ready()
	if enemy != null:
		_cannon = enemy.get_node_or_null("LaserDroneCannon") as LaserDroneCannonScript
		_visual = enemy.get_node_or_null("Visual") as Node3D
		if _visual != null:
			_hover_ring = _visual.find_child("HoverRing", true, false) as Node3D


func capture_home() -> void:
	if _home_captured or enemy == null:
		return
	_home_position = enemy.global_position
	_home_captured = true


func shutdown_weapon() -> void:
	if _cannon != null:
		_cannon.shutdown()


func step_hover(delta: float) -> void:
	if enemy == null:
		return
	capture_home()
	_bob_time += delta
	_spin_halo(delta)

	if not enemy.is_offensive:
		_was_offensive = false
		_phase = Phase.PURSUE
		_phase_timer = 0.0
		_steer_idle(delta)
		_bank_visual(delta, false)
		if _cannon != null:
			_cannon.set_beam_mode(LaserDroneCannonScript.BeamMode.OFF, 0.0)
			var idle_dir := fixed_aim_direction if aim_mode == AimMode.FIXED_DIRECTION else Vector3.DOWN
			_cannon.aim_in_direction(idle_dir, deg_to_rad(track_turn_speed_degrees), delta)
			_cannon.step_weapon(delta)
		return

	if not _was_offensive:
		_was_offensive = true
		_phase = Phase.PURSUE
		_phase_timer = 0.0

	var target_player := _resolve_target_player()
	match _phase:
		Phase.PURSUE:
			_step_pursue(target_player, delta)
		Phase.LOCKED_TELEGRAPH:
			_step_locked_telegraph(delta)
		Phase.LOCKED_FIRE:
			_step_locked_fire(delta)
		Phase.UNLOCK_COOLDOWN:
			_step_unlock_cooldown(target_player, delta)


func _step_pursue(target_player: PlayerLocal, delta: float) -> void:
	_phase_timer += delta
	var destination := _home_position
	if target_player != null and not enemy.holds_position and aim_mode == AimMode.TRACK_PLAYERS:
		destination = _clamp_to_leash(Vector3(target_player.global_position.x, _home_position.y, target_player.global_position.z))
	destination.y = _home_position.y + _current_bob()

	_move_toward_point(destination, hover_speed, delta)
	if target_player != null:
		_face_point(target_player.global_position, delta)
	_bank_visual(delta, true)

	if _cannon != null:
		_cannon.set_beam_mode(LaserDroneCannonScript.BeamMode.OFF, 0.0)
		_aim_cannon_unlocked(target_player, delta)
		_cannon.step_weapon(delta)

	var arrived := false
	if aim_mode == AimMode.FIXED_DIRECTION or enemy.holds_position or target_player == null:
		arrived = _phase_timer >= 0.8
	else:
		var flat_dist := Vector2(destination.x - enemy.global_position.x, destination.z - enemy.global_position.z).length()
		arrived = flat_dist <= lock_arrival_radius

	if arrived or _phase_timer >= max_pursue_duration:
		_enter_locked_telegraph(target_player)


func _enter_locked_telegraph(target_player: PlayerLocal) -> void:
	_phase = Phase.LOCKED_TELEGRAPH
	_phase_timer = 0.0
	_locked_position = Vector3(enemy.global_position.x, _home_position.y, enemy.global_position.z)
	enemy.velocity = Vector3.ZERO

	if aim_mode == AimMode.FIXED_DIRECTION:
		_locked_aim_direction = fixed_aim_direction.normalized()
	elif lock_vertical_beam:
		_locked_aim_direction = Vector3.DOWN
	elif target_player != null and _cannon != null:
		var aim_target := target_player.global_position + Vector3.UP * aim_target_height_offset
		var to_target := aim_target - _cannon.get_muzzle_position()
		_locked_aim_direction = to_target.normalized() if to_target.length_squared() > 0.0001 else Vector3.DOWN
	else:
		_locked_aim_direction = Vector3.DOWN

	if _cannon != null:
		_cannon.snap_to_direction(_locked_aim_direction)
		_cannon.set_beam_mode(LaserDroneCannonScript.BeamMode.TELEGRAPH, 0.0)


func _step_locked_telegraph(delta: float) -> void:
	_phase_timer += delta
	_hold_locked_position(delta)
	_bank_visual(delta, false)

	var ratio := clampf(_phase_timer / maxf(telegraph_duration, 0.001), 0.0, 1.0)
	if _cannon != null:
		_cannon.snap_to_direction(_locked_aim_direction)
		_cannon.set_beam_mode(LaserDroneCannonScript.BeamMode.TELEGRAPH, ratio)
		_cannon.step_weapon(delta, _locked_aim_direction)

	if _phase_timer >= telegraph_duration:
		_phase = Phase.LOCKED_FIRE
		_phase_timer = 0.0
		if _cannon != null:
			_cannon.set_beam_mode(LaserDroneCannonScript.BeamMode.FIRING, 1.0)


func _step_locked_fire(delta: float) -> void:
	_phase_timer += delta
	_hold_locked_position(delta)
	_bank_visual(delta, false)

	if _cannon != null:
		_cannon.snap_to_direction(_locked_aim_direction)
		_cannon.set_beam_mode(LaserDroneCannonScript.BeamMode.FIRING, 1.0)
		_cannon.step_weapon(delta, _locked_aim_direction)

	if _phase_timer >= fire_duration:
		_phase = Phase.UNLOCK_COOLDOWN
		_phase_timer = 0.0
		_target_player_index = (_target_player_index + 1) % 2
		if _cannon != null:
			_cannon.set_beam_mode(LaserDroneCannonScript.BeamMode.OFF, 0.0)


func _step_unlock_cooldown(next_target: PlayerLocal, delta: float) -> void:
	_phase_timer += delta
	_hold_locked_position(delta)
	_bank_visual(delta, false)
	if next_target != null:
		_face_point(next_target.global_position, delta)

	if _cannon != null:
		_cannon.set_beam_mode(LaserDroneCannonScript.BeamMode.OFF, 0.0)
		_aim_cannon_unlocked(next_target, delta)
		_cannon.step_weapon(delta)

	if _phase_timer >= unlock_cooldown_duration:
		_phase = Phase.PURSUE
		_phase_timer = 0.0


func _aim_cannon_unlocked(target_player: PlayerLocal, delta: float) -> void:
	var turn_rad := deg_to_rad(track_turn_speed_degrees)
	if aim_mode == AimMode.FIXED_DIRECTION:
		_cannon.aim_in_direction(fixed_aim_direction, turn_rad, delta)
	elif lock_vertical_beam:
		_cannon.aim_in_direction(Vector3.DOWN, turn_rad, delta)
	elif target_player != null:
		_cannon.aim_at_point(target_player.global_position + Vector3.UP * aim_target_height_offset, turn_rad, delta)
	else:
		_cannon.aim_in_direction(Vector3.DOWN, turn_rad, delta)


func _steer_idle(delta: float) -> void:
	var dest := Vector3(_home_position.x, _home_position.y + _current_bob(), _home_position.z)
	_move_toward_point(dest, hover_speed * 0.5, delta)


func _hold_locked_position(delta: float) -> void:
	var to_lock := _locked_position - enemy.global_position
	enemy.velocity = to_lock * 8.0
	if enemy.velocity.length() > hover_speed:
		enemy.velocity = enemy.velocity.normalized() * hover_speed
	enemy.velocity = enemy.velocity.lerp(Vector3.ZERO, clampf(4.0 * delta, 0.0, 1.0))


func _move_toward_point(dest: Vector3, max_speed: float, delta: float) -> void:
	var to_dest := dest - enemy.global_position
	var desired_vel := to_dest * 4.0
	if desired_vel.length() > max_speed:
		desired_vel = desired_vel.normalized() * max_speed
	enemy.velocity = enemy.velocity.lerp(desired_vel, clampf(7.5 * delta, 0.0, 1.0))


func _clamp_to_leash(point: Vector3) -> Vector3:
	var flat := Vector2(point.x - _home_position.x, point.z - _home_position.z)
	if flat.length() > leash_radius:
		flat = flat.normalized() * leash_radius
	return Vector3(_home_position.x + flat.x, point.y, _home_position.z + flat.y)


func _face_point(world_point: Vector3, delta: float) -> void:
	var flat := Vector3(world_point.x - enemy.global_position.x, 0.0, world_point.z - enemy.global_position.z)
	if flat.length_squared() < 0.05:
		return
	var target_yaw := atan2(-flat.x, -flat.z)
	var diff := wrapf(target_yaw - enemy.rotation.y, -PI, PI)
	var max_step := deg_to_rad(body_turn_speed_degrees) * delta
	enemy.rotation.y += clampf(diff, -max_step, max_step)


func _bank_visual(delta: float, allow_tilt: bool) -> void:
	if _visual == null:
		return
	var target_roll := 0.0
	var target_pitch := 0.0
	if allow_tilt:
		var local_vel := enemy.global_basis.inverse() * enemy.velocity
		target_roll = clampf(-local_vel.x * 0.06, -0.24, 0.24)
		target_pitch = clampf(local_vel.z * 0.055, -0.22, 0.22)
	_visual.rotation.z = lerpf(_visual.rotation.z, target_roll, clampf(8.0 * delta, 0.0, 1.0))
	_visual.rotation.x = lerpf(_visual.rotation.x, target_pitch, clampf(8.0 * delta, 0.0, 1.0))


func _spin_halo(delta: float) -> void:
	if _hover_ring == null:
		return
	var mult := 1.0
	if _phase == Phase.LOCKED_TELEGRAPH:
		mult = 2.4
	elif _phase == Phase.LOCKED_FIRE:
		mult = 3.8
	_hover_ring.rotate_y(deg_to_rad(halo_spin_degrees_per_sec) * mult * delta)


func _current_bob() -> float:
	return sin(_bob_time * TAU / maxf(bob_period_seconds, 0.1)) * bob_amplitude


## Alternates between living Player 1 and Player 2; falls back to whichever player is alive.
func _resolve_target_player() -> PlayerLocal:
	var living: Array[PlayerLocal] = []
	var players_node := _find_players_node()
	if players_node != null:
		for child in players_node.get_children():
			var p := child as PlayerLocal
			if p != null and not p.is_dead:
				living.append(p)
	if living.is_empty():
		return enemy.target_player if is_instance_valid(enemy.target_player) else null
	if living.size() == 1:
		return living[0]
	for p in living:
		if p.player_id == _target_player_index:
			return p
	return living[_target_player_index % living.size()]


func _find_players_node() -> Node:
	var n: Node = enemy.get_parent()
	while n != null:
		var players := n.get_node_or_null("Players")
		if players != null:
			return players
		n = n.get_parent()
	return null
