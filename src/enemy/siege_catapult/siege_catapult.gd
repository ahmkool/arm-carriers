class_name SiegeCatapult
extends Node3D
## An enemy's catapult: the player catapult's model, its front pole resting on a fixed stake, its back handles held
## by the operator (the EnemyLocal this is a child of). Where the operator stands aims it, as the two carriers do: the
## direction from the operator to the stake is the throw's direction, and the distance between them sets the launch
## angle, close for a steep lob, far for a 45 degree throw. CatapultOperatorBehavior picks the spot.
## The stake can stand higher than the operator, such as on a hill he hides behind: the catapult then tilts up to rest
## on it, more steeply the closer he stands. Only its look tilts; the throw's angle still comes from the gap.
## It lives in world space (top_level), so it stays on its stake while the operator walks around it, and is respawned
## with the operator on a checkpoint reset. It stops when the operator dies, and goes when his body does.

signal fired(bomb: CatapultBomb)

## The stake, this far ahead of the operator where he is placed in the level.
@export var stake_distance := 5.5
@export var min_gap := 4.0
@export var max_gap := 7.5
## Faster than the carriers' catapult (15.5), so it reaches over a hill and across a ledge: at 18 the longest throw
## fell 6 m short of a carrier in the middle of the castle siege's ledge, about 25 m from the release.
@export var launch_speed := 22.0
@export var blast_radius := 3.0
@export var damage := 3
## Seconds for the arm to wind back down after a throw.
@export var reload_seconds := 1.6

## The operator holds the handles at shoulder height, as a carrier does.
const SHOULDER_HEIGHT := 1.35
## The back handles, in the model's space (the shooter's marker on the carriers' catapult).
const HANDLES_Z := -2.7
## Gaps tried when aiming, from min_gap to max_gap.
const AIM_STEPS := 36
## How far below the operator's feet a throw counts as lost (into the chasm).
const VOID_DROP := 4.5
## Where the front pole rests on the stake, above its foot.
const STAKE_FORK_HEIGHT := 1.2
## The stake is dropped onto the highest ground below this far above where it starts (the top of a hill).
const STAKE_SEARCH_HEIGHT := 8.0
const RING_LIFT := 0.06

const BOMB_SCENE := preload("res://src/weapon/catapult/catapult_bomb.tscn")
const LAUNCH_SOUND := preload("res://assets/sounds/slash_2.wav")
const THUD_SOUND := preload("res://assets/sounds/axe/yodguard-giant-axe-impact-striking-into-dirt-4-450258.mp3")

enum ArmState { LOADED, SWINGING, WINDING }

@onready var _model: Node3D = $Model
@onready var _arm: Node3D = $Model/Arm
@onready var _front_pole: Node3D = $Model/FrontPole
@onready var _front_grip: Node3D = $Model/FrontGrip
@onready var _stake: Node3D = $Stake
@onready var _ring: Node3D = $WarningRing
@onready var _ring_edge: MeshInstance3D = $WarningRing/Edge

var _operator: EnemyLocal
var _stake_position := Vector3.ZERO
## The stake's ground height is found once the level's collision is in place.
var _stake_grounded := false
var _arm_state := ArmState.LOADED
var _arm_angle := CatapultSpecifics.ARM_REST_ANGLE
var _state_time := 0.0
var _loaded_bomb: Node3D
var _gap := 5.5
var _ring_material: StandardMaterial3D
var _in_flight: CatapultBomb


func _ready() -> void:
	_operator = get_parent() as EnemyLocal
	top_level = true
	var facing := Vector3.FORWARD
	if _operator != null:
		facing = _flat(-_operator.global_basis.z)
	var start := (get_parent() as Node3D).global_position if get_parent() is Node3D else global_position
	_stake_position = start + facing * stake_distance
	_stake.top_level = true
	_stake.global_position = _stake_position
	_ring.top_level = true
	_ring.visible = false
	_ring.scale = Vector3(blast_radius, 1.0, blast_radius)
	_ring_material = _ring_edge.get_active_material(0) as StandardMaterial3D
	_loaded_bomb = CatapultSpecifics.BOMB_MODEL.instantiate() as Node3D
	_loaded_bomb.position = CatapultSpecifics.BOMB_IN_CUP
	_arm.add_child(_loaded_bomb)
	_pose()


