class_name CarryFeedback
extends Node
## Physical feedback for a two-player carried weapon: tether strain, recoil, blocked dashes
## and the moment both players lock onto the weapon. Created by `WeaponMovement`.

const NODE_NAME := &"CarryFeedback"
const VISUALS_PARENT_PATH := ^"WeaponSpecifics"
## Spins through an animation track, so non-uniform scale would make it wobble.
const SPINNING_MESH_NAME := &"Saw"

const CREAK_SOUNDS: Array[AudioStream] = [
	preload("res://assets/sounds/wood/WoodStep01.wav"),
	preload("res://assets/sounds/wood/WoodStep05.wav"),
	preload("res://assets/sounds/wood/WoodStep09.wav"),
]
const CLUNK_SOUND := preload("res://assets/sounds/punch/Punch 3_1.wav")
const LATCH_SOUND := preload("res://assets/sounds/ammo/reload.wav")

const TAUT_HOLD_SEC := 0.12
const CREAK_INTERVAL_SEC := 0.55
const SCUFF_INTERVAL_SEC := 0.2
const MAX_STRETCH := 0.035
const MAX_THIN := 0.02
const TENSION_SPEED := 10.0

const VISUAL_RECOVERY_SPEED := 12.0
const RECOIL_KICK_METERS := 0.35
const BLOCKED_KICK_METERS := 0.1
const BLOCKED_SQUASH := 0.05
const DRY_CLICK_KICK_METERS := 0.04
const LOCK_IN_LIFT_METERS := 0.22
const LOCK_IN_SQUASH := 0.1
const SAW_BITE_KICK_METERS := 0.07
const SAW_GRIND_KICK_METERS := 0.025

const SHOVE_SPEED := 2.0
const SHOVE_DURATION_SEC := 0.1
const SHOVE_GROUND_PROBE_AHEAD := 0.6
const GROUND_PROBE_UP := 0.5
const GROUND_PROBE_DOWN := 3.0

const FLASH_ENERGY := 6.0
const FLASH_RANGE := 7.0
const FLASH_COLOR := Color(1.0, 0.72, 0.4)
const FLASH_DURATION_SEC := 0.12

var _movement: WeaponMovement
var _meshes: Array[MeshInstance3D] = []
var _rest_positions: Array[Vector3] = []
var _rest_scales: Array[Vector3] = []
var _visuals_scale := 1.0

var _taut_hold := 0.0
var _creak_cooldown := 0.0
var _scuff_cooldown := 0.0
var _strain_leader: PlayerLocal
var _strain_follower: PlayerLocal

var _tension := 0.0
var _kick := 0.0
var _lift := 0.0
var _squash := 0.0

var _shove_velocity := Vector3.ZERO
var _shove_time_remaining := 0.0
var _shoved_carriers: Array[PlayerLocal] = []
var _lock_in_delay := -1.0
var _shudder_sign := 1.0


static func from_weapon(weapon: Node) -> CarryFeedback:
	if weapon == null:
		return null
	for child in weapon.get_children():
		if child is WeaponMovement:
			return child.get_node_or_null(String(NODE_NAME)) as CarryFeedback
	return null


func setup(movement: WeaponMovement) -> void:
	_movement = movement


func _ready() -> void:
	_cache_visuals()


func notify_tether_strain(leader: PlayerLocal, follower: PlayerLocal) -> void:
	_taut_hold = TAUT_HOLD_SEC
	_strain_leader = leader
	_strain_follower = follower


func play_recoil(fire_direction: Vector3, muzzle_position: Vector3) -> void:
	_kick = -RECOIL_KICK_METERS
	_spawn_muzzle_flash(muzzle_position)
	ImpactFeedback.spawn_dust(_project_to_ground(muzzle_position), 1.0)
	var carriers := _get_carriers()
	for carrier in carriers:
		ImpactFeedback.spawn_dust(carrier.global_position, 0.6)
		ImpactFeedback.rumble(carrier, 0.7, 0.4, 0.18)
	_begin_shove(carriers, -fire_direction)


