class_name ShearsSpecifics
extends Node3D
## Giant shears: the gap between the carriers opens and closes the blades.
## Walking apart opens them. Rushing together snaps them shut and cuts every enemy caught
## between the blades during that closing stroke. Wider and faster strokes deal more damage.

signal snapped(damage: int, hit_count: int)

const HINGE_FORWARD := 2.0
const BLADE_LENGTH := 5.0
const CLOSED_HALF_ANGLE := deg_to_rad(2.0)
const OPEN_HALF_ANGLE := deg_to_rad(38.0)
## Enemy body radius, so a body overlapping a blade's edge counts as between the blades.
const ENEMY_MARGIN := 0.5
const BLADE_HEIGHT_OFFSET := 0.07

## The stroke ends this close to `min_carrier_distance`.
const SNAP_MARGIN := 0.35
## Closing less than this does nothing, so jostling at the closed position can't cut.
const MIN_STROKE_TRAVEL := 1.5
## Reopening by more than this abandons the current stroke.
const REOPEN_TOLERANCE := 0.15
const CLOSING_EPSILON := 0.001
## Both carriers running together close at 10 m/s, one alone at 5 m/s.
const FULL_POWER_CLOSING_SPEED := 8.0
const MIN_DAMAGE := 1
const MAX_DAMAGE := 3

const ARMED_OPENING := 0.9
const REST_GAP_SPEED := 8.0
const SLASH_HEIGHT := 1.0
const SLASH_SCENE := preload("res://src/vfx/sword_slash.tscn")
const SPARKS_SCENE := preload("res://src/vfx/saw_sparks.tscn")
const SNIP_SOUND := preload("res://assets/sounds/slash_2.wav")
const HIT_SOUND := preload("res://assets/sounds/damage/sword_hit.wav")
const ARMED_SOUND := preload("res://assets/sounds/ammo/reload.wav")

@export var pick_and_drop_handler: PickAndDropHandler
@export var weapon_movement: WeaponMovement

@onready var _rig: Node3D = $Rig
@onready var _blade_shooter: Node3D = $Rig/BladeShooter
@onready var _blade_setter: Node3D = $Rig/BladeSetter
@onready var _handle_shooter: Node3D = $Rig/HandleShooter
@onready var _handle_setter: Node3D = $Rig/HandleSetter
@onready var _jaw_area: Area3D = $Rig/JawArea

var _visual_gap := 0.0
var _half_angle := OPEN_HALF_ANGLE
var _shooter_z := 0.0
var _rest_gap := 0.0
var _has_stroke_history := false
var _stroke_peak := 0.0
var _stroke_low := 0.0
var _stroke_seconds := 0.0
var _last_gap := 0.0
var _is_armed := false
var _caught: Array[EnemyLocal] = []


func _ready() -> void:
	_blade_shooter.position.y = BLADE_HEIGHT_OFFSET
	_blade_setter.position.y = -BLADE_HEIGHT_OFFSET
	_shooter_z = pick_and_drop_handler.shooter_position_marker.position.z
	var setter_z := pick_and_drop_handler.direction_setter_position_marker.position.z
	_rest_gap = setter_z - _shooter_z
	_visual_gap = _rest_gap
	_apply_pose()


func _physics_process(delta: float) -> void:
	var carry_info := pick_and_drop_handler.get_carry_info()
	if not _is_carried_by_both(carry_info):
		_has_stroke_history = false
		_is_armed = false
		_caught.clear()
		_visual_gap = move_toward(_visual_gap, _rest_gap, REST_GAP_SPEED * delta)
		_apply_pose()
		return
	var gap := _get_carrier_gap(carry_info)
	_visual_gap = gap
	_apply_pose()
	_update_armed(gap)
	_update_stroke(gap, delta)


func _is_carried_by_both(carry_info: CarryInfo) -> bool:
	return is_instance_valid(carry_info.main_carrier) and is_instance_valid(carry_info.secondary_carrier)


func _get_carrier_gap(carry_info: CarryInfo) -> float:
	var between := carry_info.secondary_carrier.global_position - carry_info.main_carrier.global_position
	return Vector2(between.x, between.z).length()


func _apply_pose() -> void:
	var min_gap := weapon_movement.min_carrier_distance
	var max_gap := weapon_movement.max_carrier_distance
	var opening := clampf(inverse_lerp(min_gap, max_gap, _visual_gap), 0.0, 1.0)
	_half_angle = lerpf(CLOSED_HALF_ANGLE, OPEN_HALF_ANGLE, opening)
	# The weapon is anchored to the shooter, so the hinge follows the middle of the live gap.
	_rig.position.z = _shooter_z + _visual_gap * 0.5
	_blade_shooter.rotation.y = -_half_angle
	_blade_setter.rotation.y = _half_angle
	var half_gap := _visual_gap * 0.5
	_pose_handle(_handle_shooter, Vector3(-HINGE_FORWARD, 0.0, -half_gap))
	_pose_handle(_handle_setter, Vector3(-HINGE_FORWARD, 0.0, half_gap))


