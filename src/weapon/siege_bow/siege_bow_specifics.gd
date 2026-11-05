class_name SiegeBowSpecifics
extends Node3D
## Giant bow: the front carrier holds the grip and the back carrier holds the string.
## Moving apart draws the bow, and the back carrier's shoot button looses the arrow.
## A longer draw hits harder, flies further and pierces more enemies. After a shot, the
## carriers must come back together to nock the next arrow.

signal fired(arrow: SiegeArrow, draw: float, damage: int, pierce_hits: int, flight_range: float)

## Below this draw the string has too little tension to fire.
const MIN_DRAW := 0.25
const FULL_DRAW_CUE := 0.9
## The next arrow nocks once the carriers are this close to `min_carrier_distance`.
const NOCK_MARGIN := 0.6

const MIN_DAMAGE := 1
const MAX_DAMAGE := 3
const MAX_EXTRA_PIERCE := 3
const MIN_SPEED := 14.0
const MAX_SPEED := 30.0
const MIN_RANGE := 8.0
const MAX_RANGE := 20.0

## How far the bow and arrow sit beside the carriers, so the arrow passes the front carrier.
## Positive is the carriers' left, which leaves the front carrier on the arrow's right.
const SIDE_OFFSET := 0.9
const LIMB_LENGTH := 2.4
const LIMB_REST_ANGLE := deg_to_rad(12.0)
const LIMB_DRAWN_ANGLE := deg_to_rad(42.0)
const REST_GAP_SPEED := 8.0
const STRING_HAND_TOLERANCE := 0.1
## The string whips forward when released, and draws back more slowly as an arrow slides in.
const STRING_RELEASE_SPEED := 70.0
const STRING_NOCK_SPEED := 14.0
## A slightly underdamped spring, so released limbs flex past rest before settling.
const LIMB_SPRING_STIFFNESS := 500.0
const LIMB_SPRING_DAMPING := 22.0

const ARROW_SCENE := preload("res://src/weapon/siege_bow/siege_arrow.tscn")
const RELEASE_SOUND := preload("res://assets/sounds/slash_1.wav")
const CUE_SOUND := preload("res://assets/sounds/ammo/reload.wav")

@export var pick_and_drop_handler: PickAndDropHandler
@export var weapon_movement: WeaponMovement

@onready var _grip: Node3D = $Grip
@onready var _limb_right: Node3D = $Grip/LimbRight
@onready var _limb_left: Node3D = $Grip/LimbLeft
@onready var _string_right: Node3D = $Grip/StringRight
@onready var _string_left: Node3D = $Grip/StringLeft
@onready var _nocked_arrow: Node3D = $Grip/NockedArrow
@onready var _aim_guide: Node3D = $Grip/AimGuide
@onready var _handle_front: Node3D = $Grip/HandleFront
@onready var _handle_back: Node3D = $Grip/HandleBack

var _visual_gap := 0.0
var _shooter_z := 0.0
var _rest_gap := 0.0
var _is_nocked := true
var _is_full_draw_cued := false
## How far behind the grip the middle of the string is. It holds the arrow's tail when nocked.
var _string_z := 0.0
var _limb_flex := 0.0
var _limb_flex_speed := 0.0


func _ready() -> void:
	_shooter_z = pick_and_drop_handler.shooter_position_marker.position.z
	var setter_z := pick_and_drop_handler.direction_setter_position_marker.position.z
	_rest_gap = setter_z - _shooter_z
	_visual_gap = _rest_gap
	_string_z = -_rest_gap
	_limb_flex = get_draw(_rest_gap)
	_apply_pose()


func _physics_process(delta: float) -> void:
	var carry_info := pick_and_drop_handler.get_carry_info()
	if not _is_carried_by_both(carry_info):
		_is_full_draw_cued = false
		_visual_gap = move_toward(_visual_gap, _rest_gap, REST_GAP_SPEED * delta)
		_update_string_and_limbs(delta)
		_apply_pose()
		return
	var gap := _get_carrier_gap(carry_info)
	_visual_gap = gap
	_update_nock(gap)
	_update_full_draw_cue(gap)
	_try_fire(carry_info.main_carrier, gap)
	_update_string_and_limbs(delta)
	_apply_pose()


func is_nocked() -> bool:
	return _is_nocked


func get_draw(gap: float) -> float:
	return clampf(inverse_lerp(weapon_movement.min_carrier_distance, weapon_movement.max_carrier_distance, gap), 0.0, 1.0)


func _is_carried_by_both(carry_info: CarryInfo) -> bool:
	return is_instance_valid(carry_info.main_carrier) and is_instance_valid(carry_info.secondary_carrier)


func _get_carrier_gap(carry_info: CarryInfo) -> float:
	var between := carry_info.secondary_carrier.global_position - carry_info.main_carrier.global_position
	return Vector2(between.x, between.z).length()


func _update_nock(gap: float) -> void:
	if _is_nocked:
		return
	if gap > weapon_movement.min_carrier_distance + NOCK_MARGIN:
		return
	_is_nocked = true
	ImpactFeedback.play_sfx(CUE_SOUND, _grip.global_position, 0.9, -6.0)


func _update_full_draw_cue(gap: float) -> void:
	if not _is_nocked or get_draw(gap) < FULL_DRAW_CUE:
		_is_full_draw_cued = false
		return
	if _is_full_draw_cued:
		return
	_is_full_draw_cued = true
	ImpactFeedback.play_sfx(CUE_SOUND, _grip.global_position, 1.3, -6.0)


