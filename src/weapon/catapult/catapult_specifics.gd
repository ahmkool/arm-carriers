class_name CatapultSpecifics
extends Node3D
## Carried catapult. The front carrier sets the launch angle by how far ahead of the back
## carrier they walk: close together lobs the bomb up steeply so it drops close, stretched
## out flattens the throw to 45 degrees, the longest one.
## The back carrier's shoot button swings the arm. A ring on the ground shows where the bomb
## will land, so the two can line it up together, and the arm winds back down to reload.

signal fired(bomb: CatapultBomb, launch_angle_deg: float)

## The bomb leaves the cup about 6 m up, so even a flat throw goes far. Short throws are
## steep lobs instead. With this speed and gravity, on flat ground they land about 7 m
## (carriers close) to 18 m (carriers apart) in front of the back carrier, after 1.3 to
## 1.6 s in the air.
const STEEP_LAUNCH_DEG := 82.0
const LONG_LAUNCH_DEG := 45.0
const LAUNCH_SPEED := 15.5
const BOMB_GRAVITY := 24.0
## A flight is lost once it drops this far below the back carrier's feet: into lava or a pit.
const VOID_DROP := 4.5
## The camera frames a point this far past the landing, so the whole ring stays on screen.
const CAMERA_LEAD := 4.0

## Must match ARM_PIVOT in tools/blender/build_catapult.py.
const ARM_PIVOT := Vector3(0.0, 0.55, 0.15)
## Where the bomb sits, in the arm's own space: in the cup at the end of the arm.
const BOMB_IN_CUP := Vector3(0.0, 0.52, -2.3)
## Loaded, the arm lies back with its cup a little low. Firing swings it up and over until
## it hits the stop bar, where the bomb flies out of the cup.
const ARM_REST_ANGLE := deg_to_rad(-8.0)
const ARM_STOP_ANGLE := deg_to_rad(105.0)
const ARM_SWING_SPEED := deg_to_rad(900.0)
const ARM_HOLD_SEC := 0.25
const ARM_WIND_SEC := 1.2
const FRAME_FRONT_Z := 1.15
const MIN_POLE_LENGTH := 0.2

const BOMB_SCENE := preload("res://src/weapon/catapult/catapult_bomb.tscn")
const BOMB_MODEL := preload("res://assets/models/weapon/catapult/catapult_bomb.glb")
const LAUNCH_SOUND := preload("res://assets/sounds/slash_2.wav")
const THUD_SOUND := preload("res://assets/sounds/axe/yodguard-giant-axe-impact-striking-into-dirt-4-450258.mp3")
const RELOAD_SOUND := preload("res://assets/sounds/ammo/reload.wav")

enum ArmState { LOADED, SWINGING, HOLDING, WINDING }

@export var pick_and_drop_handler: PickAndDropHandler
@export var weapon_movement: WeaponMovement

@onready var _arm: Node3D = $Model/Arm
@onready var _front_pole: Node3D = $Model/FrontPole
@onready var _front_grip: Node3D = $Model/FrontGrip
@onready var _aim_guide: CatapultAimGuide = $AimGuide
@onready var _camera_target: Marker3D = $CameraAddons/Target

var _loaded_bomb: Node3D
var _arm_state := ArmState.LOADED
var _arm_angle := ARM_REST_ANGLE
var _state_time := 0.0
var _shooter_z := 0.0
var _rest_gap := 0.0
var _camera_target_rest := Vector3.ZERO
## The launch angle locked in when the arm starts swinging, so walking mid-swing can't change it.
var _swing_launch_deg := 0.0


func _ready() -> void:
	_shooter_z = pick_and_drop_handler.shooter_position_marker.position.z
	_rest_gap = pick_and_drop_handler.direction_setter_position_marker.position.z - _shooter_z
	_camera_target_rest = _camera_target.position
	_loaded_bomb = BOMB_MODEL.instantiate() as Node3D
	_loaded_bomb.position = BOMB_IN_CUP
	_arm.add_child(_loaded_bomb)
	_apply_arm_pose()
	_pose_front_pole(_rest_gap)


func _physics_process(delta: float) -> void:
	_update_arm(delta)
	var carry_info := pick_and_drop_handler.get_carry_info()
	if not _is_carried_by_both(carry_info):
		_aim_guide.hide_guide()
		_camera_target.position = _camera_target_rest
		_pose_front_pole(_rest_gap)
		return
	var gap := _get_carrier_gap(carry_info)
	_pose_front_pole(gap)
	var launch_deg := get_launch_angle_deg(gap)
	_update_aim_guide(launch_deg, carry_info.main_carrier)
	_try_fire(carry_info.main_carrier, launch_deg)


func is_loaded() -> bool:
	return _arm_state == ArmState.LOADED


func get_launch_angle_deg(gap: float) -> float:
	var t := inverse_lerp(weapon_movement.min_carrier_distance, weapon_movement.max_carrier_distance, gap)
	return lerpf(STEEP_LAUNCH_DEG, LONG_LAUNCH_DEG, clampf(t, 0.0, 1.0))


## Where a bomb thrown at `launch_deg` would land right now. Used by the guide and test drivers.
func predict_flight(launch_deg: float, shooter: PlayerLocal) -> Dictionary:
	return CatapultBomb.predict_flight(
		get_world_3d().direct_space_state,
		_get_release_position(),
		_get_launch_velocity(launch_deg),
		BOMB_GRAVITY,
		shooter.global_position.y - VOID_DROP
	)


