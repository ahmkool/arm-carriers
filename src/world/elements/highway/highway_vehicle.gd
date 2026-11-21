class_name HighwayVehicle
extends Node3D
## A flat-roofed highway vehicle built on AnimatableBody3D so players can stand, aim, and
## carry the Fork Cannon on its roof while it changes lanes, overtakes, or brakes.
##
## Physics safety guarantee: the walkable roof collider stays strictly flat at Y = 0.0 at all
## times. Suspension bounce, road vibration, and accel/brake pitch are applied strictly to the
## Visual child node so players never snag when crossing between adjacent cars.

signal move_finished(vehicle: HighwayVehicle)

enum Archetype {
	BOX_TRUCK,
	EXPRESS_BUS,
	ARMORED_VAN,
	SEMI_TRAILER,
	CONVOY_CARRIER,
}

enum TransferSide {
	NONE,
	LEFT,
	RIGHT,
	FRONT,
	BACK,
}

## Horizontal physics lip added to each edge of the roof collider. When two vehicles dock with a
## 0.48 m visual gap, the remaining 0.08 m crack is far narrower than the player's 0.52 m capsule,
## allowing snag-free crossing while open edges still drop players onto the highway below.
const COLLISION_LIP := 0.20
const OFFSTAGE_POS := Vector3(0.0, -500.0, 260.0)
const ROAD_Y := -3.0
const WHEEL_RADIUS := 0.56
const SWAY_EASE_IN_SEC := 1.2

@export var archetype: Archetype = Archetype.BOX_TRUCK
@export var roof_width: float = 7.0
@export var roof_length: float = 14.0
@export var body_color: Color = Color(0.86, 0.42, 0.14)
@export var roof_color: Color = Color(0.76, 0.78, 0.82)
@export var stripe_color: Color = Color(0.96, 0.84, 0.28)
@export var highway_speed: float = 38.0

var body: AnimatableBody3D
var deck: MovingFloor
var _visual: Node3D
var _wheels: Array[Node3D] = []
var _headlights: Array[SpotLight3D] = []
var _taillight_mat: StandardMaterial3D
var _signal_left_mat: StandardMaterial3D
var _signal_right_mat: StandardMaterial3D
var _trim_mat: StandardMaterial3D
var _transfer_root: Node3D
var _transfer_chevrons: Array[Node3D] = []
var _transfer_mat: StandardMaterial3D
var _warning_smoke: GPUParticles3D

var _built := false
var _moving := false
var _move_from := Vector3.ZERO
var _move_to := Vector3.ZERO
var _move_elapsed := 0.0
var _move_duration := 1.0
var _falling_back := false

var _swaying := false
var _sway_center := Vector3.ZERO
var _sway_amplitude := 0.0
var _sway_period := 4.0
var _sway_time := 0.0

var _turn_signal := 0  # -1 = left, 0 = off, +1 = right
var _braking := false
var _warning := false
var _transfer_side: TransferSide = TransferSide.NONE
var _anim_time := 0.0
var _bob_phase := 0.0
var _prev_body_pos := Vector3.ZERO


func _ready() -> void:
	_bob_phase = randf() * TAU
	ensure_built()


func ensure_built() -> void:
	if _built:
		return
	_built = true
	_build_vehicle()
	_prev_body_pos = body.position


func _physics_process(delta: float) -> void:
	if not _built:
		return
	_anim_time += delta
	_step_kinematic_motion(delta)
	_animate_visuals(delta)


func _step_kinematic_motion(delta: float) -> void:
	if _moving:
		_move_elapsed = minf(_move_elapsed + delta, _move_duration)
		var t := _move_elapsed / maxf(_move_duration, 0.001)
		var eased := t * t if _falling_back else smoothstep(0.0, 1.0, t)
		body.position = _move_from.lerp(_move_to, eased)
		if _move_elapsed >= _move_duration:
			_moving = false
			_turn_signal = 0
			if _falling_back:
				_falling_back = false
				set_active(false)
			move_finished.emit(self)
		return

	if _swaying:
		_sway_time += delta
		var reach := _sway_amplitude * smoothstep(0.0, SWAY_EASE_IN_SEC, _sway_time)
		body.position = _sway_center + Vector3.RIGHT * sin(_sway_time * TAU / _sway_period) * reach


