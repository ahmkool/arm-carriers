class_name FrostGolemMoves
extends Node
## What the Frost Golem's moves do to the world. The behavior picks a move and the attacking state times it;
## this node owns the telegraphs, the hit boxes, the spikes and the frozen ground.

const SLAM_SOUND := preload("res://assets/sounds/explosion/Small Explosion 2_1.wav")
const SPIKE_FIRST_OFFSET := 2.2
## A spike only rises where there is floor: within this of the navmesh, measured flat.
const SPIKE_FLOOR_TOLERANCE := 1.6

@export var spike_scene: PackedScene
@export var spikes_per_line := 6
@export var spike_spacing := 2.0
@export var spike_stagger_seconds := 0.12
@export var spike_fan_degrees := 28.0
@export var slam_radius := 3.6
@export var freeze_radius := 7.5
@export var freeze_seconds := 7.0
@export var enraged_freeze_seconds := 11.0

@onready var _enemy: EnemyLocal = get_parent() as EnemyLocal
@onready var _sweep_hit_box: Area3D = _enemy.get_node("SweepHitBox") as Area3D
@onready var _sweep_telegraph: MeshInstance3D = _enemy.get_node("SweepTelegraph") as MeshInstance3D
@onready var _slam_point: Node3D = _enemy.get_node("SlamPoint") as Node3D
@onready var _slam_telegraph: MeshInstance3D = _enemy.get_node("SlamPoint/SlamTelegraph") as MeshInstance3D
@onready var _slam_burst: GPUParticles3D = _enemy.get_node("SlamPoint/SlamBurst") as GPUParticles3D
@onready var _frost: FrostGround = _enemy.get_node("FrostGround") as FrostGround


func _ready() -> void:
	var health := Health.from_target(_enemy)
	if health == null:
		return
	health.died.connect(_on_died)


func begin_move(move: StringName) -> void:
	_sweep_telegraph.visible = move == &"sweep"
	_slam_telegraph.visible = move == &"slam"


func end_move() -> void:
	_sweep_telegraph.visible = false
	_slam_telegraph.visible = false
	set_sweep_active(false)


func set_sweep_active(active: bool) -> void:
	_sweep_hit_box.set_deferred("monitoring", active)


func slam(enraged: bool) -> void:
	var centre := _slam_point.global_position
	_slam_telegraph.visible = false
	_slam_burst.restart()
	_play_sound(SLAM_SOUND)
	CameraFeedback.add_trauma_hurt()
	for player in _get_living_players():
		var offset := player.global_position - centre
		if Vector2(offset.x, offset.z).length() > slam_radius:
			continue
		Health.apply_damage(player, 9999, centre)
	_frost.freeze(centre, freeze_radius, enraged_freeze_seconds if enraged else freeze_seconds)


func cast_spikes(lines: int) -> void:
	if spike_scene == null:
		return
	var aim := _get_flat_aim()
	var first_angle := -deg_to_rad(spike_fan_degrees) * (lines - 1) * 0.5
	for line in lines:
		_cast_spike_line(aim.rotated(Vector3.UP, first_angle + deg_to_rad(spike_fan_degrees) * line))


func roar() -> void:
	ImpactFeedback.play_boss_moment()
	_frost.freeze(_enemy.global_position, freeze_radius, enraged_freeze_seconds)


func _cast_spike_line(direction: Vector3) -> void:
	var origin := _enemy.global_position
	for index in spikes_per_line:
		var point := origin + direction * (SPIKE_FIRST_OFFSET + spike_spacing * index)
		if not _has_floor(point):
			return
		get_tree().create_timer(spike_stagger_seconds * index).timeout.connect(_spawn_spike.bind(point))


func _spawn_spike(point: Vector3) -> void:
	if not is_instance_valid(_enemy) or not _enemy.is_alive():
		return
	var spike := spike_scene.instantiate() as Node3D
	get_tree().current_scene.add_child(spike)
	spike.global_position = Vector3(point.x, _enemy.global_position.y, point.z)


func _has_floor(point: Vector3) -> bool:
	var map_rid := _enemy.navigation_agent.get_navigation_map()
	var closest := NavigationServer3D.map_get_closest_point(map_rid, point)
	return Vector2(closest.x - point.x, closest.z - point.z).length() <= SPIKE_FLOOR_TOLERANCE


func _get_flat_aim() -> Vector3:
	var forward := -_enemy.global_basis.z
	var fallback := Vector3(forward.x, 0.0, forward.z).normalized()
	if not is_instance_valid(_enemy.target_player):
		return fallback
	var to_target := _enemy.target_player.global_position - _enemy.global_position
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	if flat.length_squared() < 0.0001:
		return fallback
	return flat.normalized()


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
	_frost.thaw_all()


func _play_sound(stream: AudioStream) -> void:
	var sfx := AudioStreamPlayer3D.new()
	_enemy.add_child(sfx)
	sfx.bus = "SFX"
	sfx.stream = stream
	sfx.finished.connect(sfx.queue_free, CONNECT_ONE_SHOT)
	sfx.play()
