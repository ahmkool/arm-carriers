class_name GunshipState
extends EnemyState
## Shared steering for the gunship's states: flying towards a point, holding altitude, facing, and banking the
## model into its motion.

## How quickly the velocity catches up with the wanted one, per second. Low keeps it heavy and floaty.
const ACCELERATION := 3.0
## Pull towards the wanted point, per metre off, before the speed cap.
const POSITION_GAIN := 1.6
const MAX_VERTICAL_SPEED := 5.0
const ALTITUDE_GAIN := 2.5
const LEAN_SMOOTH_LAMBDA := 5.0
const MAX_ROLL_DEGREES := 14.0
const MAX_PITCH_DEGREES := 8.0


func gunship() -> AviatorGunshipBehavior:
	return enemy.behavior as AviatorGunshipBehavior


func visual() -> Node3D:
	return enemy.get_node_or_null(^"Visual") as Node3D


## Eases the flat velocity towards the point at up to `max_speed`, and the height towards the point's.
func fly_toward(point: Vector3, max_speed: float, delta: float) -> void:
	var offset := point - enemy.global_position
	var flat := Vector3(offset.x, 0.0, offset.z) * POSITION_GAIN
	if flat.length() > max_speed:
		flat = flat.normalized() * max_speed
	var w := 1.0 - exp(-ACCELERATION * delta)
	enemy.velocity.x = lerpf(enemy.velocity.x, flat.x, w)
	enemy.velocity.z = lerpf(enemy.velocity.z, flat.z, w)
	enemy.velocity.y = clampf(offset.y * ALTITUDE_GAIN, -MAX_VERTICAL_SPEED, MAX_VERTICAL_SPEED)


func face(direction: Vector3, delta: float) -> void:
	enemy.smooth_rotate_toward(Vector3(direction.x, 0.0, direction.z), delta * 0.35)


## Rolls into sideways motion and dips the nose into forward motion, like a gunship banking.
func bank(delta: float) -> void:
	var pivot := visual()
	if pivot == null:
		return
	var local := enemy.global_basis.inverse() * enemy.velocity
	var top := maxf(gunship().relocate_speed, 0.01)
	var roll := -clampf(local.x / top, -1.0, 1.0) * MAX_ROLL_DEGREES
	var pitch := clampf(local.z / top, -1.0, 1.0) * MAX_PITCH_DEGREES
	var w := 1.0 - exp(-LEAN_SMOOTH_LAMBDA * delta)
	pivot.rotation.z = lerp_angle(pivot.rotation.z, deg_to_rad(roll), w)
	pivot.rotation.x = lerp_angle(pivot.rotation.x, deg_to_rad(pitch), w)
