class_name AgentGrenade
extends Node3D
## Tactical arcing grenade launched by Agent Richard onto the players' truck roof.
## Marks its landing zone with a pulsing red warning ring from launch, spins through the air,
## and detonates on arrival — hurting any carrier still inside `blast_radius`.

const EXPLOSION_SCENE := preload("res://src/vfx/explosion.tscn")
const THROW_SOUND := preload("res://assets/sounds/fireball_cast.wav")
const GRENADE_MODEL := preload("res://assets/models/weapon/enemies/action_figure/Grenade.gltf")

@export var blast_radius: float = 2.3
@export var damage: int = 1
@export var arc_height: float = 5.2

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _track_body: Node3D
var _local_target_offset := Vector3.ZERO
var _flight_seconds := 1.35
var _elapsed := 0.0
var _launched := false

var _body_pivot: Node3D
var _led_mat: StandardMaterial3D
var _ring_root: Node3D
var _ring_edge_mat: StandardMaterial3D
var _ring_fill_mesh: MeshInstance3D


func _ready() -> void:
	add_to_group(Checkpoint.ENEMY_PROJECTILE_GROUP)
	_build_visuals()


func launch(from: Vector3, target: Vector3, flight_seconds: float = 1.35, track_surface: Node3D = null) -> void:
	if _body_pivot == null:
		_build_visuals()
	_from = from
	_to = Vector3(target.x, 0.0, target.z)
	_track_body = track_surface
	if _track_body != null and is_instance_valid(_track_body):
		_local_target_offset = _track_body.to_local(_to)
		_local_target_offset.y = 0.0
	_flight_seconds = maxf(flight_seconds, 0.35)
	_elapsed = 0.0
	_launched = true
	global_position = _from
	_sync_ring_to_surface()
	_ring_root.visible = true
	ImpactFeedback.play_sfx(THROW_SOUND, _from, randf_range(1.25, 1.45), -8.0)


func _physics_process(delta: float) -> void:
	if not _launched:
		return
	_sync_ring_to_surface()
	_elapsed += delta
	var t := clampf(_elapsed / _flight_seconds, 0.0, 1.0)
	global_position = _from.lerp(_to, t) + Vector3.UP * (arc_height * 4.0 * t * (1.0 - t))

	# Spin the grenade canister as it flies.
	_body_pivot.rotate_x(delta * 9.5)
	_body_pivot.rotate_z(delta * 5.2)

	# Blink red fuse LED faster as detonation approaches.
	var blink_rate := lerpf(10.0, 38.0, t)
	var blink_on := sin(_elapsed * blink_rate) > 0.0
	_led_mat.albedo_color = Color(2.8, 0.2, 0.12) if blink_on else Color(0.45, 0.06, 0.04)

	# Grow inner warning fill ring from 0 -> 1 to telegraph exact detonation timing.
	_ring_edge_mat.albedo_color.a = lerpf(0.45, 0.95, t) * (0.8 + 0.2 * sin(_elapsed * 28.0))
	var fill_scale := maxf(0.08, t)
	_ring_fill_mesh.scale = Vector3(fill_scale, 1.0, fill_scale)

	if t >= 1.0:
		_explode()


func _sync_ring_to_surface() -> void:
	if _ring_root == null:
		return
	if _track_body != null and is_instance_valid(_track_body):
		_to = _track_body.to_global(_local_target_offset)
		var ring_pos := _track_body.to_global(_local_target_offset + Vector3.UP * 0.08)
		var surf_basis := _track_body.global_basis.orthonormalized()
		_ring_root.global_transform = Transform3D(surf_basis.scaled(Vector3(blast_radius, 1.0, blast_radius)), ring_pos)
	else:
		_ring_root.global_position = _to + Vector3.UP * 0.10
		_ring_root.scale = Vector3(blast_radius, 1.0, blast_radius)


