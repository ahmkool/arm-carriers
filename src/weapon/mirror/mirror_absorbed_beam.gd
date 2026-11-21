class_name MirrorAbsorbedBeam
extends Node3D
## Attached to the mirror glass at the exact spot an enemy fireball was absorbed.
## Charges for `charge_duration` (1.0s) as a pulsing crimson orb + thin aiming line,
## then fires a vivid red laser straight out of that mirror face for `fire_duration` (2.0s),
## sweeping with the players' mirror and burning enemies in its path.

signal beam_fired(origin: Vector3)

const MirrorSurfaceScript := preload("res://src/weapon/mirror/mirror_surface.gd")
const BEAM_SHADER := preload("res://src/world/elements/azure_veil/laser_beam.gdshader")
const CHARGE_SOUND := preload("res://assets/sounds/fireball_cast.wav")
const FIRE_SOUND := preload("res://assets/sounds/slash_1.wav")
const BURN_SOUND := preload("res://assets/sounds/damage/161098__braqoon__arrow_damage.wav")
const SPARKS_SCENE := preload("res://src/vfx/saw_sparks.tscn")

## Layers: 2 (enemy) | 4 (level) | 32 (bolt_mirror). Excludes layer 1 (player) so the players'
## own absorbed laser never harms them.
const RAY_MASK := 2 | 4 | BoltMirror.LAYER
const MAX_RAY_ATTEMPTS := 12
const BOUNCE_CLEARANCE := 0.04

@export var charge_duration: float = 1.0
@export var fire_duration: float = 2.0
@export var max_range: float = 55.0
@export var max_bounces: int = 2
@export var core_radius: float = 0.09
@export var aura_radius: float = 0.25
@export var damage_per_tick: int = 1
@export var enemy_damage_interval: float = 0.22

var _face_sign: float = 1.0
var _owner_surface_rid: RID
var _elapsed := 0.0
var _firing := false

var _orb: MeshInstance3D
var _ring: MeshInstance3D
var _light: OmniLight3D
var _beam_root: Node3D
var _telegraph_line: Node3D
var _segments: Array[Node3D] = []
var _flares: Array[MeshInstance3D] = []
var _enemy_burn_cooldowns: Dictionary = {}


func setup(local_entry_pos: Vector3, face_sign: float, owner_surface_rid: RID) -> void:
	position = local_entry_pos
	_face_sign = 1.0 if face_sign >= 0.0 else -1.0
	_owner_surface_rid = owner_surface_rid


func get_charge_intensity() -> float:
	if _firing:
		return 1.25
	return lerpf(0.35, 1.0, clampf(_elapsed / maxf(charge_duration, 0.001), 0.0, 1.0))


func _ready() -> void:
	_build_anchor_visuals()
	_build_beam_pool()
	ImpactFeedback.play_sfx(CHARGE_SOUND, global_position, 1.55, -9.0)


func _exit_tree() -> void:
	if is_instance_valid(_beam_root):
		_beam_root.queue_free()


func _physics_process(delta: float) -> void:
	_elapsed += delta
	_tick_burn_cooldowns(delta)

	if not _firing:
		var ratio := clampf(_elapsed / maxf(charge_duration, 0.001), 0.0, 1.0)
		_update_charge_visuals(ratio)
		_update_telegraph_line(ratio)
		if _elapsed >= charge_duration:
			_begin_firing()
		return

	var fire_elapsed := _elapsed - charge_duration
	if fire_elapsed >= fire_duration:
		queue_free()
		return

	var fade := clampf((fire_duration - fire_elapsed) / 0.25, 0.0, 1.0)
	_update_firing_visuals(fade)
	_trace_active_beam()


func _begin_firing() -> void:
	_firing = true
	if _telegraph_line != null:
		_telegraph_line.visible = false
	if _ring != null:
		_ring.visible = false
	ImpactFeedback.play_sfx(FIRE_SOUND, global_position, 1.2, -5.0)
	CameraFeedback.add_trauma(0.24)
	_spawn_sparks(global_position, 0.75)
	beam_fired.emit(global_position)


func _get_fire_direction() -> Vector3:
	return (global_basis.x.normalized() * _face_sign).normalized()


