class_name LaserDroneCannon
extends Node3D
## Articulated 3D laser turret mounted on a flying Laser Drone.
## Rotates `CannonYawPivot` (360° horizontal) and `CannonPitchPivot` (full -90°..+90° vertical
## pitch) inside the imported drone model, then fires a 3D raycast beam from `Muzzle` that
## reflects off `MirrorSurface` and can bounce back to burn the drone itself (or other enemies).

signal beam_state_changed(is_on: bool)

enum BeamMode {
	OFF,
	TELEGRAPH,
	FIRING,
}

const MirrorSurfaceScript := preload("res://src/weapon/mirror/mirror_surface.gd")
const BEAM_SHADER := preload("res://src/world/elements/azure_veil/laser_beam.gdshader")
const CHARGE_SOUND := preload("res://assets/sounds/fireball_cast.wav")
const FIRE_SOUND := preload("res://assets/sounds/slash_1.wav")
const BURN_SOUND := preload("res://assets/sounds/damage/161098__braqoon__arrow_damage.wav")
const SPARKS_SCENE := preload("res://src/vfx/saw_sparks.tscn")

## Layers: 1 (player) | 2 (enemy) | 4 (level) | 32 (bolt_mirror / MirrorSurface).
const RAY_MASK := 1 | 2 | 4 | BoltMirror.LAYER
const MAX_RAY_ATTEMPTS := 12
const BOUNCE_CLEARANCE := 0.04

@export_group("Articulation")
@export var min_pitch_degrees: float = -90.0
@export var max_pitch_degrees: float = 90.0
@export var yaw_pivot_name: StringName = &"CannonYawPivot"
@export var pitch_pivot_name: StringName = &"CannonPitchPivot"
@export var muzzle_name: StringName = &"Muzzle"

@export_group("Beam")
@export var max_range: float = 55.0
@export var max_bounces: int = 4
@export var core_radius: float = 0.08
@export var aura_radius: float = 0.22
@export var damage_per_tick: int = 1
@export var enemy_damage_interval: float = 0.25
@export var player_damage: int = 1

var _owner_enemy: EnemyLocal
var _yaw_pivot: Node3D
var _pitch_pivot: Node3D
var _muzzle: Node3D
var _muzzle_light: OmniLight3D

var _beam_mode: BeamMode = BeamMode.OFF
var _telegraph_ratio: float = 0.0
var _segments: Array[Node3D] = []
var _flares: Array[MeshInstance3D] = []
var _telegraph_line: Node3D
var _telegraph_ring: MeshInstance3D
var _beam_root: Node3D
var _enemy_burn_cooldowns: Dictionary = {}


func _ready() -> void:
	_owner_enemy = get_parent() as EnemyLocal
	_bind_model_pivots()
	_build_beam_pool()
	_hide_all_beams()


func _exit_tree() -> void:
	if is_instance_valid(_beam_root):
		_beam_root.queue_free()


func set_beam_mode(mode: BeamMode, telegraph_ratio: float = 0.0) -> void:
	var prev_mode := _beam_mode
	_beam_mode = mode
	_telegraph_ratio = clampf(telegraph_ratio, 0.0, 1.0)
	if prev_mode != mode:
		if mode == BeamMode.TELEGRAPH:
			ImpactFeedback.play_sfx(CHARGE_SOUND, get_muzzle_position(), 1.75, -12.0)
		elif mode == BeamMode.FIRING:
			ImpactFeedback.play_sfx(FIRE_SOUND, get_muzzle_position(), 1.45, -8.0)
		if (prev_mode == BeamMode.FIRING) != (mode == BeamMode.FIRING):
			beam_state_changed.emit(mode == BeamMode.FIRING)
	if mode == BeamMode.OFF:
		_hide_all_beams()
		if _muzzle_light != null:
			_muzzle_light.light_energy = 0.0


func shutdown() -> void:
	set_beam_mode(BeamMode.OFF, 0.0)


func is_beam_active() -> bool:
	return _beam_mode == BeamMode.FIRING


func is_telegraphing() -> bool:
	return _beam_mode == BeamMode.TELEGRAPH


func get_muzzle_position() -> Vector3:
	if is_instance_valid(_muzzle):
		return _muzzle.global_position
	return global_position


func get_aim_direction() -> Vector3:
	if is_instance_valid(_muzzle):
		return -_muzzle.global_basis.z.normalized()
	return -global_basis.z.normalized()


## Aims the articulated cannon toward a world-space target point in any 3D direction.
func aim_at_point(world_target: Vector3, turn_speed_rad: float, delta: float) -> void:
	var pivot_origin := _pitch_pivot.global_position if is_instance_valid(_pitch_pivot) else global_position
	var to_target := world_target - pivot_origin
	if to_target.length_squared() < 0.0001:
		return
	aim_in_direction(to_target.normalized(), turn_speed_rad, delta)