func play_blocked_dash(dasher: PlayerLocal) -> void:
	_kick = -BLOCKED_KICK_METERS
	_squash = BLOCKED_SQUASH
	ImpactFeedback.play_sfx(CLUNK_SOUND, dasher.global_position, 0.6, -4.0)
	ImpactFeedback.spawn_dust(dasher.global_position, 0.5)
	ImpactFeedback.rumble(dasher, 0.2, 0.6, 0.12)


func play_dry_click(shooter: PlayerLocal, at_position: Vector3) -> void:
	_kick = minf(_kick, -DRY_CLICK_KICK_METERS)
	ImpactFeedback.play_sfx(LATCH_SOUND, at_position, 1.8, -10.0)
	ImpactFeedback.rumble(shooter, 0.25, 0.0, 0.05)


func play_saw_bite() -> void:
	_kick_shudder(SAW_BITE_KICK_METERS)
	for carrier in _get_carriers():
		ImpactFeedback.rumble(carrier, 0.45, 0.25, 0.12)


func play_saw_grind_tick() -> void:
	_kick_shudder(SAW_GRIND_KICK_METERS)
	for carrier in _get_carriers():
		ImpactFeedback.rumble(carrier, 0.2, 0.1, 0.1)


## Alternates direction each call so repeated kicks read as vibration.
func _kick_shudder(meters: float) -> void:
	_shudder_sign = -_shudder_sign
	_kick = meters * _shudder_sign


func play_lock_in(delay_sec: float) -> void:
	_lock_in_delay = delay_sec


func _physics_process(delta: float) -> void:
	_creak_cooldown = maxf(0.0, _creak_cooldown - delta)
	_scuff_cooldown = maxf(0.0, _scuff_cooldown - delta)
	_update_strain(delta)
	_update_shove(delta)
	_update_lock_in(delta)


func _process(delta: float) -> void:
	var target_tension := 1.0 if _taut_hold > 0.0 else 0.0
	_tension = move_toward(_tension, target_tension, TENSION_SPEED * delta)
	var recovery := exp(-VISUAL_RECOVERY_SPEED * delta)
	_kick *= recovery
	_lift *= recovery
	_squash *= recovery
	_apply_visual_pose()


func _update_strain(delta: float) -> void:
	if _taut_hold <= 0.0:
		return
	_taut_hold -= delta
	if not _has_valid_strain_carriers():
		return
	_try_play_creak()
	_try_play_scuff()


func _has_valid_strain_carriers() -> bool:
	return is_instance_valid(_strain_leader) and is_instance_valid(_strain_follower)


func _try_play_creak() -> void:
	if _creak_cooldown > 0.0:
		return
	_creak_cooldown = CREAK_INTERVAL_SEC
	var pitch := randf_range(0.5, 0.62)
	ImpactFeedback.play_sfx(CREAK_SOUNDS.pick_random(), _get_weapon().global_position, pitch, -6.0)
	ImpactFeedback.rumble(_strain_leader, 0.35, 0.15, 0.15)
	ImpactFeedback.rumble(_strain_follower, 0.35, 0.15, 0.15)


func _try_play_scuff() -> void:
	if _scuff_cooldown > 0.0:
		return
	_scuff_cooldown = SCUFF_INTERVAL_SEC
	ImpactFeedback.rumble(_strain_follower, 0.2, 0.0, SCUFF_INTERVAL_SEC + 0.02)
	if not _strain_follower.is_on_floor():
		return
	ImpactFeedback.spawn_dust(_strain_follower.global_position, 0.35)


## Skipped unless both carriers have ground behind them: a recoil must never push a
## player off a ledge, because falling ends the run.
func _begin_shove(carriers: Array[PlayerLocal], direction: Vector3) -> void:
	var flat_direction := Vector3(direction.x, 0.0, direction.z)
	if flat_direction.length_squared() < 0.0001:
		return
	flat_direction = flat_direction.normalized()
	for carrier in carriers:
		var probe_position := carrier.global_position + flat_direction * SHOVE_GROUND_PROBE_AHEAD
		if not _has_ground_below(probe_position):
			return
	_shoved_carriers = carriers
	_shove_velocity = flat_direction * SHOVE_SPEED
	_shove_time_remaining = SHOVE_DURATION_SEC