func _animate_visuals(delta: float) -> void:
	if not visible:
		return

	# Spin wheels at road speed (relative velocity adjusts spin slightly).
	var rel_vel := (body.position - _prev_body_pos) / maxf(delta, 0.0001)
	_prev_body_pos = body.position
	var effective_speed := maxf(highway_speed - rel_vel.z, 6.0)
	var wheel_spin := (effective_speed / WHEEL_RADIUS) * delta
	for wheel in _wheels:
		wheel.rotate_x(-wheel_spin)

	# Visual-only suspension bounce, subtle road chatter, and gentle lane-change roll.
	# Kept compact so long truck roofs stay flush with player feet and deck telegraphs.
	var bob_y := sin(_anim_time * 7.5 + _bob_phase) * 0.018 + sin(_anim_time * 19.0 + _bob_phase) * 0.007
	var target_roll := clampf(-rel_vel.x * 0.006, -0.026, 0.026)
	var target_pitch := clampf(-rel_vel.z * 0.0025, -0.014, 0.014)
	if _braking:
		target_pitch = -0.014
	_visual.position.y = bob_y
	_visual.rotation.z = lerpf(_visual.rotation.z, target_roll, clampf(delta * 8.0, 0.0, 1.0))
	_visual.rotation.x = lerpf(_visual.rotation.x, target_pitch, clampf(delta * 8.0, 0.0, 1.0))

	# Taillight intensity (flares crimson when braking or falling back).
	if _taillight_mat != null:
		_taillight_mat.albedo_color = Color(3.6, 0.16, 0.12) if _braking else Color(1.4, 0.16, 0.14)

	# Blinking turn signals or hazard flashers.
	var blink_on := fmod(_anim_time, 0.44) < 0.22
	var left_lit := (_turn_signal < 0 or _warning) and blink_on
	var right_lit := (_turn_signal > 0 or _warning) and blink_on
	if _signal_left_mat != null:
		_signal_left_mat.albedo_color = Color(2.4, 1.35, 0.12) if left_lit else Color(0.32, 0.20, 0.05)
	if _signal_right_mat != null:
		_signal_right_mat.albedo_color = Color(2.4, 1.35, 0.12) if right_lit else Color(0.32, 0.20, 0.05)

	# Roof border trim pulses amber/red when warning that this vehicle is about to drop back.
	if _trim_mat != null:
		if _warning:
			var pulse := 0.5 + 0.5 * sin(_anim_time * 12.0)
			_trim_mat.albedo_color = Color(0.95, 0.25, 0.15).lerp(Color(1.9, 0.95, 0.2), pulse)
		else:
			_trim_mat.albedo_color = stripe_color

	# Animate glowing transfer chevrons pointing across the active boarding edge.
	if _transfer_root != null and _transfer_root.visible:
		var pulse := 0.55 + 0.45 * sin(_anim_time * 7.0)
		_transfer_mat.albedo_color = Color(0.25, 1.35, 1.05).lerp(Color(0.55, 2.1, 1.45), pulse)
		var slide := fmod(_anim_time * 1.8, 1.0)
		for idx in _transfer_chevrons.size():
			var chev := _transfer_chevrons[idx]
			var base_offset: Vector3 = chev.get_meta("base_pos", Vector3.ZERO)
			var push_dir: Vector3 = chev.get_meta("push_dir", Vector3.RIGHT)
			chev.position = base_offset + push_dir * (slide * 0.42)


# ---- Control API ----

func set_active(active: bool) -> void:
	ensure_built()
	visible = active
	for light in _headlights:
		light.visible = active
	var shape := body.get_node_or_null("RoofCollider") as CollisionShape3D
	if shape != null:
		shape.disabled = not active
	if not active:
		_moving = false
		_swaying = false
		_falling_back = false
		_braking = false
		_turn_signal = 0
		set_warning(false)
		set_transfer_side(TransferSide.NONE)
		_teleport_body(OFFSTAGE_POS)


