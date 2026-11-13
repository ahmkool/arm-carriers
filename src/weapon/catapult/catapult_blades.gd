class_name CatapultBlades
extends SwordSpecifics
## Three short blades on the catapult's front grip, one either side of the front carrier and one pointing ahead of
## them, so the front carrier has a melee of their own. Like the sword's blade (`src/weapon/sword/hit_area.gd`, on
## the three HitAreas below this node), they only cut while the front carrier dashes and the grip actually moves: forward or back along the catapult, which
## the gap between the carriers allows, or sideways. A dash the carry distance stops dead doesn't cut.
## Extends SwordSpecifics for the interface hit_area.gd reads (is_strike_active, register_dash_hit, travel_direction);
## it leaves out the sword's trail and blocked-dash feedback.

## The grip the blades sit on: it moves with the front carrier as the gap changes.
@export var front_grip: Node3D

## Min grip movement per physics frame for a dash to count as a strike, as for the sword.
const GRIP_MOVEMENT_THRESHOLD := 0.1

var _last_grip := Vector3.ZERO
var _has_last_grip := false


## No trail: the blades are short, and the sword's trail reads its blade's full length.
func _ready() -> void:
	pass


func _physics_process(_delta: float) -> void:
	_follow_grip()
	var moved := _grip_movement()
	var front := _front_carrier()
	is_strike_active = front != null and front.is_dashing() and moved > GRIP_MOVEMENT_THRESHOLD
	if front != null and front.is_dashing():
		return
	_dash_hit_count = 0


func _follow_grip() -> void:
	if front_grip == null:
		return
	position = front_grip.position


func _grip_movement() -> float:
	var now := global_position
	if not _has_last_grip:
		_last_grip = now
		_has_last_grip = true
		return 0.0
	var movement := now - _last_grip
	_last_grip = now
	_update_travel_direction(movement)
	return movement.length()


## Only the front carrier's dash cuts: the back carrier has the shoot button.
func _front_carrier() -> PlayerLocal:
	if pick_and_drop_handler == null:
		return null
	var carrier := pick_and_drop_handler.get_carry_info().secondary_carrier
	if not is_instance_valid(carrier):
		return null
	return carrier
