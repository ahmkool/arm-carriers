extends Node

@export var spawn_interval_seconds: float = 5.0
@export var spawn_jitter_seconds: float = 0.8
@export var edge_inset: float = 0.35
@export var enemy_scene: PackedScene = preload("res://src/enemy/enemy.tscn")

@onready var _spawn_timer: Timer = Timer.new()
@onready var _world: Node3D = get_parent() as Node3D
@onready var _game_state_manager: Node = get_node_or_null("../GameStateManager")

var _half_floor_x: float = 5.0
var _half_floor_z: float = 5.0
var _spawn_height: float = 1.0

func _ready():
	_cache_floor_size()
	_setup_timer()

func _cache_floor_size() -> void:
	var floor_mesh := _world.get_node_or_null("Floor/MeshInstance3D") as MeshInstance3D
	var box_mesh := floor_mesh.mesh as BoxMesh if floor_mesh else null
	if box_mesh != null:
		_half_floor_x = box_mesh.size.x * 0.5
		_half_floor_z = box_mesh.size.z * 0.5


func _setup_timer() -> void:
	add_child(_spawn_timer)
	_spawn_timer.one_shot = true
	_spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	_schedule_next_spawn()


func _schedule_next_spawn() -> void:
	var jitter := randf_range(-spawn_jitter_seconds, spawn_jitter_seconds)
	_spawn_timer.start(maxf(0.1, spawn_interval_seconds + jitter))


func _on_spawn_timer_timeout() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_schedule_next_spawn()
		return

	if not _is_game_ongoing():
		_schedule_next_spawn()
		return

	var spawn_pos := _random_edge_position()
	_spawn_enemy_on_all.rpc(spawn_pos)
	_schedule_next_spawn()


@rpc("authority", "call_local", "reliable")
func _spawn_enemy_on_all(spawn_pos: Vector3) -> void:
	if enemy_scene == null:
		return

	var enemy := enemy_scene.instantiate() as Node3D
	if enemy == null:
		return

	add_child(enemy)
	enemy.global_position = spawn_pos


func _random_edge_position() -> Vector3:
	var x := 0.0
	var z := 0.0
	var use_x_edge := randi() % 2 == 0

	if use_x_edge:
		x = (_half_floor_x - edge_inset) * (1.0 if randi() % 2 == 0 else -1.0)
		z = randf_range(-_half_floor_z + edge_inset, _half_floor_z - edge_inset)
	else:
		z = (_half_floor_z - edge_inset) * (1.0 if randi() % 2 == 0 else -1.0)
		x = randf_range(-_half_floor_x + edge_inset, _half_floor_x - edge_inset)

	return Vector3(x, _spawn_height, z)


func _is_game_ongoing() -> bool:
	if _game_state_manager == null:
		return false
	if not _game_state_manager.has_method("get"):
		return false
	return bool(_game_state_manager.get("is_game_ongoing"))