func _try_fire(shooter: PlayerLocal, gap: float) -> void:
	if GameplayInput.is_locked():
		return
	if not Input.is_action_just_pressed(shooter.action_shoot):
		return
	var draw := get_draw(gap)
	if not _is_nocked or draw < MIN_DRAW:
		_play_dry_click(shooter)
		return
	_fire(draw)


func _fire(draw: float) -> void:
	var power := inverse_lerp(MIN_DRAW, 1.0, draw)
	var damage := roundi(lerpf(MIN_DAMAGE, MAX_DAMAGE, power))
	var pierce_hits := 1 + roundi(MAX_EXTRA_PIERCE * power)
	var flight_range := lerpf(MIN_RANGE, MAX_RANGE, power)
	var forward := global_basis.z.normalized()
	var arrow := ARROW_SCENE.instantiate() as SiegeArrow
	get_tree().current_scene.add_child(arrow)
	arrow.launch(
		_grip.to_global(Vector3(0.0, 0.0, _string_z)),
		_grip.global_position,
		forward,
		lerpf(MIN_SPEED, MAX_SPEED, power),
		flight_range,
		damage,
		pierce_hits
	)
	_is_nocked = false
	_is_full_draw_cued = false
	_play_release_feedback(power)
	fired.emit(arrow, draw, damage, pierce_hits, flight_range)


func _play_release_feedback(power: float) -> void:
	ImpactFeedback.play_sfx(RELEASE_SOUND, _grip.global_position, lerpf(1.2, 0.75, power), 0.0)
	CameraFeedback.add_trauma_shot()
	var carry_info := pick_and_drop_handler.get_carry_info()
	ImpactFeedback.rumble(carry_info.main_carrier, 0.3, 0.7, 0.15)
	ImpactFeedback.rumble(carry_info.secondary_carrier, 0.3, 0.7, 0.15)


func _play_dry_click(shooter: PlayerLocal) -> void:
	var feedback := CarryFeedback.from_weapon(get_parent())
	if feedback == null:
		return
	feedback.play_dry_click(shooter, _grip.global_position)


func _update_string_and_limbs(delta: float) -> void:
	if _is_nocked:
		_string_z = move_toward(_string_z, -_visual_gap, STRING_NOCK_SPEED * delta)
		_limb_flex = get_draw(-_string_z)
		_limb_flex_speed = 0.0
		return
	_limb_flex_speed += (-LIMB_SPRING_STIFFNESS * _limb_flex - LIMB_SPRING_DAMPING * _limb_flex_speed) * delta
	_limb_flex += _limb_flex_speed * delta
	var tip_z := _limb_tip(_get_limb_angle(), 1.0).z
	_string_z = move_toward(_string_z, tip_z, STRING_RELEASE_SPEED * delta)


func _get_limb_angle() -> float:
	return lerpf(LIMB_REST_ANGLE, LIMB_DRAWN_ANGLE, _limb_flex)


func _apply_pose() -> void:
	# The weapon is anchored to the shooter, so the grip follows the front carrier's distance.
	_grip.position = Vector3(SIDE_OFFSET, 0.0, _shooter_z + _visual_gap)
	var limb_angle := _get_limb_angle()
	_limb_right.rotation.y = limb_angle
	_limb_left.rotation.y = -limb_angle
	var nock := Vector3(0.0, 0.0, _string_z)
	_pose_string(_string_right, _limb_tip(limb_angle, 1.0), nock)
	_pose_string(_string_left, _limb_tip(limb_angle, -1.0), nock)
	_nocked_arrow.visible = _is_nocked
	_nocked_arrow.position.z = _string_z
	_pose_aim_guide(get_draw(_visual_gap))
	_pose_side_handle(_handle_front, 0.0)
	_pose_side_handle(_handle_back, -_visual_gap)
	_handle_back.visible = _is_string_in_back_hand()


## The back carrier lets go on release and takes the string again once it has come back.
func _is_string_in_back_hand() -> bool:
	return _is_nocked and absf(_string_z + _visual_gap) < STRING_HAND_TOLERANCE


func _limb_tip(limb_angle: float, side: float) -> Vector3:
	return Vector3(side * LIMB_LENGTH * cos(limb_angle), 0.0, -LIMB_LENGTH * sin(limb_angle))


func _pose_string(string: Node3D, from: Vector3, to: Vector3) -> void:
	var along := to - from
	string.position = (from + to) * 0.5
	string.basis = Basis.looking_at(along.normalized(), Vector3.UP)
	string.scale = Vector3(1.0, 1.0, along.length())


## Bridges the sideways gap between a carrier and the bow's centre line.
func _pose_side_handle(handle: Node3D, z: float) -> void:
	handle.position = Vector3(-SIDE_OFFSET * 0.5, 0.0, z)
	handle.scale.x = SIDE_OFFSET


## A strip on the ground showing how far the arrow would fly right now.
func _pose_aim_guide(draw: float) -> void:
	_aim_guide.visible = _is_nocked and draw >= MIN_DRAW
	if not _aim_guide.visible:
		return
	var flight_range := lerpf(MIN_RANGE, MAX_RANGE, inverse_lerp(MIN_DRAW, 1.0, draw))
	_aim_guide.position.z = flight_range * 0.5
	_aim_guide.scale.z = flight_range
