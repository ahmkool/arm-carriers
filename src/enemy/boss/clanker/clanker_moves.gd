class_name ClankerMoves
extends Node
## What the Clanker's moves do to the world. The behavior picks a move and the attacking state times it;
## this node owns the telegraphs, the punch hit box, the shockwave, the slag and the overheat visuals.
##
## The shockwave is the lava world's twist: it rolls outward from the smash and sets off each magma pocket as it
## reaches it, so the floor erupts in a wave towards the carriers. The Clanker is spared by pockets it sets off
## itself, but a pocket the carriers set off under it burns it (see LavaVent.boss_burn_damage).

const SMASH_SOUND := preload("res://assets/sounds/explosion/Small Explosion 2_1.wav")
const POCKET_GROUP := &"magma_pockets"
## A glob lands on the floor: a target further than this from the navmesh, flat, is moved onto it.
const FLOOR_TOLERANCE := 1.2
const GLOB_STAGGER_SECONDS := 0.16

@export var slag_scene: PackedScene
@export var smash_radius := 3.4
@export var shockwave_speed := 9.0
@export var shockwave_reach := 12.0
@export var overheated_shockwave_reach := 16.0
## The roar's shockwave: far enough to cover the arena.
@export var overheat_shockwave_reach := 40.0
## How far ahead of a moving carrier a glob is aimed, as a share of where they'd be when it lands.
@export var mortar_lead := 0.6
@export var overheated_glob_spread := 2.6
@export var overheat_eye_material: Material

var _shockwave_tween: Tween

@onready var _enemy: EnemyLocal = get_parent() as EnemyLocal
@onready var _punch_hit_box: Area3D = _enemy.get_node("PunchHitBox") as Area3D
@onready var _punch_telegraph: MeshInstance3D = _enemy.get_node("PunchTelegraph") as MeshInstance3D
@onready var _smash_point: Node3D = _enemy.get_node("SmashPoint") as Node3D
@onready var _smash_telegraph: MeshInstance3D = _enemy.get_node("SmashPoint/SmashTelegraph") as MeshInstance3D
@onready var _smash_burst: GPUParticles3D = _enemy.get_node("SmashPoint/SmashBurst") as GPUParticles3D
@onready var _shockwave: MeshInstance3D = _enemy.get_node("Shockwave") as MeshInstance3D
@onready var _exhausts: Array[Node3D] = [
	_enemy.get_node("Clanker/Rig_Large/Skeleton3D/Chest/ExhaustLeft") as Node3D,
	_enemy.get_node("Clanker/Rig_Large/Skeleton3D/Chest/ExhaustRight") as Node3D,
]
@onready var _head: MeshInstance3D = _enemy.get_node("Clanker/Rig_Large/Skeleton3D/Clanker_Head") as MeshInstance3D
@onready var _light: OmniLight3D = _enemy.get_node("BossLight") as OmniLight3D


func _ready() -> void:
	_shockwave.visible = false
	_set_exhaust_fire(false)
	var health := Health.from_target(_enemy)
	if health == null:
		return
	health.died.connect(_on_died)


func begin_move(move: StringName) -> void:
	_punch_telegraph.visible = move == &"punch"
	_smash_telegraph.visible = move == &"smash"


func end_move() -> void:
	_punch_telegraph.visible = false
	_smash_telegraph.visible = false
	set_punch_active(false)


func set_punch_active(active: bool) -> void:
	_punch_hit_box.set_deferred("monitoring", active)


func smash(overheated: bool) -> void:
	var centre := _smash_point.global_position
	_smash_telegraph.visible = false
	_smash_burst.restart()
	_play_sound(SMASH_SOUND)
	CameraFeedback.add_trauma_hurt()
	for player in _get_living_players():
		var offset := player.global_position - centre
		if Vector2(offset.x, offset.z).length() > smash_radius:
			continue
		Health.apply_damage(player, 9999, centre)
	_send_shockwave(centre, overheated_shockwave_reach if overheated else shockwave_reach)


func fire_mortar(overheated: bool) -> void:
	if slag_scene == null:
		return
	var targets := _get_mortar_targets(overheated)
	for index in targets.size():
		var exhaust := _exhausts[index % _exhausts.size()]
		get_tree().create_timer(GLOB_STAGGER_SECONDS * index).timeout.connect(_launch_glob.bind(exhaust, targets[index]))