## Aims the articulated cannon along an arbitrary world-space direction vector (down, horizontal, up, etc.).
func aim_in_direction(world_dir: Vector3, turn_speed_rad: float, delta: float) -> void:
	if not is_instance_valid(_yaw_pivot) or not is_instance_valid(_pitch_pivot):
		return
	if world_dir.length_squared() < 0.0001:
		return
	var yaw_parent := _yaw_pivot.get_parent() as Node3D
	if yaw_parent == null:
		return

	var local_dir := (yaw_parent.global_basis.inverse() * world_dir.normalized()).normalized()
	var horiz_len := Vector2(local_dir.x, local_dir.z).length()
	var max_step := turn_speed_rad * delta

	if horiz_len > 0.02:
		var target_yaw := atan2(-local_dir.x, -local_dir.z)
		var yaw_diff := wrapf(target_yaw - _yaw_pivot.rotation.y, -PI, PI)
		_yaw_pivot.rotation.y += clampf(yaw_diff, -max_step, max_step)

	var target_pitch := clampf(
		asin(clampf(local_dir.y, -1.0, 1.0)),
		deg_to_rad(min_pitch_degrees),
		deg_to_rad(max_pitch_degrees)
	)
	_pitch_pivot.rotation.x = move_toward(_pitch_pivot.rotation.x, target_pitch, max_step)


## Immediately snaps the cannon to an exact world direction (e.g. exact Vector3.DOWN on lock).
func snap_to_direction(world_dir: Vector3) -> void:
	aim_in_direction(world_dir, TAU * 10.0, 1.0)


func step_weapon(delta: float, forced_direction: Vector3 = Vector3.ZERO) -> void:
	_tick_burn_cooldowns(delta)
	_update_muzzle_light()

	var fire_dir := forced_direction.normalized() if forced_direction.length_squared() > 0.0001 else get_aim_direction()

	if _beam_mode == BeamMode.FIRING:
		_telegraph_line.visible = false
		_telegraph_ring.visible = false
		_trace_active_beam(fire_dir)
		return

	_hide_active_segments()
	if _beam_mode == BeamMode.TELEGRAPH:
		_update_telegraph_line(fire_dir)
	else:
		_telegraph_line.visible = false
		_telegraph_ring.visible = false


func _bind_model_pivots() -> void:
	var visual := get_parent().get_node_or_null("Visual")
	if visual == null:
		return
	_yaw_pivot = visual.find_child(String(yaw_pivot_name), true, false) as Node3D
	_pitch_pivot = visual.find_child(String(pitch_pivot_name), true, false) as Node3D
	_muzzle = visual.find_child(String(muzzle_name), true, false) as Node3D

	if is_instance_valid(_muzzle):
		_muzzle_light = OmniLight3D.new()
		_muzzle_light.light_color = Color(1.0, 0.25, 0.42)
		_muzzle_light.light_energy = 0.0
		_muzzle_light.omni_range = 5.5
		_muzzle.add_child(_muzzle_light)


func _update_muzzle_light() -> void:
	if _muzzle_light == null:
		return
	match _beam_mode:
		BeamMode.FIRING:
			_muzzle_light.light_energy = 3.4
		BeamMode.TELEGRAPH:
			_muzzle_light.light_energy = lerpf(0.6, 2.8, _telegraph_ratio)
		BeamMode.OFF:
			_muzzle_light.light_energy = 0.15


func _trace_active_beam(initial_direction: Vector3) -> void:
	var origin := get_muzzle_position()
	var direction := initial_direction
	var remaining := max_range
	# Exclude our own hull only on segment 0 so the beam exits cleanly; after bouncing off
	# a MirrorSurface, segment 1+ CAN hit the drone itself!
	var excluded: Array[RID] = []
	if is_instance_valid(_owner_enemy):
		excluded.append(_owner_enemy.get_rid())
	var segment_index := 0

	while segment_index <= max_bounces and remaining > 0.05:
		var target := origin + direction * remaining
		var hit := _cast_beam_ray(origin, target, direction, excluded)
		if hit.is_empty():
			_show_segment(segment_index, origin, target)
			_hide_flare(segment_index)
			segment_index += 1
			break

		var hit_pos: Vector3 = hit["position"]
		_show_segment(segment_index, origin, hit_pos)
		_show_flare(segment_index, hit_pos)
		segment_index += 1

		var collider: Object = hit["collider"]
		if collider is MirrorSurfaceScript:
			var mirror := collider as MirrorSurfaceScript
			mirror.notify_laser_reflect(hit_pos)
			var normal := mirror.get_reflection_normal(direction)
			var travelled := origin.distance_to(hit_pos)
			remaining -= travelled
			direction = direction.bounce(normal).normalized()
			origin = hit_pos + direction * BOUNCE_CLEARANCE
			excluded = [hit["rid"] as RID]
			continue

		if collider is EnemyLocal:
			_burn_enemy(collider as EnemyLocal, hit_pos, direction)
		elif collider is PlayerLocal:
			_hit_player(collider as PlayerLocal, hit_pos)
		break

	for i in range(segment_index, _segments.size()):
		_segments[i].visible = false
		_flares[i].visible = false


