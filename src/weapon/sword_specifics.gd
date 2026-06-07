class_name SwordSpecifics
extends Node3D

@export var pick_and_drop_handler: PickAndDropHandler

## Min sword-origin movement per physics frame for a dash to count as a real strike.
## Free-dash per-frame movement at 60 Hz is ~0.42 m; a fully clamped dash is ~0 m.
const STRIKE_MOVEMENT_THRESHOLD := 0.1

## True for the physics frames where at least one carrier is dashing AND that dash
## actually translated the sword (i.e. wasn't fully blocked by carrier-distance clamping).
## Read by `hit_area.gd` to decide whether contacts deal damage.
var is_strike_active: bool = false
var _last_origin: Vector3 = Vector3.ZERO
var _has_last_origin: bool = false


func _physics_process(_delta: float) -> void:
	_update_strike_active()


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