func snap_to(world_pos: Vector3) -> void:
	ensure_built()
	_moving = false
	_swaying = false
	_falling_back = false
	_braking = false
	_turn_signal = 0
	_teleport_body(world_pos - global_position)


## Atomically places an off-screen vehicle at `from_world_pos` BEFORE making it visible,
## then smoothly drives it to `to_world_pos`. Prevents any 1-frame flash or physics ghosting.
func spawn_and_drive(from_world_pos: Vector3, to_world_pos: Vector3, duration: float, turn_signal: int = 0) -> void:
	ensure_built()
	snap_to(from_world_pos)
	set_active(true)
	drive_to(to_world_pos, duration, turn_signal)


func _teleport_body(local_pos: Vector3) -> void:
	body.constant_linear_velocity = Vector3.ZERO
	body.position = local_pos
	body.force_update_transform()
	body.reset_physics_interpolation()
	_prev_body_pos = local_pos
	if _visual != null:
		_visual.position = Vector3.ZERO
		_visual.rotation = Vector3.ZERO


func get_deck_world_position() -> Vector3:
	ensure_built()
	return body.global_position


## Returns the visual roof container so ground telegraphs can match suspension bounce/tilt cleanly.
func get_visual_surface_node() -> Node3D:
	ensure_built()
	return _visual


## Returns a world transform sitting strictly flush and parallel to the visible roof at `height_above_roof`.
func get_roof_indicator_transform(local_offset: Vector3, height_above_roof: float = 0.07) -> Transform3D:
	ensure_built()
	var local_pt := Vector3(local_offset.x, height_above_roof, local_offset.z)
	var world_pt := _visual.to_global(local_pt)
	return Transform3D(_visual.global_basis.orthonormalized(), world_pt)


func is_moving() -> bool:
	return _moving


func is_falling_back() -> bool:
	return _falling_back


func drive_to(world_target: Vector3, duration: float, turn_signal: int = 0) -> void:
	ensure_built()
	set_active(true)
	_swaying = false
	_falling_back = false
	_braking = false
	_move_from = body.position
	_move_to = world_target - global_position
	_move_elapsed = 0.0
	_move_duration = maxf(duration, 0.05)
	_turn_signal = turn_signal
	_moving = true


func start_sway(amplitude_x: float, period: float) -> void:
	ensure_built()
	_moving = false
	_sway_center = body.position
	_sway_amplitude = amplitude_x
	_sway_period = maxf(period, 0.5)
	_sway_time = 0.0
	_swaying = true


func stop_sway() -> void:
	_swaying = false


func start_fall_back(target_world_z: float, duration: float = 2.8, drift_x: float = 0.0) -> void:
	ensure_built()
	set_transfer_side(TransferSide.NONE)
	set_warning(false)
	_swaying = false
	_braking = true
	_turn_signal = 0
	_falling_back = true
	_move_from = body.position
	_move_to = Vector3(body.position.x + drift_x, 0.0, target_world_z - global_position.z)
	_move_elapsed = 0.0
	_move_duration = maxf(duration, 0.25)
	_moving = true


func set_warning(enabled: bool) -> void:
	_warning = enabled
	if _warning_smoke != null:
		_warning_smoke.emitting = enabled


func set_transfer_side(side: TransferSide) -> void:
	_transfer_side = side
	if _transfer_root == null:
		return
	if side == TransferSide.NONE:
		_transfer_root.visible = false
		return
	_transfer_root.visible = true
	_rebuild_transfer_chevrons(side)


func contains_player(player: PlayerLocal, margin: float = 0.15) -> bool:
	if not visible or deck == null:
		return false
	return deck.contains(player.global_position, margin)


# ---- Procedural Vehicle Construction ----

