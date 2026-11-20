class_name LaserEmitter
extends Node3D
## Ancient floating arcane projector that fires an intermittent magical laser beam.
## Cycles between `off_duration` (with a visible charge telegraph near the end) and `on_duration`.
## Raycasts in true 3D and bounces off `MirrorSurface` panes, damaging living enemies (and players
## who step straight into the beam) while ignoring dead enemies and trigger areas.

signal beam_state_changed(is_on: bool)

## Layers: 1 (player) | 2 (enemy) | 4 (level) | 32 (bolt_mirror / MirrorSurface).
const RAY_MASK := 1 | 2 | 4 | BoltMirror.LAYER
const MAX_RAY_ATTEMPTS := 12
const BOUNCE_CLEARANCE := 0.04

const MirrorSurfaceScript := preload("res://src/weapon/mirror/mirror_surface.gd")
const BEAM_SHADER := preload("res://src/world/elements/azure_veil/laser_beam.gdshader")
const CHARGE_SOUND := preload("res://assets/sounds/fireball_cast.wav")
const FIRE_SOUND := preload("res://assets/sounds/slash_1.wav")
const BURN_SOUND := preload("res://assets/sounds/damage/161098__braqoon__arrow_damage.wav")
const SPARKS_SCENE := preload("res://src/vfx/saw_sparks.tscn")

@export_group("Cycle")
@export var off_duration: float = 2.0
@export var on_duration: float = 3.0
@export var telegraph_duration: float = 0.55
@export var initial_phase_offset: float = 0.0

@export_group("Beam")
@export var max_range: float = 65.0
@export var max_bounces: int = 4
@export var core_radius: float = 0.085
@export var aura_radius: float = 0.24
@export var damage_per_tick: int = 1
@export var enemy_damage_interval: float = 0.25
@export var player_damage: int = 1

@onready var _muzzle: Marker3D = $Muzzle
@onready var _prism: MeshInstance3D = $Visuals/Prism
@onready var _ring_outer: Node3D = $Visuals/RingOuter
@onready var _ring_inner: Node3D = $Visuals/RingInner
@onready var _muzzle_light: OmniLight3D = $Muzzle/MuzzleLight

var _cycle_time := 0.0
var _is_beam_on := false
var _was_telegraphing := false
var _segments: Array[Node3D] = []
var _flares: Array[MeshInstance3D] = []
var _telegraph_line: Node3D
var _prism_material: StandardMaterial3D
var _enemy_burn_cooldowns: Dictionary = {}
var _base_y := 0.0


func _ready() -> void:
	add_to_group(&"checkpoint_resettable")
	_base_y = position.y
	_cycle_time = _wrap_cycle(initial_phase_offset)
	_prism_material = _prism.get_active_material(0) as StandardMaterial3D
	if _prism_material != null:
		_prism_material = _prism_material.duplicate() as StandardMaterial3D
		_prism.material_override = _prism_material
	_build_beam_pool()
	_sync_state(false)


func reset_to_checkpoint() -> void:
	_cycle_time = _wrap_cycle(initial_phase_offset)
	_enemy_burn_cooldowns.clear()
	_was_telegraphing = false
	_sync_state(false)
	_hide_all_beams()


func is_beam_active() -> bool:
	return _is_beam_on


func _physics_process(delta: float) -> void:
	_tick_burn_cooldowns(delta)
	_advance_cycle(delta)
	_animate_emitter(delta)

	if _is_beam_on:
		_telegraph_line.visible = false
		_trace_active_beam()
		return

	_hide_active_segments()
	_update_telegraph_line()


func _advance_cycle(delta: float) -> void:
	var period := off_duration + on_duration
	if period <= 0.001:
		_sync_state(true)
		return
	_cycle_time = fposmod(_cycle_time + delta, period)
	var should_be_on := _cycle_time >= off_duration
	var telegraphing := (not should_be_on) and (_cycle_time >= maxf(0.0, off_duration - telegraph_duration))
	if telegraphing and not _was_telegraphing:
		ImpactFeedback.play_sfx(CHARGE_SOUND, _muzzle.global_position, 1.55, -14.0)
	_was_telegraphing = telegraphing
	_sync_state(should_be_on)


func _sync_state(new_on: bool) -> void:
	if _is_beam_on == new_on:
		return
	_is_beam_on = new_on
	if _is_beam_on:
		ImpactFeedback.play_sfx(FIRE_SOUND, _muzzle.global_position, 1.35, -8.0)
	beam_state_changed.emit(_is_beam_on)


