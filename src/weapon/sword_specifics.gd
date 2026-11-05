class_name SwordSpecifics
extends Node3D

@export var pick_and_drop_handler: PickAndDropHandler

## Min sword-origin movement per physics frame for a dash to count as a real strike.
## Free-dash per-frame movement at 60 Hz is ~0.42 m; a fully clamped dash is ~0 m.
const STRIKE_MOVEMENT_THRESHOLD := 0.1
const TRAIL_SCENE := preload("res://src/vfx/sword_trail.tscn")
const BLADE_LENGTH := 7.3

## True for the physics frames where at least one carrier is dashing AND that dash
## actually translated the sword (i.e. wasn't fully blocked by carrier-distance clamping).
## Read by `hit_area.gd` to decide whether contacts deal damage.
var is_strike_active: bool = false
var _last_origin: Vector3 = Vector3.ZERO
var _has_last_origin: bool = false
var _active_dasher: PlayerLocal = null
var _dash_landed_strike := false
var _dash_hit_count := 0
var _trail: SwordTrail
var _was_strike_active := false
## Flat direction the sword moved on the latest physics tick.
var travel_direction := Vector3.ZERO


func _ready() -> void:
	_trail = TRAIL_SCENE.instantiate() as SwordTrail
	add_child(_trail)


## Returns how many hits this dash landed before this one.
func register_dash_hit() -> int:
	var previous_hits := _dash_hit_count
	_dash_hit_count += 1
	return previous_hits


func _physics_process(_delta: float) -> void:
	_update_strike_active()
	_update_trail()
	_update_blocked_dash()


func _update_trail() -> void:
	var was_active := _was_strike_active
	_was_strike_active = is_strike_active
	if not is_strike_active:
		return
	var blade_start := get_parent().get_node_or_null("BladeStart") as Node3D
	if blade_start == null:
		return
	if not was_active:
		_trail.begin_stroke()
	var blade_axis := blade_start.global_basis.z.normalized()
	_trail.add_sample(blade_start.global_position, blade_start.global_position + blade_axis * BLADE_LENGTH)


## A dash is judged when it ends: its first tick has not moved the sword yet.
func _update_blocked_dash() -> void:
	var dasher := _get_dashing_carrier()
	if dasher != null:
		_active_dasher = dasher
		_dash_landed_strike = _dash_landed_strike or is_strike_active
		return
	if _active_dasher == null:
		return
	_dash_hit_count = 0
	var finished_dasher := _active_dasher
	var was_blocked := not _dash_landed_strike
	_active_dasher = null
	_dash_landed_strike = false
	if not was_blocked or not is_instance_valid(finished_dasher):
		return
	_play_blocked_dash(finished_dasher)


func _play_blocked_dash(dasher: PlayerLocal) -> void:
	var feedback := CarryFeedback.from_weapon(get_parent())
	if feedback == null:
		return
	feedback.play_blocked_dash(dasher)


func _get_dashing_carrier() -> PlayerLocal:
	if pick_and_drop_handler == null:
		return null
	var carry_info: CarryInfo = pick_and_drop_handler.get_carry_info()
	if is_instance_valid(carry_info.main_carrier) and carry_info.main_carrier.is_dashing():
		return carry_info.main_carrier
	if is_instance_valid(carry_info.secondary_carrier) and carry_info.secondary_carrier.is_dashing():
		return carry_info.secondary_carrier
	return null


func _update_strike_active() -> void:
	var weapon: BigWeapon = get_parent() as BigWeapon
	if weapon == null:
		is_strike_active = false
		_has_last_origin = false
		return

	var current_origin: Vector3 = weapon.global_transform.origin
	var origin_delta: float = 0.0
	if _has_last_origin:
		origin_delta = current_origin.distance_to(_last_origin)
		_update_travel_direction(current_origin - _last_origin)
	_last_origin = current_origin
	_has_last_origin = true

	var carry_info: CarryInfo = null
	if pick_and_drop_handler != null:
		carry_info = pick_and_drop_handler.get_carry_info()
	is_strike_active = _any_carrier_dashing(carry_info) and origin_delta > STRIKE_MOVEMENT_THRESHOLD


func _update_travel_direction(movement: Vector3) -> void:
	var flat := Vector3(movement.x, 0.0, movement.z)
	if flat.length_squared() < 0.0001:
		return
	travel_direction = flat.normalized()


func _any_carrier_dashing(carry_info: CarryInfo) -> bool:
	if carry_info == null:
		return false
	if is_instance_valid(carry_info.main_carrier) and carry_info.main_carrier.is_dashing():
		return true
	if is_instance_valid(carry_info.secondary_carrier) and carry_info.secondary_carrier.is_dashing():
		return true
	return false