func _build_vehicle() -> void:
	body = AnimatableBody3D.new()
	body.name = "AnimatableBody3D"
	body.collision_layer = 4
	body.collision_mask = 0
	# Keep sync_to_physics off so teleports update PhysicsServer3D immediately.
	# AnimatableBody3D automatically computes kinematic platform velocity from body.position changes.
	body.sync_to_physics = false
	body.set_meta(&"footstep_surface", &"metal")
	add_child(body)

	# Walkable flat roof collider — top strictly at Y = 0.0.
	var collider := CollisionShape3D.new()
	collider.name = "RoofCollider"
	var shape := BoxShape3D.new()
	shape.size = Vector3(roof_width + COLLISION_LIP * 2.0, 0.5, roof_length + COLLISION_LIP * 2.0)
	collider.shape = shape
	collider.position = Vector3(0.0, -0.25, 0.0)
	body.add_child(collider)

	# MovingFloor metadata node so future enemies/bosses recognize this moving roof.
	deck = MovingFloor.new()
	deck.name = "MovingFloor"
	deck.size = Vector2(roof_width, roof_length)
	body.add_child(deck)

	_visual = Node3D.new()
	_visual.name = "Visual"
	body.add_child(_visual)

	var mat_body := _make_mat(body_color, 0.32, 0.42)
	var mat_roof := _make_mat(roof_color, 0.18, 0.58)
	var mat_dark := _make_mat(Color(0.11, 0.12, 0.15), 0.45, 0.55)
	var mat_chrome := _make_mat(Color(0.76, 0.80, 0.86), 0.82, 0.22)
	var mat_glass := _make_mat(Color(0.12, 0.24, 0.36), 0.72, 0.14)
	mat_glass.emission_enabled = true
	mat_glass.emission = Color(0.08, 0.18, 0.28)
	mat_glass.emission_energy_multiplier = 0.45

	var mat_headlight := StandardMaterial3D.new()
	mat_headlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat_headlight.albedo_color = Color(2.1, 1.95, 1.45)

	_taillight_mat = StandardMaterial3D.new()
	_taillight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_taillight_mat.albedo_color = Color(1.4, 0.16, 0.14)

	_signal_left_mat = StandardMaterial3D.new()
	_signal_left_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_signal_left_mat.albedo_color = Color(0.32, 0.20, 0.05)

	_signal_right_mat = StandardMaterial3D.new()
	_signal_right_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_signal_right_mat.albedo_color = Color(0.32, 0.20, 0.05)

	_trim_mat = StandardMaterial3D.new()
	_trim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trim_mat.albedo_color = stripe_color

	_build_flat_roof(mat_roof, mat_dark)
	_build_chassis(mat_body, mat_dark, mat_chrome, mat_glass, mat_headlight)
	_build_wheels(mat_dark, mat_chrome)
	_build_headlight_beams()
	_build_transfer_indicator()
	_build_warning_smoke()


func _build_flat_roof(mat_roof: StandardMaterial3D, mat_dark: StandardMaterial3D) -> void:
	# Main flat walkable roof plate: top sits at Y = 0.0.
	var roof := _add_box(_visual, Vector3(roof_width, 0.24, roof_length), Vector3(0.0, -0.12, 0.0), mat_roof)
	roof.name = "FlatRoof"

	# Flush roof trim strips outlining the playable perimeter.
	var trim_h := 0.03
	var trim_w := 0.14
	_add_box(_visual, Vector3(roof_width + 0.04, trim_h, trim_w), Vector3(0.0, 0.005, -roof_length * 0.5 + trim_w * 0.5), _trim_mat, false)
	_add_box(_visual, Vector3(roof_width + 0.04, trim_h, trim_w), Vector3(0.0, 0.005, roof_length * 0.5 - trim_w * 0.5), _trim_mat, false)
	_add_box(_visual, Vector3(trim_w, trim_h, roof_length), Vector3(-roof_width * 0.5 + trim_w * 0.5, 0.005, 0.0), _trim_mat, false)
	_add_box(_visual, Vector3(trim_w, trim_h, roof_length), Vector3(roof_width * 0.5 - trim_w * 0.5, 0.005, 0.0), _trim_mat, false)

	# Subtle flush panel seams across the roof so players read vehicle scale & roof grip.
	var rib_count := maxi(int(roof_length / 3.2), 2)
	for i in range(1, rib_count):
		var z := lerpf(-roof_length * 0.44, roof_length * 0.44, float(i) / float(rib_count))
		_add_box(_visual, Vector3(roof_width - 0.6, 0.015, 0.12), Vector3(0.0, 0.004, z), mat_dark, false)

	# Stylized flat center stripe or roof hatch detail (flush, zero obstruction).
	if archetype == Archetype.CONVOY_CARRIER:
		_add_box(_visual, Vector3(0.28, 0.015, roof_length - 1.4), Vector3(0.0, 0.006, 0.0), _trim_mat, false)
		_add_box(_visual, Vector3(roof_width - 2.0, 0.015, 0.28), Vector3(0.0, 0.006, 0.0), _trim_mat, false)
	elif archetype == Archetype.EXPRESS_BUS:
		for z_off: float in [-roof_length * 0.25, roof_length * 0.22]:
			_add_box(_visual, Vector3(roof_width * 0.52, 0.025, 2.2), Vector3(0.0, 0.008, z_off), mat_dark, false)