func _update_telegraph_line(direction: Vector3) -> void:
	var origin := get_muzzle_position()
	var target := origin + direction * max_range
	var excluded: Array[RID] = []
	if is_instance_valid(_owner_enemy):
		excluded.append(_owner_enemy.get_rid())
	var hit := _cast_beam_ray(origin, target, direction, excluded)
	var end_pos: Vector3 = hit["position"] if not hit.is_empty() else target
	_telegraph_line.visible = true
	_place_cylinder(_telegraph_line, origin, end_pos, lerpf(0.45, 1.35, _telegraph_ratio))

	if not hit.is_empty():
		_telegraph_ring.visible = true
		var ring_normal: Vector3 = hit["normal"] if hit.has("normal") else Vector3.UP
		_telegraph_ring.global_position = end_pos + ring_normal * 0.05
		var ring_scale := lerpf(1.45, 0.55, _telegraph_ratio)
		_telegraph_ring.scale = Vector3(ring_scale, 1.0, ring_scale)
	else:
		_telegraph_ring.visible = false


func _cast_beam_ray(from: Vector3, to: Vector3, direction: Vector3, initial_exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, RAY_MASK)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = initial_exclude.duplicate()
	var space := get_world_3d().direct_space_state

	for _attempt in MAX_RAY_ATTEMPTS:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {}
		var collider: Object = hit["collider"]
		if _accept_hit(collider, direction):
			return hit
		var next_exclude := query.exclude
		next_exclude.append(hit["rid"])
		query.exclude = next_exclude
	return {}


func _accept_hit(collider: Object, direction: Vector3) -> bool:
	if collider is MirrorSurfaceScript:
		return not (collider as MirrorSurfaceScript).is_grazing(direction)
	if collider is EnemyLocal:
		return (collider as EnemyLocal).is_alive()
	if collider is PlayerLocal:
		return not (collider as PlayerLocal).is_dead
	if collider is Area3D:
		return false
	return true


func _burn_enemy(enemy: EnemyLocal, hit_pos: Vector3, beam_dir: Vector3) -> void:
	var id := enemy.get_instance_id()
	if _enemy_burn_cooldowns.get(id, 0.0) > 0.0:
		return
	_enemy_burn_cooldowns[id] = enemy_damage_interval
	var source := enemy.global_position - beam_dir
	if not Health.apply_damage(enemy, damage_per_tick, source):
		return
	ImpactFeedback.play_sfx(BURN_SOUND, hit_pos, randf_range(1.3, 1.6), -6.5)
	CameraFeedback.add_trauma(0.16)
	_spawn_sparks(hit_pos, 0.65)


func _hit_player(player: PlayerLocal, hit_pos: Vector3) -> void:
	if not Health.apply_damage(player, player_damage, hit_pos):
		return
	CameraFeedback.add_trauma_hurt()
	_spawn_sparks(hit_pos, 0.7)


func _tick_burn_cooldowns(delta: float) -> void:
	var expired: Array = []
	for id in _enemy_burn_cooldowns.keys():
		var remaining: float = _enemy_burn_cooldowns[id] - delta
		if remaining <= 0.0:
			expired.append(id)
		else:
			_enemy_burn_cooldowns[id] = remaining
	for id in expired:
		_enemy_burn_cooldowns.erase(id)