func _update_charge_visuals(ratio: float) -> void:
	var pulse := 1.0 + 0.14 * sin(_elapsed * 26.0)
	var orb_scale := lerpf(0.55, 1.15, ratio) * pulse
	if _orb != null:
		_orb.scale = Vector3.ONE * orb_scale
	if _ring != null:
		var ring_scale := lerpf(1.65, 0.65, ratio)
		_ring.scale = Vector3(ring_scale, 1.0, ring_scale)
		_ring.rotate_object_local(Vector3.UP, 3.2 * get_physics_process_delta_time())
	if _light != null:
		_light.light_energy = lerpf(0.8, 3.0, ratio)


func _update_firing_visuals(fade: float) -> void:
	if _orb != null:
		var pulse := (1.0 + 0.18 * sin(_elapsed * 42.0)) * maxf(0.4, fade)
		_orb.scale = Vector3.ONE * (1.28 * pulse)
	if _light != null:
		_light.light_energy = 3.8 * fade


func _update_telegraph_line(ratio: float) -> void:
	if _telegraph_line == null:
		return
	var origin := global_position
	var direction := _get_fire_direction()
	var target := origin + direction * max_range
	var excluded: Array[RID] = []
	if _owner_surface_rid.is_valid():
		excluded.append(_owner_surface_rid)
	var hit := _cast_beam_ray(origin, target, direction, excluded)
	var end_pos: Vector3 = hit["position"] if not hit.is_empty() else target
	_telegraph_line.visible = true
	_place_cylinder(_telegraph_line, origin, end_pos, lerpf(0.35, 1.2, ratio))


func _trace_active_beam() -> void:
	var origin := global_position
	var direction := _get_fire_direction()
	var remaining := max_range
	var excluded: Array[RID] = []
	if _owner_surface_rid.is_valid():
		excluded.append(_owner_surface_rid)
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
		break

	for i in range(segment_index, _segments.size()):
		_segments[i].visible = false
		_flares[i].visible = false


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
	ImpactFeedback.play_sfx(BURN_SOUND, hit_pos, randf_range(1.25, 1.55), -6.5)
	CameraFeedback.add_trauma(0.15)
	_spawn_sparks(hit_pos, 0.65)


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


func _build_anchor_visuals() -> void:
	var orb_mat := StandardMaterial3D.new()
	orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	orb_mat.albedo_color = Color(1.0, 0.85, 0.78)
	orb_mat.emission_enabled = true
	orb_mat.emission = Color(1.0, 0.16, 0.10)
	orb_mat.emission_energy_multiplier = 3.2

	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = 0.20
	orb_mesh.height = 0.40
	orb_mesh.radial_segments = 14
	orb_mesh.rings = 8
	orb_mesh.material = orb_mat

	_orb = MeshInstance3D.new()
	_orb.mesh = orb_mesh
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_orb)

	var ring_mat := StandardMaterial3D.new()
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(1.0, 0.28, 0.16, 0.88)

	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.24
	ring_mesh.outer_radius = 0.31
	ring_mesh.rings = 18
	ring_mesh.ring_segments = 8
	ring_mesh.material = ring_mat

	_ring = MeshInstance3D.new()
	_ring.mesh = ring_mesh
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Align torus flat against the mirror's ±X glass face.
	_ring.rotation.z = PI * 0.5
	add_child(_ring)

	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.22, 0.14)
	_light.light_energy = 1.0
	_light.omni_range = 6.0
	add_child(_light)


func _build_beam_pool() -> void:
	_beam_root = Node3D.new()
	_beam_root.name = "AbsorbedBeamVisuals"
	_beam_root.top_level = true
	add_child(_beam_root)

	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1.0, 0.92, 0.88)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.24, 0.16)
	core_mat.emission_energy_multiplier = 3.0

	var aura_mat := ShaderMaterial.new()
	aura_mat.shader = BEAM_SHADER
	aura_mat.set_shader_parameter("core_color", Color(1.0, 0.78, 0.70))
	aura_mat.set_shader_parameter("aura_color", Color(1.0, 0.08, 0.05))
	aura_mat.set_shader_parameter("intensity", 2.8)

	var flare_mat := StandardMaterial3D.new()
	flare_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flare_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flare_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flare_mat.albedo_color = Color(1.0, 0.30, 0.18, 0.92)

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
	flare_mesh.radius = 0.34
	flare_mesh.height = 0.68
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
	tele_mat.albedo_color = Color(1.0, 0.22, 0.14, 0.62)
	var tele_mesh := CylinderMesh.new()
	tele_mesh.top_radius = 0.036
	tele_mesh.bottom_radius = 0.036
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