func _build_chassis(
	mat_body: StandardMaterial3D,
	mat_dark: StandardMaterial3D,
	mat_chrome: StandardMaterial3D,
	mat_glass: StandardMaterial3D,
	mat_headlight: StandardMaterial3D,
) -> void:
	var body_h := 2.22
	var body_y := -0.24 - body_h * 0.5
	var body_w := roof_width - 0.12
	var body_l := roof_length - 0.12

	# Main hull below the flat roof.
	_add_box(_visual, Vector3(body_w, body_h, body_l), Vector3(0.0, body_y, 0.0), mat_body)

	# Lower dark armored skirt / undercarriage.
	_add_box(_visual, Vector3(body_w - 0.3, 0.42, body_l - 0.2), Vector3(0.0, -2.42, 0.0), mat_dark)

	# Bold side accent stripe along both flanks.
	var stripe_mat := _make_mat(stripe_color, 0.25, 0.4)
	for side: float in [-1.0, 1.0]:
		_add_box(_visual, Vector3(0.10, 0.34, body_l - 0.3), Vector3(side * (body_w * 0.5 + 0.02), -1.35, 0.0), stripe_mat, false)

	# Archetype-specific silhouette details (all strictly below Y = -0.35 so roof stays 100% flat!).
	var nose_z := -roof_length * 0.5
	match archetype:
		Archetype.BOX_TRUCK:
			# Forward truck cab protruding ahead of the cargo box, below roof height.
			var cab_len := 2.4
			var cab_z := nose_z - cab_len * 0.5 + 0.1
			_add_box(_visual, Vector3(body_w * 0.86, 1.85, cab_len), Vector3(0.0, -1.52, cab_z), mat_body)
			_add_box(_visual, Vector3(body_w * 0.78, 0.72, 0.18), Vector3(0.0, -1.12, cab_z - cab_len * 0.5 - 0.02), mat_glass, false)
			_add_box(_visual, Vector3(body_w * 0.62, 0.45, 0.16), Vector3(0.0, -1.85, cab_z - cab_len * 0.5 - 0.04), mat_chrome, false)
			nose_z = cab_z - cab_len * 0.5
		Archetype.SEMI_TRAILER:
			# Big 18-wheeler tractor cab ahead of the container trailer + dual chrome exhaust stacks.
			var cab_len := 3.4
			var cab_z := nose_z - cab_len * 0.5 + 0.1
			var cab_mat := _make_mat(body_color.darkened(0.22), 0.42, 0.36)
			_add_box(_visual, Vector3(body_w * 0.84, 1.92, cab_len), Vector3(0.0, -1.50, cab_z), cab_mat)
			_add_box(_visual, Vector3(body_w * 0.76, 0.68, 0.18), Vector3(0.0, -1.08, cab_z - cab_len * 0.5 - 0.02), mat_glass, false)
			_add_box(_visual, Vector3(body_w * 0.58, 0.62, 0.22), Vector3(0.0, -1.86, cab_z - cab_len * 0.5 - 0.05), mat_chrome, false)
			# Dual chrome exhaust stacks behind tractor cab (outside roof width, below roof).
			for side: float in [-1.0, 1.0]:
				var stack := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = 0.14
				cyl.bottom_radius = 0.14
				cyl.height = 1.9
				cyl.radial_segments = 10
				cyl.material = mat_chrome
				stack.mesh = cyl
				stack.position = Vector3(side * (body_w * 0.46), -1.15, nose_z - 0.35)
				_visual.add_child(stack)
			nose_z = cab_z - cab_len * 0.5
		Archetype.EXPRESS_BUS:
			# Long glowing row of transit bus side windows + front panoramic windshield.
			var win_mat := StandardMaterial3D.new()
			win_mat.albedo_color = Color(0.96, 0.88, 0.68)
			win_mat.emission_enabled = true
			win_mat.emission = Color(0.98, 0.82, 0.45)
			win_mat.emission_energy_multiplier = 0.85
			var win_count := maxi(int(body_l / 2.6), 4)
			for i in win_count:
				var wz := lerpf(-body_l * 0.38, body_l * 0.38, float(i) / maxf(float(win_count - 1), 1.0))
				for side: float in [-1.0, 1.0]:
					_add_box(_visual, Vector3(0.12, 0.72, 1.55), Vector3(side * (body_w * 0.5 + 0.02), -0.92, wz), win_mat, false)
			_add_box(_visual, Vector3(body_w * 0.86, 0.92, 0.18), Vector3(0.0, -1.05, nose_z - 0.02), mat_glass, false)
			# Glowing cyan route destination strip above windshield.
			var sign_mat := StandardMaterial3D.new()
			sign_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sign_mat.albedo_color = Color(0.35, 1.5, 1.8)
			_add_box(_visual, Vector3(body_w * 0.55, 0.24, 0.14), Vector3(0.0, -0.46, nose_z - 0.04), sign_mat, false)
		Archetype.ARMORED_VAN:
			# Sloped armored nose + heavy front bullbar.
			var hood_len := 1.75
			var hood_z := nose_z - hood_len * 0.5 + 0.1
			_add_box(_visual, Vector3(body_w * 0.90, 1.42, hood_len), Vector3(0.0, -1.72, hood_z), mat_body)
			_add_box(_visual, Vector3(body_w * 0.82, 0.68, 0.18), Vector3(0.0, -0.82, nose_z - 0.04), mat_glass, false)
			_add_box(_visual, Vector3(body_w * 0.78, 0.45, 0.28), Vector3(0.0, -1.96, hood_z - hood_len * 0.5 - 0.12), mat_chrome, false)
			nose_z = hood_z - hood_len * 0.5
		Archetype.CONVOY_CARRIER:
			# Armored twin-bridge nose + side thruster/bumper guards.
			var bridge_len := 2.6
			var bridge_z := nose_z - bridge_len * 0.5 + 0.15
			_add_box(_visual, Vector3(body_w * 0.82, 1.80, bridge_len), Vector3(0.0, -1.55, bridge_z), mat_body)
			_add_box(_visual, Vector3(body_w * 0.74, 0.58, 0.22), Vector3(0.0, -1.08, bridge_z - bridge_len * 0.5 - 0.02), mat_glass, false)
			_add_box(_visual, Vector3(body_w * 0.94, 0.46, 0.42), Vector3(0.0, -2.08, bridge_z - bridge_len * 0.5 - 0.14), mat_chrome, false)
			nose_z = bridge_z - bridge_len * 0.5

	# Front chrome bumper + glowing dual headlights.
	var front_w := body_w * 0.86
	_add_box(_visual, Vector3(front_w + 0.2, 0.34, 0.30), Vector3(0.0, -2.26, nose_z - 0.08), mat_chrome, false)
	for side: float in [-1.0, 1.0]:
		_add_box(_visual, Vector3(0.75, 0.34, 0.16), Vector3(side * (front_w * 0.34), -1.86, nose_z - 0.06), mat_headlight, false)
		var sig_mat := _signal_left_mat if side < 0.0 else _signal_right_mat
		_add_box(_visual, Vector3(0.32, 0.26, 0.20), Vector3(side * (front_w * 0.48), -1.86, nose_z - 0.04), sig_mat, false)

	# Rear bumper + dual brake lights + rear turn signals (clearly visible from overhead camera!).
	var rear_z := roof_length * 0.5
	_add_box(_visual, Vector3(body_w + 0.12, 0.34, 0.30), Vector3(0.0, -2.26, rear_z + 0.08), mat_chrome, false)
	for side: float in [-1.0, 1.0]:
		_add_box(_visual, Vector3(0.95, 0.38, 0.18), Vector3(side * (body_w * 0.32), -1.65, rear_z + 0.04), _taillight_mat, false)
		var sig_mat := _signal_left_mat if side < 0.0 else _signal_right_mat
		_add_box(_visual, Vector3(0.38, 0.34, 0.20), Vector3(side * (body_w * 0.45), -1.65, rear_z + 0.05), sig_mat, false)


