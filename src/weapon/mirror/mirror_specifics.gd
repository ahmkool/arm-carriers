class_name MirrorSpecifics
extends Node3D
## Rectangular arcane mirror carried between two players.
## Both carriers tilt the mirror around its lengthwise axis by holding their shoot button,
## pushing in opposite directions:
## - Shooter (player 0 / main carrier) tilts toward MAX_TILT_ANGLE (90 deg, parallel to the ground).
## - Direction setter (player 1 / secondary carrier) tilts toward MIN_TILT_ANGLE (0 deg, perpendicular to the ground).
## Holding both cancels out. While vertical (0 deg), it reflects horizontal lasers horizontally;
## tilting raises the reflection angle up into the sky (or flattens it at 90 deg to bounce overhead
## beams straight back up). Enemy fireballs that touch the glass are absorbed at the entry point,
## charge for 1.0s, and then unleash a 2.0s red laser out of that exact spot on the mirror.

signal tilt_changed(angle_radians: float)
signal fireball_absorbed(point: Vector3)

const MIN_TILT_ANGLE := 0.0
const MAX_TILT_ANGLE := PI * 0.5
## Degrees per second when one carrier holds shoot.
const TILT_SPEED_RAD := deg_to_rad(75.0)
const REST_GAP_SPEED := 8.0
const PANE_HALF_WIDTH := 1.65
const GLASS_MAX_HALF_Z := 1.46
const GLASS_MAX_HALF_Y := 0.62
const GLASS_FACE_OFFSET_X := 0.08
const MAX_ABSORBED_BEAMS := 6
const FLASH_DECAY_PER_SEC := 5.5
const LASER_GLOW_DECAY_PER_SEC := 6.0
const LASER_SPARK_INTERVAL_SEC := 0.09
const LIMIT_CLICK_COOLDOWN_SEC := 0.25

const MirrorSurfaceScript := preload("res://src/weapon/mirror/mirror_surface.gd")
const MirrorAbsorbedBeamScript := preload("res://src/weapon/mirror/mirror_absorbed_beam.gd")
const ABSORB_SOUND := preload("res://assets/sounds/metal/GridStep03.wav")
const LIMIT_SOUND := preload("res://assets/sounds/ammo/reload.wav")
const SPARKS_SCENE := preload("res://src/vfx/saw_sparks.tscn")

@export var pick_and_drop_handler: PickAndDropHandler
@export var weapon_movement: WeaponMovement

@onready var _rig: Node3D = $Rig
@onready var _mirror_pivot: Node3D = $Rig/MirrorPivot
@onready var _glass_mesh: MeshInstance3D = $Rig/MirrorPivot/Glass
@onready var _mirror_surface: MirrorSurfaceScript = $Rig/MirrorPivot/MirrorSurface
@onready var _handle_shooter: Node3D = $Rig/HandleShooter
@onready var _handle_setter: Node3D = $Rig/HandleSetter

var _tilt_angle := MIN_TILT_ANGLE
var _shooter_z := 0.0
var _rest_gap := 0.0
var _visual_gap := 0.0
var _flash := 0.0
var _laser_glow := 0.0
var _fire_charge := 0.0
var _laser_spark_cooldown := 0.0
var _limit_click_cooldown := 0.0
var _was_at_limit := true
var _glass_material: ShaderMaterial
var _absorbed_beams: Array[Node] = []


func _ready() -> void:
	add_to_group(&"checkpoint_resettable")
	_shooter_z = pick_and_drop_handler.shooter_position_marker.position.z
	var setter_z := pick_and_drop_handler.direction_setter_position_marker.position.z
	_rest_gap = setter_z - _shooter_z
	_visual_gap = _rest_gap
	_glass_material = _glass_mesh.get_active_material(0) as ShaderMaterial
	if _glass_material != null:
		_glass_material = _glass_material.duplicate() as ShaderMaterial
		_glass_mesh.material_override = _glass_material
	_mirror_surface.fireball_absorbed.connect(_on_fireball_absorbed)
	_mirror_surface.laser_reflected.connect(_on_laser_reflected)
	_apply_pose()


