class_name HighwayTrooperController
extends Node
## Drives a smaller Action Figure highway enemy perched on an enemy truck roof.
## Supports two roles:
##   - SHOOTER: holds Gun.gltf and fires staggered bursts of normal bullets at players.
##   - GRENADIER: holds Grenade.gltf and lobs arcing AgentGrenades onto the players' deck.

signal defeated(trooper: EnemyLocal)

enum Role {
	SHOOTER,
	GRENADIER,
}

const BULLET_SCENE := preload("res://src/enemy/boss/agent_richard/agent_bullet.tscn")
const GRENADE_SCRIPT := preload("res://src/enemy/boss/agent_richard/agent_grenade.gd")
const GUN_MODEL := preload("res://assets/models/weapon/enemies/action_figure/Gun.gltf")
const GRENADE_MODEL := preload("res://assets/models/weapon/enemies/action_figure/Grenade.gltf")
const VEHICLE_SCRIPT := preload("res://src/world/elements/highway/highway_vehicle.gd")
## Matches KayKit Rig_Medium handslot.r alignment so +Z gun barrel points straight forward in Ranged_2H_Aiming.
const GUN_HAND_TRANSFORM := Transform3D(
	Vector3(0.0186, 0.0022, -0.9998),
	Vector3(-0.055, 0.9985, 0.0011),
	Vector3(0.9983, 0.055, 0.0187),
	Vector3.ZERO,
)

const GUN_SOUNDS: Array[AudioStream] = [
	preload("res://assets/sounds/gun/Gun 6-1.wav"),
	preload("res://assets/sounds/gun/Gun 6-2.wav"),
]

@export var role: Role = Role.SHOOTER
@export var bullet_speed: float = 14.5
@export var bullet_damage: int = 1
@export var burst_count: int = 2
@export var burst_interval_sec: float = 0.28
@export var shoot_cooldown_min: float = 2.1
@export var shoot_cooldown_max: float = 2.8
@export var grenade_flight_sec: float = 1.45
@export var grenade_blast_radius: float = 2.2
@export var grenade_damage: int = 1
@export var grenade_cooldown_min: float = 2.8
@export var grenade_cooldown_max: float = 3.5

var _enemy: EnemyLocal
var _health: Health
var _anim_player: AnimationPlayer
var _muzzle: Marker3D
var _muzzle_flash: MeshInstance3D

var _host_truck: VEHICLE_SCRIPT
var _player_truck: VEHICLE_SCRIPT
var _local_offset := Vector3.ZERO
var _combat_active := false
var _dead := false
var _run_id := 0
var _muzzle_flash_timer := 0.0


func _ready() -> void:
	_enemy = get_parent() as EnemyLocal
	if _enemy == null:
		return
	_health = Health.from_target(_enemy)
	if _health != null:
		_health.died.connect(_on_died)
	_anim_player = _enemy.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_attach_weapon()
	_build_muzzle_flash()


func _physics_process(delta: float) -> void:
	if _enemy == null:
		return
	if _muzzle_flash_timer > 0.0:
		_muzzle_flash_timer = maxf(0.0, _muzzle_flash_timer - delta)
		if _muzzle_flash_timer <= 0.0 and _muzzle_flash != null:
			_muzzle_flash.visible = false

	if _host_truck == null or not is_instance_valid(_host_truck):
		return

	# Keep trooper planted on their moving truck roof.
	_enemy.global_position = _host_truck.get_deck_world_position() + _local_offset
	_enemy.velocity = Vector3.ZERO

	if _dead or not _combat_active:
		return

	var target := _closest_living_player()
	if target != null:
		var to_player := target.global_position - _enemy.global_position
		to_player.y = 0.0
		if to_player.length_squared() > 0.01:
			_enemy.smooth_rotate_toward(to_player, delta)