func _build_beam_pool() -> void:
	_beam_root = Node3D.new()
	_beam_root.name = "DroneBeamVisuals"
	_beam_root.top_level = true
	add_child(_beam_root)

	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1.0, 0.90, 0.94)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.45, 0.60)
	core_mat.emission_energy_multiplier = 2.8

	var aura_mat := ShaderMaterial.new()
	aura_mat.shader = BEAM_SHADER
	aura_mat.set_shader_parameter("core_color", Color(1.0, 0.72, 0.80))
	aura_mat.set_shader_parameter("aura_color", Color(1.0, 0.14, 0.30))
	aura_mat.set_shader_parameter("intensity", 2.6)

	var flare_mat := StandardMaterial3D.new()
	flare_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flare_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flare_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flare_mat.albedo_color = Color(1.0, 0.42, 0.56, 0.92)

	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = core_radius
	core_mesh.bottom_radius = core_radius
	core_mesh.height = 1.0
	core_mesh.radial_segments = 12
	core_mesh.rings = 1
	core_mesh.material = core_mat

	var aura_mesh := CylinderMesh.new()
	aura_mesh.top_radius = aura_radius
	aura_mesh.bottom_radius = aura_radius
	aura_mesh.height = 1.0
	aura_mesh.radial_segments = 14
	aura_mesh.rings = 1
	aura_mesh.material = aura_mat

	var flare_mesh := SphereMesh.new()
	flare_mesh.radius = 0.30
	flare_mesh.height = 0.60
	flare_mesh.radial_segments = 12
	flare_mesh.rings = 6
	flare_mesh.material = flare_mat

	for i in range(max_bounces + 1):
		var seg := Node3D.new()
		seg.name = "Segment_%d" % i
		seg.visible = false
		var core := MeshInstance3D.new()
		core.mesh = core_mesh
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		core.rotation.x = PI * 0.5
		seg.add_child(core)
		var aura := MeshInstance3D.new()
		aura.mesh = aura_mesh
		aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		aura.rotation.x = PI * 0.5
		seg.add_child(aura)
		_beam_root.add_child(seg)
		_segments.append(seg)

		var flare := MeshInstance3D.new()
		flare.name = "Flare_%d" % i
		flare.mesh = flare_mesh
		flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flare.visible = false
		_beam_root.add_child(flare)
		_flares.append(flare)

	_telegraph_line = Node3D.new()
	_telegraph_line.name = "TelegraphLine"
	_telegraph_line.visible = false
	var tele_mat := StandardMaterial3D.new()
	tele_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tele_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tele_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tele_mat.albedo_color = Color(1.0, 0.25, 0.38, 0.72)
	var tele_mesh := CylinderMesh.new()
	tele_mesh.top_radius = 0.042
	tele_mesh.bottom_radius = 0.042
	tele_mesh.height = 1.0
	tele_mesh.radial_segments = 8
	tele_mesh.rings = 1
	tele_mesh.material = tele_mat
	var tele_inst := MeshInstance3D.new()
	tele_inst.mesh = tele_mesh
	tele_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tele_inst.rotation.x = PI * 0.5
	_telegraph_line.add_child(tele_inst)
	_beam_root.add_child(_telegraph_line)

	# Glowing target reticle ring on the floor where the locked laser will strike.
	_telegraph_ring = MeshInstance3D.new()
	_telegraph_ring.name = "TelegraphRing"
	_telegraph_ring.visible = false
	_telegraph_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.55
	ring_mesh.outer_radius = 0.72
	ring_mesh.rings = 20
	ring_mesh.ring_segments = 8
	var ring_mat := StandardMaterial3D.new()
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.22, 0.36, 0.85)
	ring_mesh.material = ring_mat
	_telegraph_ring.mesh = ring_mesh
	_beam_root.add_child(_telegraph_ring)


func _show_segment(index: int, start: Vector3, end: Vector3) -> void:
	if index >= _segments.size():
		return
	var seg := _segments[index]
	seg.visible = true
	_place_cylinder(seg, start, end, 1.0)


func _show_flare(index: int, at: Vector3) -> void:
	if index >= _flares.size():
		return
	var flare := _flares[index]
	flare.visible = true
	flare.global_position = at


func _hide_flare(index: int) -> void:
	if index >= _flares.size():
		return
	_flares[index].visible = false


func _hide_active_segments() -> void:
	for i in _segments.size():
		_segments[i].visible = false
		_flares[i].visible = false


func _hide_all_beams() -> void:
	_hide_active_segments()
	if _telegraph_line != null:
		_telegraph_line.visible = false
	if _telegraph_ring != null:
		_telegraph_ring.visible = false


func _place_cylinder(node: Node3D, start: Vector3, end: Vector3, thickness: float) -> void:
	var delta := end - start
	var length := delta.length()
	if length < 0.001:
		node.visible = false
		return
	var dir := delta / length
	var up_ref := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	var seg_basis := Basis.looking_at(dir, up_ref).scaled_local(Vector3(thickness, thickness, length))
	node.global_transform = Transform3D(seg_basis, (start + end) * 0.5)


func _spawn_sparks(at_position: Vector3, density: float) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var sparks := SPARKS_SCENE.instantiate() as GPUParticles3D
	sparks.amount_ratio = density
	scene_root.add_child(sparks)
	sparks.global_position = at_position
	sparks.emitting = true