func overheat() -> void:
	ImpactFeedback.play_boss_moment()
	CameraFeedback.add_trauma_explosion()
	_set_exhaust_fire(true)
	_light.light_color = Color(1.0, 0.32, 0.1)
	_light.light_energy = 2.2
	if overheat_eye_material != null:
		_head.set_surface_override_material(1, overheat_eye_material)
	_send_shockwave(_enemy.global_position, overheat_shockwave_reach)


## Shows a ring rolling outward and sets off each armed pocket within `reach` as the ring passes it.
func _send_shockwave(centre: Vector3, reach: float) -> void:
	_show_shockwave(centre, reach)
	for node in get_tree().get_nodes_in_group(POCKET_GROUP):
		var pocket := node as LavaVent
		var offset := pocket.global_position - centre
		var distance := Vector2(offset.x, offset.z).length()
		if distance > reach or absf(offset.y) > 3.0:
			continue
		get_tree().create_timer(distance / shockwave_speed).timeout.connect(_ignite_pocket.bind(pocket))


func _ignite_pocket(pocket: LavaVent) -> void:
	if not is_instance_valid(pocket):
		return
	if not is_instance_valid(_enemy) or not _enemy.is_alive():
		return
	pocket.ignite(_enemy)


func _show_shockwave(centre: Vector3, reach: float) -> void:
	if _shockwave_tween != null:
		_shockwave_tween.kill()
	_shockwave.visible = true
	_shockwave.global_position = Vector3(centre.x, centre.y + 0.12, centre.z)
	_shockwave.scale = Vector3(0.5, 1.0, 0.5)
	_shockwave.transparency = 0.0
	_shockwave_tween = create_tween()
	_shockwave_tween.tween_property(_shockwave, "scale", Vector3(reach, 1.0, reach), reach / shockwave_speed)
	_shockwave_tween.parallel().tween_property(_shockwave, "transparency", 0.7, reach / shockwave_speed)
	_shockwave_tween.tween_callback(_shockwave.hide)


func _get_mortar_targets(overheated: bool) -> Array[Vector3]:
	var targets: Array[Vector3] = []
	var players := _get_living_players()
	for player in players:
		targets.append(_lead(player))
	if not overheated:
		return targets
	for player in players:
		var side := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)).normalized()
		targets.append(_lead(player) + side * overheated_glob_spread)
	if players.size() == 2:
		targets.append(players[0].global_position.lerp(players[1].global_position, 0.5))
	return targets


func _lead(player: PlayerLocal) -> Vector3:
	var flight := 1.25
	var flat_velocity := Vector3(player.velocity.x, 0.0, player.velocity.z)
	return player.global_position + flat_velocity * flight * mortar_lead


func _launch_glob(exhaust: Node3D, target: Vector3) -> void:
	if not is_instance_valid(_enemy) or not _enemy.is_alive():
		return
	var glob := slag_scene.instantiate() as SlagGlob
	glob.add_to_group(Checkpoint.ENEMY_PROJECTILE_GROUP)
	get_tree().current_scene.add_child(glob)
	var landing := _onto_floor(target)
	glob.global_position = Vector3(landing.x, _enemy.global_position.y, landing.z)
	glob.launch(exhaust.global_position)


func _onto_floor(point: Vector3) -> Vector3:
	var map_rid := _enemy.navigation_agent.get_navigation_map()
	var closest := NavigationServer3D.map_get_closest_point(map_rid, point)
	if Vector2(closest.x - point.x, closest.z - point.z).length() <= FLOOR_TOLERANCE:
		return point
	return closest


func _set_exhaust_fire(on: bool) -> void:
	for exhaust in _exhausts:
		var fire := exhaust.get_node_or_null("Fire") as GPUParticles3D
		if fire == null:
			continue
		fire.emitting = on


func _get_living_players() -> Array[PlayerLocal]:
	var living: Array[PlayerLocal] = []
	var players := _enemy._get_players_node()
	if players == null:
		return living
	for child in players.get_children():
		var player := child as PlayerLocal
		if player == null or player.is_dead:
			continue
		living.append(player)
	return living


func _on_died(_source_position: Vector3 = Vector3.ZERO) -> void:
	end_move()
	_set_exhaust_fire(false)
	_shockwave.visible = false


func _play_sound(stream: AudioStream) -> void:
	var sfx := AudioStreamPlayer3D.new()
	_enemy.add_child(sfx)
	sfx.bus = "SFX"
	sfx.stream = stream
	sfx.finished.connect(sfx.queue_free, CONNECT_ONE_SHOT)
	sfx.play()