func _animate_emitter(delta: float) -> void:
	var charge_ratio := _get_charge_ratio()
	var spin_mult := 1.0 + charge_ratio * 2.5 + (3.5 if _is_beam_on else 0.0)
	_ring_outer.rotate_object_local(Vector3.UP, deg_to_rad(28.0) * spin_mult * delta)
	_ring_inner.rotate_object_local(Vector3.UP, -deg_to_rad(44.0) * spin_mult * delta)
	_prism.rotate_object_local(Vector3.UP, deg_to_rad(50.0) * spin_mult * delta)

	if _muzzle_light != null:
		if _is_beam_on:
			_muzzle_light.light_energy = 3.2
		elif charge_ratio > 0.0:
			_muzzle_light.light_energy = lerpf(0.5, 2.6, charge_ratio)
		else:
			_muzzle_light.light_energy = 0.35

	if _prism_material != null:
		var glow := 3.4 if _is_beam_on else lerpf(0.45, 2.5, charge_ratio)
		_prism_material.emission_energy_multiplier = glow


func _get_charge_ratio() -> float:
	if _is_beam_on or telegraph_duration <= 0.001:
		return 0.0
	var start := maxf(0.0, off_duration - telegraph_duration)
	if _cycle_time < start:
		return 0.0
	return clampf((_cycle_time - start) / telegraph_duration, 0.0, 1.0)


func _trace_active_beam() -> void:
	var origin := _muzzle.global_position
	var direction := -_muzzle.global_basis.z.normalized()
	var remaining := max_range
	var excluded: Array[RID] = []
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


func _update_telegraph_line() -> void:
	var charge_ratio := _get_charge_ratio()
	if charge_ratio <= 0.0:
		_telegraph_line.visible = false
		return
	var origin := _muzzle.global_position
	var direction := -_muzzle.global_basis.z.normalized()
	var target := origin + direction * max_range
	var hit := _cast_beam_ray(origin, target, direction, [])
	var end_pos: Vector3 = hit["position"] if not hit.is_empty() else target
	_telegraph_line.visible = true
	_place_cylinder(_telegraph_line, origin, end_pos, lerpf(0.35, 1.0, charge_ratio))


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
	# Skip trigger areas, pickup zones, enemy melee hitboxes, etc.
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
	ImpactFeedback.play_sfx(BURN_SOUND, hit_pos, randf_range(1.25, 1.55), -7.0)
	CameraFeedback.add_trauma(0.14)
	_spawn_sparks(hit_pos, 0.55)


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
	var beam_root := Node3D.new()
	beam_root.name = "BeamVisuals"
	beam_root.top_level = true
	add_child(beam_root)

	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(0.95, 1.0, 1.0)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.75, 0.98, 1.0)
	core_mat.emission_energy_multiplier = 2.6

	var aura_mat := ShaderMaterial.new()
	aura_mat.shader = BEAM_SHADER

	var flare_mat := StandardMaterial3D.new()
	flare_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flare_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flare_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flare_mat.albedo_color = Color(0.72, 0.96, 1.0, 0.92)

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
		beam_root.add_child(seg)
		_segments.append(seg)

		var flare := MeshInstance3D.new()
		flare.name = "Flare_%d" % i
		flare.mesh = flare_mesh
		flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flare.visible = false
		beam_root.add_child(flare)
		_flares.append(flare)

	_telegraph_line = Node3D.new()
	_telegraph_line.name = "TelegraphLine"
	_telegraph_line.visible = false
	var tele_mat := StandardMaterial3D.new()
	tele_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tele_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tele_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tele_mat.albedo_color = Color(0.55, 0.92, 1.0, 0.52)
	var tele_mesh := CylinderMesh.new()
	tele_mesh.top_radius = 0.035
	tele_mesh.bottom_radius = 0.035
	tele_mesh.height = 1.0
	tele_mesh.radial_segments = 8
	tele_mesh.rings = 1
	tele_mesh.material = tele_mat
	var tele_inst := MeshInstance3D.new()
	tele_inst.mesh = tele_mesh
	tele_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tele_inst.rotation.x = PI * 0.5
	_telegraph_line.add_child(tele_inst)
	beam_root.add_child(_telegraph_line)


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


func _wrap_cycle(t: float) -> float:
	var period := off_duration + on_duration
	if period <= 0.001:
		return 0.0
	return fposmod(t, period)