func _physics_process(delta: float) -> void:
	_ground_stake()
	_update_arm(delta)
	_pose()
	_pulse_ring()


func stake_position() -> Vector3:
	return _stake_position


func is_loaded() -> bool:
	return _arm_state == ArmState.LOADED


func is_manned() -> bool:
	return is_instance_valid(_operator) and _operator.is_alive()


## Where the operator stands for a throw at `gap` toward `target`, at his own floor's height.
func spot_for(gap: float, target: Vector3) -> Vector3:
	var toward := _flat(target - _stake_position)
	var spot := _stake_position - toward * gap
	spot.y = _operator_floor_y()
	return spot


## Tries every gap and returns the throw landing nearest `target`: {gap, landing, error}, with error INF when no
## throw lands on the ground.
func aim_at(target: Vector3) -> Dictionary:
	var best := {"gap": max_gap, "landing": target, "error": INF}
	for step in AIM_STEPS + 1:
		var gap := lerpf(min_gap, max_gap, float(step) / AIM_STEPS)
		var flight := predict_flight(gap, target)
		if not flight.hit_ground:
			continue
		var landing: Vector3 = flight.landing
		var error := Vector2(landing.x - target.x, landing.z - target.z).length()
		if error < best.error:
			best = {"gap": gap, "landing": landing, "error": error}
	return best


## The flight a throw at `gap` toward `target` would take, with the operator standing where spot_for puts him.
func predict_flight(gap: float, target: Vector3) -> Dictionary:
	var toward := _flat(target - _stake_position)
	var feet := spot_for(gap, target)
	var pose := _pose_transform(feet, toward)
	return CatapultBomb.predict_flight(get_world_3d().direct_space_state, _release_position(pose),
		_launch_velocity(toward, gap), CatapultSpecifics.BOMB_GRAVITY, feet.y - VOID_DROP)


## Shows where the next throw lands, faintly, while the operator lines it up.
func show_aim(landing: Vector3) -> void:
	if is_instance_valid(_in_flight):
		return
	_place_ring(landing)
	_ring_material.albedo_color.a = 0.35


func hide_aim() -> void:
	if is_instance_valid(_in_flight):
		return
	_ring.visible = false


## Swings the arm and throws at the current gap. Returns false when it can't throw now.
func fire() -> bool:
	if not is_loaded() or not is_manned():
		return false
	_arm_state = ArmState.SWINGING
	_state_time = 0.0
	ImpactFeedback.play_sfx(LAUNCH_SOUND, _arm.global_position, 0.6, -2.0)
	return true


func _update_arm(delta: float) -> void:
	_state_time += delta
	match _arm_state:
		ArmState.SWINGING:
			_swing(delta)
		ArmState.WINDING:
			_wind()


func _swing(delta: float) -> void:
	_arm_angle = minf(_arm_angle + CatapultSpecifics.ARM_SWING_SPEED * delta, CatapultSpecifics.ARM_STOP_ANGLE)
	if _arm_angle < CatapultSpecifics.ARM_STOP_ANGLE:
		return
	_release()
	_arm_state = ArmState.WINDING
	_state_time = 0.0


func _wind() -> void:
	var t := clampf(_state_time / reload_seconds, 0.0, 1.0)
	_arm_angle = lerpf(CatapultSpecifics.ARM_STOP_ANGLE, CatapultSpecifics.ARM_REST_ANGLE, ease(t, 0.6))
	if t < 1.0:
		return
	_arm_state = ArmState.LOADED
	_loaded_bomb.visible = true


func _release() -> void:
	_loaded_bomb.visible = false
	if not is_manned():
		return
	var toward := _flat(_stake_position - _operator.global_position)
	var bomb := BOMB_SCENE.instantiate() as CatapultBomb
	bomb.make_hostile(damage, blast_radius)
	get_tree().current_scene.add_child(bomb)
	bomb.launch(_release_position(global_transform), _launch_velocity(toward, _gap), CatapultSpecifics.BOMB_GRAVITY,
		_operator.global_position.y - VOID_DROP)
	_in_flight = bomb
	bomb.exploded.connect(_on_bomb_exploded)
	var flight := CatapultBomb.predict_flight(get_world_3d().direct_space_state, _release_position(global_transform),
		_launch_velocity(toward, _gap), CatapultSpecifics.BOMB_GRAVITY, _operator.global_position.y - VOID_DROP)
	_place_ring(flight.landing)
	ImpactFeedback.play_sfx(THUD_SOUND, _arm.global_position, 1.2, -6.0)
	fired.emit(bomb)