func reset_to_checkpoint() -> void:
	set_tilt_angle(MIN_TILT_ANGLE)
	_clear_absorbed_beams()
	_flash = 0.0
	_laser_glow = 0.0
	_fire_charge = 0.0
	_update_shader_glow()


func get_tilt_angle() -> float:
	return _tilt_angle


func get_tilt_degrees() -> float:
	return rad_to_deg(_tilt_angle)


func set_tilt_angle(radians: float) -> void:
	var clamped := clampf(radians, MIN_TILT_ANGLE, MAX_TILT_ANGLE)
	if is_equal_approx(clamped, _tilt_angle):
		return
	_tilt_angle = clamped
	_apply_tilt_transform()
	tilt_changed.emit(_tilt_angle)


func _physics_process(delta: float) -> void:
	_laser_spark_cooldown = maxf(0.0, _laser_spark_cooldown - delta)
	_limit_click_cooldown = maxf(0.0, _limit_click_cooldown - delta)
	_decay_glow(delta)
	_sync_fire_charge_glow()

	var carry_info := pick_and_drop_handler.get_carry_info()
	if not _is_carried_by_both(carry_info):
		_visual_gap = move_toward(_visual_gap, _rest_gap, REST_GAP_SPEED * delta)
		_apply_pose()
		return

	_visual_gap = _get_carrier_gap(carry_info)
	_update_tilt_input(carry_info, delta)
	_apply_pose()


func _is_carried_by_both(carry_info: CarryInfo) -> bool:
	return is_instance_valid(carry_info.main_carrier) and is_instance_valid(carry_info.secondary_carrier)


func _get_carrier_gap(carry_info: CarryInfo) -> float:
	var between := carry_info.secondary_carrier.global_position - carry_info.main_carrier.global_position
	return Vector2(between.x, between.z).length()


func _update_tilt_input(carry_info: CarryInfo, delta: float) -> void:
	if GameplayInput.is_locked():
		return
	var shooter_pressed := Input.is_action_pressed(carry_info.main_carrier.action_shoot)
	var setter_pressed := Input.is_action_pressed(carry_info.secondary_carrier.action_shoot)
	var tilt_dir := int(shooter_pressed) - int(setter_pressed)
	if tilt_dir == 0:
		return

	var prev := _tilt_angle
	var next := clampf(_tilt_angle + float(tilt_dir) * TILT_SPEED_RAD * delta, MIN_TILT_ANGLE, MAX_TILT_ANGLE)
	var at_limit := next <= MIN_TILT_ANGLE + 0.0001 or next >= MAX_TILT_ANGLE - 0.0001
	if not is_equal_approx(next, prev):
		_tilt_angle = next
		tilt_changed.emit(_tilt_angle)
		if at_limit and not _was_at_limit:
			_play_limit_feedback(carry_info)
	_was_at_limit = at_limit


func _apply_pose() -> void:
	# Anchor the mirror rig right between both carriers regardless of live spacing.
	_rig.position.z = _shooter_z + _visual_gap * 0.5
	_apply_tilt_transform()
	var half_gap := _visual_gap * 0.5
	_pose_handle(_handle_shooter, -PANE_HALF_WIDTH, -half_gap)
	_pose_handle(_handle_setter, PANE_HALF_WIDTH, half_gap)


func _apply_tilt_transform() -> void:
	if _mirror_pivot == null:
		return
	_mirror_pivot.rotation.z = _tilt_angle


## Stretches a side grip bar from the mirror frame hinge to the carrier's hands.
func _pose_handle(handle: Node3D, from_z: float, to_z: float) -> void:
	var span := absf(to_z - from_z)
	if span < 0.05:
		handle.visible = false
		return
	handle.visible = true
	handle.position = Vector3(0.0, 0.0, (from_z + to_z) * 0.5)
	handle.scale = Vector3(1.0, 1.0, span)