## Places the trooper on `host_truck` at `local_offset` and starts attacking after `initial_delay`.
func deploy_on_truck(
	host_truck: VEHICLE_SCRIPT,
	local_offset: Vector3,
	player_truck: VEHICLE_SCRIPT,
	initial_delay: float = 0.6,
) -> void:
	_host_truck = host_truck
	_local_offset = local_offset
	_player_truck = player_truck
	_dead = false
	_combat_active = true
	_run_id += 1
	if _enemy != null:
		_enemy.global_position = host_truck.get_deck_world_position() + local_offset
		_enemy.visible = true
		_enemy.collision_layer = 2
		_enemy.is_offensive = true
		_face_players_immediately()
	_play_anim(&"Ranged_2H_Aiming" if role == Role.SHOOTER else &"Idle_B", 1.0)
	_run_attack_loop(_run_id, initial_delay)


func is_trooper_alive() -> bool:
	return not _dead and _health != null and _health.is_alive()


func _run_attack_loop(run_id: int, initial_delay: float) -> void:
	if not await _wait_seconds(initial_delay, run_id):
		return

	while _is_active_run(run_id):
		if role == Role.SHOOTER:
			if not await _perform_shoot_burst(run_id):
				return
			var cd := randf_range(shoot_cooldown_min, shoot_cooldown_max)
			if not await _wait_seconds(cd, run_id):
				return
		else:
			_launch_grenade()
			var cd := randf_range(grenade_cooldown_min, grenade_cooldown_max)
			if not await _wait_seconds(cd, run_id):
				return


func _perform_shoot_burst(run_id: int) -> bool:
	for i in burst_count:
		if not _is_active_run(run_id):
			return false
		_fire_bullet()
		if i < burst_count - 1:
			if not await _wait_seconds(burst_interval_sec, run_id):
				return false
	return true


func _fire_bullet() -> void:
	var target := _closest_living_player()
	if target == null:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	_play_anim(&"Ranged_2H_Shoot", 1.8)
	var flash_origin := _muzzle.global_position if _muzzle != null else (_enemy.global_position + Vector3.UP * 1.15 - _enemy.global_basis.z * 0.7)
	var origin := Vector3(flash_origin.x, _enemy.global_position.y + 1.10, flash_origin.z)
	var aim_pos := target.global_position + Vector3.UP * 0.95
	var dir := aim_pos - origin
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		dir = -_enemy.global_basis.z
	dir = dir.normalized().rotated(Vector3.UP, deg_to_rad(randf_range(-4.5, 4.5)))

	var bullet := BULLET_SCENE.instantiate() as Fireball
	bullet.damage = bullet_damage
	scene_root.add_child(bullet)
	bullet.global_position = origin
	bullet.launch(dir * bullet_speed)

	if _muzzle_flash != null:
		_muzzle_flash.global_position = flash_origin
		_muzzle_flash.visible = true
		_muzzle_flash_timer = 0.07
	_play_sfx(GUN_SOUNDS.pick_random(), randf_range(1.05, 1.22), -7.0)


func _launch_grenade() -> void:
	var players := _living_players()
	if players.is_empty():
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return

	var target_player: PlayerLocal = players.pick_random()
	var target_pos := target_player.global_position + Vector3(randf_range(-1.4, 1.4), 0.0, randf_range(-1.4, 1.4))
	if _player_truck != null and _player_truck.deck != null:
		target_pos = _player_truck.deck.clamp_inside(target_pos, 1.5)

	_play_anim(&"Throw", 1.2)
	var grenade := GRENADE_SCRIPT.new()
	grenade.blast_radius = grenade_blast_radius
	grenade.damage = grenade_damage
	scene_root.add_child(grenade)
	var track_surface: Node3D = _player_truck.get_visual_surface_node() if _player_truck != null else null
	grenade.launch(_enemy.global_position + Vector3.UP * 1.5, target_pos, grenade_flight_sec, track_surface)


