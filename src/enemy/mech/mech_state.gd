class_name MechState
extends EnemyState
## Shared steering for the Combat Mech states, winged (`src/enemy/winged_mech/`) and on foot (`src/enemy/ground_mech/`):
## holding height, facing, aiming the gun, and leaning the model into its motion.

## Highest climb or descent speed while holding altitude.
const MAX_VERTICAL_SPEED := 4.0
## How hard the mech pulls toward its hover altitude, per metre off.
const ALTITUDE_GAIN := 2.5
## How quickly the model's lean and turn ease toward their targets, roughly per second.
const LEAN_SMOOTH_LAMBDA := 8.0
## Lean while cruising at full hover speed.
const CRUISE_PITCH_DEGREES := 12.0
const CRUISE_ROLL_DEGREES := 18.0
## The model's yaw inside its pivot when not aiming, as for the other KayKit enemies.
const MODEL_REST_YAW_DEGREES := 180.0
const MAX_AIM_PITCH_DEGREES := 45.0
const GUN_HAND_PATH := ^"Visual/Mech/Rig_Medium/Skeleton3D/GunHand"
const BOLT_EMITTER_PATH := ^"Visual/Mech/Rig_Medium/Skeleton3D/GunHand/Minigun/Muzzle/BoltEmitter"
## Fallback when the emitter is missing: the height on the target the bolts aim at.
const DEFAULT_AIM_HEIGHT := 0.9
const GRAVITY := 20.0


func mech_behavior() -> WingedMechBehavior:
	return enemy.behavior as WingedMechBehavior


func visual() -> Node3D:
	return enemy.get_node_or_null(^"Visual") as Node3D


func model() -> Node3D:
	return enemy.get_node_or_null(^"Visual/Mech") as Node3D


## The `Muzzle` marker on whatever gun is in the right hand: the minigun or the grenade launcher.
func muzzle() -> Node3D:
	var hand := enemy.get_node_or_null(GUN_HAND_PATH)
	if hand == null:
		return null
	return hand.find_child("Muzzle", true, false) as Node3D


func has_aim() -> bool:
	return muzzle() != null and is_instance_valid(enemy.target_player)


## A winged mech holds its hover altitude; one on foot falls onto the floor and stays there.
func hold_height(delta: float) -> void:
	var hover := enemy.behavior as WingedMechBehavior
	if hover != null:
		enemy.velocity.y = altitude_velocity(hover.desired_altitude)
		return
	apply_gravity(delta)


func apply_gravity(delta: float) -> void:
	if enemy.is_on_floor():
		enemy.velocity.y = -0.1
		return
	enemy.velocity.y -= GRAVITY * delta


## Vertical speed that brings the mech to `altitude`.
func altitude_velocity(altitude: float) -> float:
	var error := altitude - enemy.global_position.y
	return clampf(error * ALTITUDE_GAIN, -MAX_VERTICAL_SPEED, MAX_VERTICAL_SPEED)


func face_flat(direction: Vector3, delta: float) -> void:
	enemy.smooth_rotate_toward(Vector3(direction.x, 0.0, direction.z), delta)


func face_target(delta: float) -> void:
	if not is_instance_valid(enemy.target_player):
		return
	face_flat(enemy.target_player.global_position - enemy.global_position, delta)


## Where the bolts go: the emitter's aim point on the target.
func aim_point() -> Vector3:
	var height := DEFAULT_AIM_HEIGHT
	var emitter := enemy.get_node_or_null(BOLT_EMITTER_PATH) as AimedBoltEmitter
	if emitter != null:
		height = emitter.aim_height
	return enemy.target_player.global_position + Vector3.UP * height


## When set, the barrel follows this instead of the straight line to the target, such as a grenade's arc.
var aim_direction_override := Vector3.ZERO


func shot_direction() -> Vector3:
	if aim_direction_override.length_squared() > 0.0001:
		return aim_direction_override.normalized()
	return (aim_point() - muzzle().global_position).normalized()


func barrel_direction() -> Vector3:
	return muzzle().global_basis.z.normalized()


## Points the gun along the shot. The aim pose holds the gun roughly forward but sways, and the muzzle sits off to
## one side, so this steers on the barrel itself instead of on fixed offsets: the body faces from the muzzle to the
## target, the model turns inside its pivot until the barrel lines up with that facing, and the pivot pitches
## until the barrel tips down onto the target.
## `extra_pitch_degrees` adds on top, for recoil. Roll follows the velocity, as when cruising.
func aim_gun(delta: float, extra_pitch_degrees := 0.0) -> void:
	if not has_aim():
		turn_model_to_rest(delta)
		lean_with_velocity(delta)
		return
	face_flat(aim_point() - muzzle().global_position, delta)
	_turn_model_onto_facing(delta)
	var pitch := clampf(_current_pitch_degrees() + _barrel_pitch_error_degrees(), -MAX_AIM_PITCH_DEGREES, MAX_AIM_PITCH_DEGREES)
	lean_visual(pitch + extra_pitch_degrees, _velocity_roll_degrees(), delta)


func turn_model_to_rest(delta: float) -> void:
	var mech := model()
	if mech == null:
		return
	var w := 1.0 - exp(-LEAN_SMOOTH_LAMBDA * delta)
	mech.rotation.y = lerp_angle(mech.rotation.y, deg_to_rad(MODEL_REST_YAW_DEGREES), w)


## Yaw of the barrel off the body's facing, flat. Positive turns the model the way that closes it.
func _turn_model_onto_facing(delta: float) -> void:
	var mech := model()
	if mech == null:
		return
	var local := enemy.global_basis.inverse() * barrel_direction()
	var yaw_off := atan2(local.x, -local.z)
	var w := 1.0 - exp(-LEAN_SMOOTH_LAMBDA * delta)
	mech.rotation.y += yaw_off * w


func _current_pitch_degrees() -> float:
	var pivot := visual()
	if pivot == null:
		return 0.0
	return rad_to_deg(pivot.rotation.x)


## How much more nose-up (positive) the barrel needs to point along the shot.
func _barrel_pitch_error_degrees() -> float:
	var barrel := rad_to_deg(asin(clampf(barrel_direction().y, -1.0, 1.0)))
	var shot := rad_to_deg(asin(clampf(shot_direction().y, -1.0, 1.0)))
	return shot - barrel


## Pitch is nose-down when negative. Angles in degrees.
func lean_visual(pitch_degrees: float, roll_degrees: float, delta: float) -> void:
	var pivot := visual()
	if pivot == null:
		return
	var w := 1.0 - exp(-LEAN_SMOOTH_LAMBDA * delta)
	pivot.rotation.x = lerp_angle(pivot.rotation.x, deg_to_rad(pitch_degrees), w)
	pivot.rotation.z = lerp_angle(pivot.rotation.z, deg_to_rad(roll_degrees), w)


## Leans into the current horizontal velocity, like a gunship banking through a turn.
func lean_with_velocity(delta: float) -> void:
	var local := enemy.global_basis.inverse() * enemy.velocity
	var top_speed := maxf(enemy.speed, 0.01)
	var forward := clampf(-local.z / top_speed, -1.0, 1.0)
	lean_visual(-forward * CRUISE_PITCH_DEGREES, _velocity_roll_degrees(), delta)


func _velocity_roll_degrees() -> float:
	var local := enemy.global_basis.inverse() * enemy.velocity
	var top_speed := maxf(enemy.speed, 0.01)
	return -clampf(local.x / top_speed, -1.0, 1.0) * CRUISE_ROLL_DEGREES