func _on_fireball_absorbed(point: Vector3, face_sign: float) -> void:
	_prune_absorbed_beams()
	if _absorbed_beams.size() >= MAX_ABSORBED_BEAMS:
		var oldest: Node = _absorbed_beams.pop_front() as Node
		if is_instance_valid(oldest):
			oldest.queue_free()

	var local_entry := _mirror_pivot.to_local(point)
	local_entry.x = face_sign * GLASS_FACE_OFFSET_X
	local_entry.y = clampf(local_entry.y, -GLASS_MAX_HALF_Y, GLASS_MAX_HALF_Y)
	local_entry.z = clampf(local_entry.z, -GLASS_MAX_HALF_Z, GLASS_MAX_HALF_Z)

	var beam := MirrorAbsorbedBeamScript.new()
	beam.setup(local_entry, face_sign, _mirror_surface.get_rid())
	beam.beam_fired.connect(_on_absorbed_beam_fired)
	_mirror_pivot.add_child(beam)
	_absorbed_beams.append(beam)

	_flash = 1.2
	_sync_fire_charge_glow()
	ImpactFeedback.play_sfx(ABSORB_SOUND, point, randf_range(1.6, 1.9), -5.0)
	_spawn_sparks(point, 0.85)
	CameraFeedback.add_trauma(0.18)
	_rumble_carriers(0.45, 0.25, 0.12)
	fireball_absorbed.emit(point)


func _on_absorbed_beam_fired(_origin: Vector3) -> void:
	_rumble_carriers(0.6, 0.4, 0.2)


func _on_laser_reflected(point: Vector3) -> void:
	_laser_glow = 1.0
	_update_shader_glow()
	if _laser_spark_cooldown > 0.0:
		return
	_laser_spark_cooldown = LASER_SPARK_INTERVAL_SEC
	_spawn_sparks(point, 0.35)
	_rumble_carriers(0.2, 0.08, 0.08)


func _play_limit_feedback(carry_info: CarryInfo) -> void:
	if _limit_click_cooldown > 0.0:
		return
	_limit_click_cooldown = LIMIT_CLICK_COOLDOWN_SEC
	ImpactFeedback.play_sfx(LIMIT_SOUND, _rig.global_position, 1.5, -10.0)
	ImpactFeedback.rumble(carry_info.main_carrier, 0.25, 0.1, 0.06)
	ImpactFeedback.rumble(carry_info.secondary_carrier, 0.25, 0.1, 0.06)


func _decay_glow(delta: float) -> void:
	if _flash <= 0.0 and _laser_glow <= 0.0:
		return
	_flash = maxf(0.0, _flash - FLASH_DECAY_PER_SEC * delta)
	_laser_glow = maxf(0.0, _laser_glow - LASER_GLOW_DECAY_PER_SEC * delta)
	_update_shader_glow()


func _sync_fire_charge_glow() -> void:
	_prune_absorbed_beams()
	var peak := 0.0
	for node in _absorbed_beams:
		var beam := node as MirrorAbsorbedBeamScript
		if beam != null:
			peak = maxf(peak, beam.get_charge_intensity())
	if not is_equal_approx(peak, _fire_charge):
		_fire_charge = peak
		_update_shader_glow()


func _prune_absorbed_beams() -> void:
	var alive: Array[Node] = []
	for node in _absorbed_beams:
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			alive.append(node)
	_absorbed_beams = alive


func _clear_absorbed_beams() -> void:
	for node in _absorbed_beams:
		if is_instance_valid(node):
			node.queue_free()
	_absorbed_beams.clear()


func _update_shader_glow() -> void:
	if _glass_material == null:
		return
	_glass_material.set_shader_parameter("flash", _flash)
	_glass_material.set_shader_parameter("laser_glow", _laser_glow)
	_glass_material.set_shader_parameter("fire_charge", _fire_charge)


func _spawn_sparks(at_position: Vector3, density: float) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var sparks := SPARKS_SCENE.instantiate() as GPUParticles3D
	sparks.amount_ratio = density
	scene_root.add_child(sparks)
	sparks.global_position = at_position
	sparks.emitting = true


func _rumble_carriers(weak: float, strong: float, duration_sec: float) -> void:
	var carry_info := pick_and_drop_handler.get_carry_info()
	if is_instance_valid(carry_info.main_carrier):
		ImpactFeedback.rumble(carry_info.main_carrier, weak, strong, duration_sec)
	if is_instance_valid(carry_info.secondary_carrier):
		ImpactFeedback.rumble(carry_info.secondary_carrier, weak, strong, duration_sec)