func _build_wheels(mat_tire: StandardMaterial3D, mat_rim: StandardMaterial3D) -> void:
	var axle_z: Array[float] = []
	var half_l := roof_length * 0.5
	match archetype:
		Archetype.SEMI_TRAILER, Archetype.CONVOY_CARRIER:
			axle_z = [-half_l - 1.1, -half_l + 2.2, half_l - 3.6, half_l - 1.6]
		Archetype.EXPRESS_BUS:
			axle_z = [-half_l + 2.4, half_l - 4.2, half_l - 2.0]
		_:
			axle_z = [-half_l + 2.0, half_l - 2.2]

	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = WHEEL_RADIUS
	tire_mesh.bottom_radius = WHEEL_RADIUS
	tire_mesh.height = 0.44
	tire_mesh.radial_segments = 14
	tire_mesh.material = mat_tire

	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = WHEEL_RADIUS * 0.54
	rim_mesh.bottom_radius = WHEEL_RADIUS * 0.54
	rim_mesh.height = 0.48
	rim_mesh.radial_segments = 10
	rim_mesh.material = mat_rim

	var spoke_mesh := BoxMesh.new()
	spoke_mesh.size = Vector3(0.50, WHEEL_RADIUS * 1.45, 0.14)
	spoke_mesh.material = mat_rim

	var wheel_x := roof_width * 0.5 - 0.18
	var wheel_y := ROAD_Y + WHEEL_RADIUS

	for z in axle_z:
		for side: float in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * wheel_x, wheel_y, z)

			var tire := MeshInstance3D.new()
			tire.mesh = tire_mesh
			tire.rotation.z = PI * 0.5
			pivot.add_child(tire)

			var rim := MeshInstance3D.new()
			rim.mesh = rim_mesh
			rim.rotation.z = PI * 0.5
			pivot.add_child(rim)

			var spoke := MeshInstance3D.new()
			spoke.mesh = spoke_mesh
			pivot.add_child(spoke)

			_visual.add_child(pivot)
			_wheels.append(pivot)