## Stretches a handle from the hinge to a carrier's end.
func _pose_handle(handle: Node3D, end: Vector3) -> void:
	handle.position = end * 0.5
	handle.basis = Basis.looking_at(end.normalized(), Vector3.UP)
	handle.scale = Vector3(1.0, 1.0, end.length())


## The click tells both players the blades are open wide enough for a full cut.
func _update_armed(gap: float) -> void:
	var min_gap := weapon_movement.min_carrier_distance
	var max_gap := weapon_movement.max_carrier_distance
	var is_open := inverse_lerp(min_gap, max_gap, gap) >= ARMED_OPENING
	if not is_open:
		return
	if _is_armed:
		return
	_is_armed = true
	ImpactFeedback.play_sfx(ARMED_SOUND, _rig.global_position, 1.3, -6.0)


func _update_stroke(gap: float, delta: float) -> void:
	if not _has_stroke_history:
		_begin_stroke(gap)
		_has_stroke_history = true
		return
	var closing_step := _last_gap - gap
	_last_gap = gap
	if gap > _stroke_peak or gap > _stroke_low + REOPEN_TOLERANCE:
		_begin_stroke(gap)
		return
	_stroke_low = minf(_stroke_low, gap)
	if closing_step <= CLOSING_EPSILON:
		return
	_stroke_seconds += delta
	_catch_enemies_between_blades()
	if not _is_stroke_finished(gap):
		return
	_snap(gap)
	_begin_stroke(gap)


func _begin_stroke(gap: float) -> void:
	_stroke_peak = gap
	_stroke_low = gap
	_stroke_seconds = 0.0
	_last_gap = gap
	_caught.clear()


func _is_stroke_finished(gap: float) -> bool:
	if gap > weapon_movement.min_carrier_distance + SNAP_MARGIN:
		return false
	return _stroke_peak - gap >= MIN_STROKE_TRAVEL


func _catch_enemies_between_blades() -> void:
	for body in _jaw_area.get_overlapping_bodies():
		var enemy := body as EnemyLocal
		if enemy == null or _caught.has(enemy):
			continue
		if not _is_between_blades(enemy):
			continue
		_caught.append(enemy)


func _is_between_blades(enemy: Node3D) -> bool:
	var local := _rig.to_local(enemy.global_position)
	if local.x < -ENEMY_MARGIN:
		return false
	if Vector2(local.x, local.z).length() > BLADE_LENGTH + ENEMY_MARGIN:
		return false
	return absf(local.z) <= maxf(local.x, 0.0) * tan(_half_angle) + ENEMY_MARGIN


func _snap(gap: float) -> void:
	var damage := _compute_damage(gap)
	var hit_count := _cut_caught_enemies(damage)
	_is_armed = false
	_play_snap_feedback(hit_count)
	snapped.emit(damage, hit_count)


func _compute_damage(gap: float) -> int:
	var travel := _stroke_peak - gap
	var full_travel := weapon_movement.max_carrier_distance - weapon_movement.min_carrier_distance - SNAP_MARGIN
	var width_power := clampf(travel / full_travel, 0.0, 1.0)
	var closing_speed := travel / maxf(_stroke_seconds, 0.001)
	var speed_power := clampf(closing_speed / FULL_POWER_CLOSING_SPEED, 0.0, 1.0)
	return roundi(lerpf(MIN_DAMAGE, MAX_DAMAGE, width_power * speed_power))


func _cut_caught_enemies(damage: int) -> int:
	var hit_count := 0
	for enemy in _caught:
		if _cut_enemy(enemy, damage):
			hit_count += 1
	return hit_count


func _cut_enemy(enemy: EnemyLocal, damage: int) -> bool:
	if not is_instance_valid(enemy):
		return false
	if not Health.apply_damage(enemy, damage, _rig.global_position):
		return false
	_spawn_slash(enemy)
	ImpactFeedback.play_sfx(HIT_SOUND, enemy.global_position, randf_range(0.9, 1.1), 0.0)
	return true


func _spawn_slash(enemy: Node3D) -> void:
	var slash := SLASH_SCENE.instantiate() as SwordSlash
	get_tree().current_scene.add_child(slash)
	slash.global_position = enemy.global_position + Vector3.UP * SLASH_HEIGHT
	slash.align_to(_rig.global_basis.z)


func _play_snap_feedback(hit_count: int) -> void:
	var meeting_point := _rig.to_global(Vector3(BLADE_LENGTH * 0.5, 0.0, 0.0))
	ImpactFeedback.play_sfx(SNIP_SOUND, meeting_point, randf_range(0.75, 0.9), 0.0)
	_spawn_sparks(meeting_point)
	var feedback := CarryFeedback.from_weapon(get_parent())
	if feedback != null:
		feedback.play_saw_bite()
	if hit_count == 0:
		CameraFeedback.add_trauma_shot()
		return
	ImpactFeedback.play_sword_hit()


func _spawn_sparks(at_position: Vector3) -> void:
	var sparks := SPARKS_SCENE.instantiate() as GPUParticles3D
	get_tree().current_scene.add_child(sparks)
	sparks.global_position = at_position
	sparks.emitting = true