func _is_carried_by_both(carry_info: CarryInfo) -> bool:
	return is_instance_valid(carry_info.main_carrier) and is_instance_valid(carry_info.secondary_carrier)


func _get_carrier_gap(carry_info: CarryInfo) -> float:
	var between := carry_info.secondary_carrier.global_position - carry_info.main_carrier.global_position
	return Vector2(between.x, between.z).length()


func _update_aim_guide(launch_deg: float, shooter: PlayerLocal) -> void:
	if _arm_state == ArmState.SWINGING:
		return
	var flight := predict_flight(launch_deg, shooter)
	_aim_guide.show_flight(flight, is_loaded())
	_camera_target.global_position = flight.landing + _get_flat_forward() * CAMERA_LEAD


func _try_fire(shooter: PlayerLocal, launch_deg: float) -> void:
	if GameplayInput.is_locked():
		return
	if not Input.is_action_just_pressed(shooter.action_shoot):
		return
	if not is_loaded():
		_play_dry_click(shooter)
		return
	start_swing(launch_deg)


## Swings the arm and lets the bomb go at `launch_deg`. Test drivers can call this directly.
func start_swing(launch_deg: float) -> void:
	if not is_loaded():
		return
	_swing_launch_deg = launch_deg
	_set_arm_state(ArmState.SWINGING)
	ImpactFeedback.play_sfx(LAUNCH_SOUND, _arm.global_position, 0.6, -2.0)


func _update_arm(delta: float) -> void:
	_state_time += delta
	match _arm_state:
		ArmState.SWINGING:
			_update_swing(delta)
		ArmState.HOLDING:
			_update_hold()
		ArmState.WINDING:
			_update_wind()
	_apply_arm_pose()


func _update_swing(delta: float) -> void:
	_arm_angle = minf(_arm_angle + ARM_SWING_SPEED * delta, ARM_STOP_ANGLE)
	if _arm_angle < ARM_STOP_ANGLE:
		return
	_release_bomb()
	_set_arm_state(ArmState.HOLDING)


func _update_hold() -> void:
	if _state_time < ARM_HOLD_SEC:
		return
	_set_arm_state(ArmState.WINDING)


func _update_wind() -> void:
	var t := clampf(_state_time / ARM_WIND_SEC, 0.0, 1.0)
	_arm_angle = lerpf(ARM_STOP_ANGLE, ARM_REST_ANGLE, ease(t, 0.6))
	if t < 1.0:
		return
	_set_arm_state(ArmState.LOADED)
	ImpactFeedback.play_sfx(RELOAD_SOUND, _arm.global_position, 0.8, -6.0)


func _set_arm_state(state: ArmState) -> void:
	_arm_state = state
	_state_time = 0.0
	_loaded_bomb.visible = state == ArmState.LOADED or state == ArmState.SWINGING


func _release_bomb() -> void:
	var carry_info := pick_and_drop_handler.get_carry_info()
	var floor_y := global_position.y - VOID_DROP - weapon_movement.shoulder_height
	if is_instance_valid(carry_info.main_carrier):
		floor_y = carry_info.main_carrier.global_position.y - VOID_DROP
	var bomb := BOMB_SCENE.instantiate() as CatapultBomb
	get_tree().current_scene.add_child(bomb)
	bomb.launch(
		_get_release_position(),
		_get_launch_velocity(_swing_launch_deg),
		BOMB_GRAVITY,
		floor_y
	)
	_play_release_feedback()
	fired.emit(bomb, _swing_launch_deg)


## Where the bomb leaves the cup: with the arm against the stop bar.
func _get_release_position() -> Vector3:
	var arm_basis := Basis(Vector3.RIGHT, ARM_STOP_ANGLE)
	return to_global(ARM_PIVOT + arm_basis * BOMB_IN_CUP)


func _get_launch_velocity(launch_deg: float) -> Vector3:
	var angle := deg_to_rad(launch_deg)
	return (_get_flat_forward() * cos(angle) + Vector3.UP * sin(angle)) * LAUNCH_SPEED


func _get_flat_forward() -> Vector3:
	var forward := global_basis.z
	forward.y = 0.0
	return forward.normalized()


func _apply_arm_pose() -> void:
	_arm.position = ARM_PIVOT
	_arm.rotation = Vector3(_arm_angle, 0.0, 0.0)


## The front pole reaches from the frame to wherever the front carrier holds it.
func _pose_front_pole(gap: float) -> void:
	var grip_z := maxf(_shooter_z + gap, FRAME_FRONT_Z + MIN_POLE_LENGTH)
	_front_pole.position = Vector3(0.0, -0.12, FRAME_FRONT_Z)
	_front_pole.scale = Vector3(1.0, 1.0, grip_z - FRAME_FRONT_Z)
	_front_grip.position = Vector3(0.0, -0.15, grip_z)


func _play_release_feedback() -> void:
	ImpactFeedback.play_sfx(THUD_SOUND, _arm.global_position, 1.2, -6.0)
	CameraFeedback.add_trauma_shot()
	var carry_info := pick_and_drop_handler.get_carry_info()
	_rumble(carry_info.main_carrier)
	_rumble(carry_info.secondary_carrier)


func _rumble(carrier: PlayerLocal) -> void:
	if not is_instance_valid(carrier):
		return
	ImpactFeedback.rumble(carrier, 0.4, 0.8, 0.2)


func _play_dry_click(shooter: PlayerLocal) -> void:
	var feedback := CarryFeedback.from_weapon(get_parent())
	if feedback == null:
		return
	feedback.play_dry_click(shooter, _arm.global_position)