func _explode() -> void:
	_launched = false
	var scene_root := get_tree().current_scene
	if scene_root != null:
		_hurt_carriers(scene_root)
		var blast := EXPLOSION_SCENE.instantiate()
		blast.set("hurts_enemies", false)
		blast.set("damage_radius", blast_radius)
		scene_root.add_child(blast)
		blast.global_position = _to
	CameraFeedback.add_trauma_explosion()
	queue_free()


func _hurt_carriers(scene_root: Node) -> void:
	var players := scene_root.get_node_or_null(^"Players")
	if players == null:
		return
	for child in players.get_children():
		var player := child as PlayerLocal
		if player == null or player.is_dead:
			continue
		var offset := player.global_position - _to
		if absf(offset.y) > 2.5:
			continue
		if Vector2(offset.x, offset.z).length() <= blast_radius:
			if Health.apply_damage(player, damage, _to):
				CameraFeedback.add_trauma_hurt()


func _build_visuals() -> void:
	if _body_pivot != null:
		return
	_body_pivot = Node3D.new()
	add_child(_body_pivot)

	_led_mat = StandardMaterial3D.new()
	_led_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_led_mat.albedo_color = Color(2.4, 0.2, 0.12)

	var model := GRENADE_MODEL.instantiate() as Node3D
	if model != null:
		model.scale = Vector3.ONE * 1.45
		_body_pivot.add_child(model)

	var led := MeshInstance3D.new()
	var led_sphere := SphereMesh.new()
	led_sphere.radius = 0.12
	led_sphere.height = 0.24
	led_sphere.radial_segments = 8
	led_sphere.rings = 4
	led_sphere.material = _led_mat
	led.mesh = led_sphere
	led.position = Vector3(0.0, 0.42, 0.0)
	_body_pivot.add_child(led)

	# Smoke trail behind the arcing grenade.
	var smoke := GPUParticles3D.new()
	smoke.amount = 18
	smoke.lifetime = 0.55
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var proc := ParticleProcessMaterial.new()
	proc.spread = 180.0
	proc.initial_velocity_min = 0.2
	proc.initial_velocity_max = 0.6
	proc.gravity = Vector3(0.0, 1.2, 0.0)
	proc.scale_min = 0.14
	proc.scale_max = 0.34
	smoke.process_material = proc
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.albedo_color = Color(0.75, 0.72, 0.68, 0.7)
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var puff := SphereMesh.new()
	puff.radius = 0.22
	puff.height = 0.44
	puff.radial_segments = 6
	puff.rings = 4
	puff.material = smoke_mat
	smoke.draw_pass_1 = puff
	add_child(smoke)

	# Ground warning ring (top_level so it stays flat on the truck roof).
	_ring_root = Node3D.new()
	_ring_root.top_level = true
	_ring_root.visible = false
	add_child(_ring_root)

	_ring_edge_mat = StandardMaterial3D.new()
	_ring_edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_edge_mat.albedo_color = Color(1.0, 0.18, 0.10, 0.75)

	var torus := TorusMesh.new()
	torus.inner_radius = 0.90
	torus.outer_radius = 1.0
	torus.rings = 36
	torus.ring_segments = 4
	torus.material = _ring_edge_mat
	var edge := MeshInstance3D.new()
	edge.mesh = torus
	edge.scale = Vector3(1.0, 0.05, 1.0)
	edge.position = Vector3(0.0, 0.02, 0.0)
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_root.add_child(edge)

	var fill_mat := StandardMaterial3D.new()
	fill_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.albedo_color = Color(1.0, 0.22, 0.10, 0.26)

	var disc := CylinderMesh.new()
	disc.top_radius = 0.96
	disc.bottom_radius = 0.96
	disc.height = 0.015
	disc.radial_segments = 32
	disc.rings = 1
	disc.material = fill_mat
	_ring_fill_mesh = MeshInstance3D.new()
	_ring_fill_mesh.mesh = disc
	_ring_fill_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring_root.add_child(_ring_fill_mesh)