func _update_shove(delta: float) -> void:
	if _shove_time_remaining <= 0.0:
		return
	_shove_time_remaining -= delta
	for carrier in _shoved_carriers:
		if not is_instance_valid(carrier):
			continue
		carrier.move_and_collide(_shove_velocity * delta)


func _update_lock_in(delta: float) -> void:
	if _lock_in_delay < 0.0:
		return
	_lock_in_delay -= delta
	if _lock_in_delay > 0.0:
		return
	_lock_in_delay = -1.0
	_trigger_lock_in()


func _trigger_lock_in() -> void:
	var carriers := _get_carriers()
	if carriers.size() < 2:
		return
	_lift = LOCK_IN_LIFT_METERS
	_squash = LOCK_IN_SQUASH
	var weapon_position := _get_weapon().global_position
	ImpactFeedback.play_sfx(LATCH_SOUND, weapon_position, 0.8, -3.0)
	ImpactFeedback.play_sfx(CLUNK_SOUND, weapon_position, 0.55, -6.0)
	for carrier in carriers:
		ImpactFeedback.spawn_dust(carrier.global_position, 0.8)
		ImpactFeedback.rumble(carrier, 0.5, 0.5, 0.2)


func _get_carriers() -> Array[PlayerLocal]:
	var carriers: Array[PlayerLocal] = []
	var carry_info := _movement.pick_and_drop_handler.get_carry_info()
	if is_instance_valid(carry_info.main_carrier):
		carriers.append(carry_info.main_carrier)
	if is_instance_valid(carry_info.secondary_carrier):
		carriers.append(carry_info.secondary_carrier)
	return carriers


func _get_weapon() -> Node3D:
	return _movement.get_parent() as Node3D


func _cache_visuals() -> void:
	var visuals_parent := _get_weapon().get_node_or_null(VISUALS_PARENT_PATH) as Node3D
	if visuals_parent == null:
		return
	_visuals_scale = maxf(visuals_parent.scale.z, 0.0001)
	for child in visuals_parent.get_children():
		if child is MeshInstance3D:
			_add_visual(child as MeshInstance3D)


func _add_visual(mesh: MeshInstance3D) -> void:
	_meshes.append(mesh)
	_rest_positions.append(mesh.position)
	_rest_scales.append(mesh.scale)


func _apply_visual_pose() -> void:
	var offset := Vector3(0.0, _lift, _kick) / _visuals_scale
	var thin := 1.0 - _tension * MAX_THIN - _squash
	var stretch := 1.0 + _tension * MAX_STRETCH
	var pose_scale := Vector3(thin, thin, stretch)
	for index in _meshes.size():
		_apply_mesh_pose(index, offset, pose_scale)


func _apply_mesh_pose(index: int, offset: Vector3, pose_scale: Vector3) -> void:
	var mesh := _meshes[index]
	mesh.position = _rest_positions[index] + offset
	if mesh.name == SPINNING_MESH_NAME:
		return
	mesh.scale = _rest_scales[index] * pose_scale


func _spawn_muzzle_flash(at_position: Vector3) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var flash := OmniLight3D.new()
	flash.light_color = FLASH_COLOR
	flash.light_energy = FLASH_ENERGY
	flash.omni_range = FLASH_RANGE
	scene_root.add_child(flash)
	flash.global_position = at_position
	var tween := flash.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, FLASH_DURATION_SEC)
	tween.tween_callback(flash.queue_free)


func _has_ground_below(world_position: Vector3) -> bool:
	return not _raycast_ground(world_position).is_empty()


func _project_to_ground(world_position: Vector3) -> Vector3:
	var hit := _raycast_ground(world_position)
	if hit.is_empty():
		return world_position
	return hit.position


func _raycast_ground(world_position: Vector3) -> Dictionary:
	var ray_start := world_position + Vector3.UP * GROUND_PROBE_UP
	var ray_end := world_position + Vector3.DOWN * GROUND_PROBE_DOWN
	var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
	query.collision_mask = _movement.ground_collision_mask
	return _get_weapon().get_world_3d().direct_space_state.intersect_ray(query)