func _build_headlight_beams() -> void:
	# Real warm SpotLight3D headlights illuminating the scrolling asphalt ahead.
	var front_z := -roof_length * 0.5
	match archetype:
		Archetype.BOX_TRUCK:
			front_z -= 2.35
		Archetype.SEMI_TRAILER:
			front_z -= 3.35
		Archetype.ARMORED_VAN:
			front_z -= 1.70
		Archetype.CONVOY_CARRIER:
			front_z -= 2.50

	var beam_x := (roof_width - 0.12) * 0.86 * 0.34
	for side: float in [-1.0, 1.0]:
		var spot := SpotLight3D.new()
		spot.name = "HeadlightLeft" if side < 0.0 else "HeadlightRight"
		spot.position = Vector3(side * beam_x, -1.82, front_z - 0.18)
		spot.rotation_degrees = Vector3(-15.0, side * -3.5, 0.0)
		spot.light_color = Color(1.0, 0.93, 0.78)
		spot.light_energy = 7.5
		spot.spot_range = 28.0
		spot.spot_attenuation = 1.25
		spot.spot_angle = 36.0
		spot.spot_angle_attenuation = 1.4
		spot.shadow_enabled = false
		spot.visible = visible
		_visual.add_child(spot)
		_headlights.append(spot)


func _build_transfer_indicator() -> void:
	_transfer_mat = StandardMaterial3D.new()
	_transfer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_transfer_mat.albedo_color = Color(0.35, 1.65, 1.2)

	_transfer_root = Node3D.new()
	_transfer_root.name = "TransferIndicator"
	_transfer_root.visible = false
	_visual.add_child(_transfer_root)