## Follows the operator: the catapult sits between his hands and the stake, the front pole reaching the stake.
func _pose() -> void:
	_arm.position = CatapultSpecifics.ARM_PIVOT
	_arm.rotation = Vector3(_arm_angle, 0.0, 0.0)
	if not is_instance_valid(_operator):
		return
	if _operator.is_alive():
		_gap = clampf(_flat_distance(_operator.global_position, _stake_position), min_gap, max_gap)
	var toward := _flat(_stake_position - _operator.global_position)
	global_transform = _pose_transform(_operator.global_position, toward)
	var grip_z := HANDLES_Z + _handles(_operator.global_position).distance_to(_stake_fork())
	_front_pole.position = Vector3(0.0, -0.12, CatapultSpecifics.FRAME_FRONT_Z)
	_front_pole.scale = Vector3(1.0, 1.0, maxf(grip_z - CatapultSpecifics.FRAME_FRONT_Z, CatapultSpecifics.MIN_POLE_LENGTH))
	_front_grip.position = Vector3(0.0, -0.15, grip_z)


## The catapult's transform with the operator's feet at `feet`: its handles in his hands, its front end tilted up or
## down toward the fork on the stake. `toward` is used only when he stands right on the stake.
func _pose_transform(feet: Vector3, toward: Vector3) -> Transform3D:
	var along := _stake_fork() - _handles(feet)
	if Vector2(along.x, along.z).length() < 0.01:
		along = toward
	var basis := Basis.looking_at(-along.normalized(), Vector3.UP)
	return Transform3D(basis, _handles(feet) - basis.z * HANDLES_Z)


func _handles(feet: Vector3) -> Vector3:
	return feet + Vector3.UP * SHOULDER_HEIGHT


func _stake_fork() -> Vector3:
	return _stake_position + Vector3.UP * STAKE_FORK_HEIGHT


func _operator_floor_y() -> float:
	if is_instance_valid(_operator):
		return _operator.global_position.y
	return _stake_position.y


func _release_position(pose: Transform3D) -> Vector3:
	var arm_basis := Basis(Vector3.RIGHT, CatapultSpecifics.ARM_STOP_ANGLE)
	return pose * (CatapultSpecifics.ARM_PIVOT + arm_basis * CatapultSpecifics.BOMB_IN_CUP)


func _launch_velocity(toward: Vector3, gap: float) -> Vector3:
	var t := clampf(inverse_lerp(min_gap, max_gap, gap), 0.0, 1.0)
	var angle := deg_to_rad(lerpf(CatapultSpecifics.STEEP_LAUNCH_DEG, CatapultSpecifics.LONG_LAUNCH_DEG, t))
	return (toward * cos(angle) + Vector3.UP * sin(angle)) * launch_speed


## The ring brightens and pulses while a bomb is in the air.
func _pulse_ring() -> void:
	if not is_instance_valid(_in_flight):
		return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.02)
	_ring_material.albedo_color.a = lerpf(0.6, 0.95, pulse)


func _on_bomb_exploded(_at: Vector3) -> void:
	_in_flight = null
	_ring.visible = false


func _place_ring(landing: Vector3) -> void:
	_ring.global_position = landing + Vector3.UP * RING_LIFT
	_ring.visible = true


## Drops the stake onto the ground below it. Tries every physics frame until a ray hits: on the first ones the level's
## collision may not be registered yet.
func _ground_stake() -> void:
	if _stake_grounded:
		return
	var query := PhysicsRayQueryParameters3D.create(_stake_position + Vector3.UP * STAKE_SEARCH_HEIGHT,
		_stake_position + Vector3.DOWN * 6.0, CatapultBomb.LEVEL_COLLISION_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	_stake_grounded = true
	_stake_position.y = (hit.position as Vector3).y
	_stake.global_position = _stake_position


static func _flat(v: Vector3) -> Vector3:
	var flat := Vector3(v.x, 0.0, v.z)
	if flat.length_squared() < 0.0001:
		return Vector3.FORWARD
	return flat.normalized()


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