func _on_died(_source_position: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return
	_dead = true
	_combat_active = false
	_run_id += 1
	if _enemy != null:
		_enemy.collision_layer = 0
		_enemy.is_offensive = false
		ImpactFeedback.spawn_dust(_enemy.global_position, 0.8)
	_play_anim(&"Death_A", 1.2, false)
	defeated.emit(_enemy)
	get_tree().create_timer(1.6).timeout.connect(func() -> void:
		if is_instance_valid(_enemy):
			_enemy.queue_free()
	)


func _attach_weapon() -> void:
	var skeleton := _enemy.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	var hand := BoneAttachment3D.new()
	hand.name = "RightHandAttachment"
	hand.bone_name = "handslot.r"
	skeleton.add_child(hand)
	if role == Role.SHOOTER:
		var gun := GUN_MODEL.instantiate() as Node3D
		if gun != null:
			gun.transform = GUN_HAND_TRANSFORM
			hand.add_child(gun)
			_muzzle = Marker3D.new()
			_muzzle.name = "Muzzle"
			_muzzle.position = Vector3(0.0, 0.17, 1.12)
			gun.add_child(_muzzle)
	else:
		var grenade := GRENADE_MODEL.instantiate() as Node3D
		if grenade != null:
			grenade.scale = Vector3.ONE * 1.35
			grenade.position = Vector3(0.0, 0.06, 0.08)
			hand.add_child(grenade)


func _build_muzzle_flash() -> void:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(2.2, 1.35, 0.35, 0.95)
	var mesh := SphereMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.50
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = mat
	_muzzle_flash = MeshInstance3D.new()
	_muzzle_flash.top_level = true
	_muzzle_flash.visible = false
	_muzzle_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle_flash.mesh = mesh
	add_child(_muzzle_flash)


func _play_anim(anim_name: StringName, speed_scale: float = 1.0, return_to_idle: bool = true) -> void:
	if _anim_player == null:
		return
	var full_name := StringName("trooper/" + String(anim_name))
	if not _anim_player.has_animation(full_name):
		return
	_anim_player.speed_scale = speed_scale
	_anim_player.play(full_name, 0.08)
	var idle_anim := &"Ranged_2H_Aiming" if role == Role.SHOOTER else &"Idle_B"
	if return_to_idle and anim_name != idle_anim:
		_anim_player.queue(StringName("trooper/" + String(idle_anim)))


func _face_players_immediately() -> void:
	var target := _closest_living_player()
	if target == null:
		return
	var to_player := target.global_position - _enemy.global_position
	to_player.y = 0.0
	if to_player.length_squared() > 0.01:
		_enemy.global_basis = Basis.looking_at(to_player.normalized(), Vector3.UP)


func _is_active_run(run_id: int) -> bool:
	return is_inside_tree() and run_id == _run_id and not _dead and _combat_active


func _wait_seconds(seconds: float, run_id: int) -> bool:
	var elapsed := 0.0
	while elapsed < seconds:
		await get_tree().physics_frame
		if not _is_active_run(run_id):
			return false
		elapsed += get_physics_process_delta_time()
	return true


func _living_players() -> Array[PlayerLocal]:
	var living: Array[PlayerLocal] = []
	var world := get_tree().current_scene
	if world == null:
		return living
	var players := world.get_node_or_null(^"Players")
	if players == null:
		return living
	for child in players.get_children():
		var p := child as PlayerLocal
		if p == null or p.is_dead:
			continue
		living.append(p)
	return living


func _closest_living_player() -> PlayerLocal:
	var best: PlayerLocal = null
	var best_dist := INF
	for p in _living_players():
		var d := _enemy.global_position.distance_squared_to(p.global_position)
		if d < best_dist:
			best_dist = d
			best = p
	return best


func _play_sfx(stream: AudioStream, pitch: float, volume_db: float) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var sfx := AudioStreamPlayer3D.new()
	scene_root.add_child(sfx)
	sfx.global_position = _enemy.global_position
	sfx.bus = "SFX"
	sfx.stream = stream
	sfx.pitch_scale = pitch
	sfx.volume_db = volume_db
	sfx.max_distance = 65.0
	sfx.finished.connect(sfx.queue_free, CONNECT_ONE_SHOT)
	sfx.play()