func _rebuild_transfer_chevrons(side: TransferSide) -> void:
	for child in _transfer_root.get_children():
		child.queue_free()
	_transfer_chevrons.clear()

	var is_lr := (side == TransferSide.LEFT or side == TransferSide.RIGHT)
	var sign_dir := -1.0 if (side == TransferSide.LEFT or side == TransferSide.FRONT) else 1.0
	var edge_len := roof_length * 0.74 if is_lr else roof_width * 0.74

	# Bright glowing edge strip along the safe boarding side.
	var bar_size := Vector3(0.28, 0.04, edge_len) if is_lr else Vector3(edge_len, 0.04, 0.28)
	var bar_pos := Vector3(sign_dir * (roof_width * 0.5 - 0.12), 0.025, 0.0) if is_lr \
		else Vector3(0.0, 0.025, sign_dir * (roof_length * 0.5 - 0.12))
	_add_box(_transfer_root, bar_size, bar_pos, _transfer_mat, false)

	# 3 animated arrow chevrons pointing onto the docked vehicle.
	var push_dir := Vector3(sign_dir, 0.0, 0.0) if is_lr else Vector3(0.0, 0.0, sign_dir)
	var yaw := 0.0
	if side == TransferSide.RIGHT:
		yaw = 0.0
	elif side == TransferSide.LEFT:
		yaw = PI
	elif side == TransferSide.FRONT:
		yaw = PI * 0.5
	elif side == TransferSide.BACK:
		yaw = -PI * 0.5

	for idx in 3:
		var along := lerpf(-edge_len * 0.34, edge_len * 0.34, float(idx) / 2.0)
		var base := Vector3(sign_dir * (roof_width * 0.5 - 0.95), 0.035, along) if is_lr \
			else Vector3(along, 0.035, sign_dir * (roof_length * 0.5 - 0.95))

		var chev := Node3D.new()
		chev.position = base
		chev.rotation.y = yaw
		chev.set_meta("base_pos", base)
		chev.set_meta("push_dir", push_dir)

		# V-shaped chevron pointing along +X in local space.
		var leg_a := _add_box(chev, Vector3(0.72, 0.04, 0.16), Vector3(0.0, 0.0, -0.22), _transfer_mat, false)
		leg_a.rotation.y = -0.62
		var leg_b := _add_box(chev, Vector3(0.72, 0.04, 0.16), Vector3(0.0, 0.0, 0.22), _transfer_mat, false)
		leg_b.rotation.y = 0.62

		_transfer_root.add_child(chev)
		_transfer_chevrons.append(chev)


func _build_warning_smoke() -> void:
	# Smoke streaming backward from the engine/roof edge when the car is about to peel off.
	_warning_smoke = GPUParticles3D.new()
	_warning_smoke.name = "WarningSmoke"
	_warning_smoke.position = Vector3(0.0, -0.6, -roof_length * 0.5 - 0.5)
	_warning_smoke.emitting = false
	_warning_smoke.amount = 28
	_warning_smoke.lifetime = 0.9

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(roof_width * 0.35, 0.25, 0.4)
	proc.direction = Vector3(0.0, 0.35, 1.0)
	proc.spread = 16.0
	proc.initial_velocity_min = 14.0
	proc.initial_velocity_max = 22.0
	proc.gravity = Vector3(0.0, 2.5, 0.0)
	proc.scale_min = 0.55
	proc.scale_max = 1.25
	_warning_smoke.process_material = proc

	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.albedo_color = Color(0.92, 0.42, 0.22, 0.55)

	var puff := SphereMesh.new()
	puff.radius = 0.38
	puff.height = 0.76
	puff.radial_segments = 8
	puff.rings = 4
	puff.material = smoke_mat
	_warning_smoke.draw_pass_1 = puff

	_visual.add_child(_warning_smoke)


func _make_mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = metallic
	mat.roughness = roughness
	return mat


func _add_box(
	parent: Node3D,
	size: Vector3,
	pos: Vector3,
	material: Material,
	shadows: bool = true,
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.position = pos
	if not shadows:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)
	return inst
