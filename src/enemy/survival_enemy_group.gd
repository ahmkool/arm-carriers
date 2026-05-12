class_name SurvivalEnemyGroup
extends EnemyGroup

@export var enemy_scene: PackedScene = preload("res://src/enemy/enemy_local.tscn")
@export_range(0.05, 120.0, 0.05) var interval_spawn: float = 3.0
@export_range(0.1, 600.0, 0.1) var fight_duration: float = 60.0

var signal_emitted := false

var _started := false
var _fight_elapsed := 0.0
var _spawn_timer := 0.0

var _enemies_parent: Node
var _spawn_point_nodes: Array[Node3D] = []


func _ready() -> void:
	_resolve_containers()
	_cache_spawn_points()


func trigger(offensive: bool = true) -> void:
	if signal_emitted or not offensive:
		return
	if _started:
		return
	_started = true
	_fight_elapsed = 0.0
	_spawn_timer = 0.0
	_spawn_one()


func reset() -> void:
	signal_emitted = false
	_started = false
	_fight_elapsed = 0.0
	_spawn_timer = 0.0
	_clear_spawned_enemies()


func mark_as_defeated() -> void:
	_started = false
	_clear_spawned_enemies()
	signal_emitted = true


func _physics_process(delta: float) -> void:
	if signal_emitted or not _started:
		return
	_fight_elapsed += delta
	_spawn_timer += delta
	while _fight_elapsed < fight_duration and _spawn_timer >= interval_spawn:
		_spawn_timer -= interval_spawn
		_spawn_one()
	if _fight_elapsed >= fight_duration and _all_spawned_dead():
		signal_emitted = true
		_started = false
		print("SurvivalEnemyGroup: Timer ended and all enemies defeated")
		enemies_defeated.emit()


func _resolve_containers() -> void:
	var time_enemies := get_node_or_null(^"TimeEnemies") as Node
	if time_enemies != null:
		_enemies_parent = time_enemies.get_node_or_null(^"Enemies")
	else:
		_enemies_parent = get_node_or_null(^"Enemies")
	if _enemies_parent == null:
		push_warning("SurvivalEnemyGroup: Missing Enemies container under %s" % str(get_path()))


func _cache_spawn_points() -> void:
	_spawn_point_nodes.clear()
	var time_enemies := get_node_or_null(^"TimeEnemies") as Node
	var spawn_root: Node = null
	if time_enemies != null:
		spawn_root = time_enemies.get_node_or_null(^"SpawnPoints")
	else:
		spawn_root = get_node_or_null(^"SpawnPoints")
	if spawn_root == null:
		return
	for child in spawn_root.get_children():
		if child is Node3D:
			_spawn_point_nodes.append(child as Node3D)


func _spawn_one() -> void:
	if not is_instance_valid(_enemies_parent) or _spawn_point_nodes.is_empty():
		return
	var marker := _spawn_point_nodes[randi() % _spawn_point_nodes.size()]
	var enemy := enemy_scene.instantiate() as EnemyLocal
	_enemies_parent.add_child(enemy)
	enemy.global_transform = marker.global_transform
	enemy.is_offensive = true


func _clear_spawned_enemies() -> void:
	if not is_instance_valid(_enemies_parent):
		return
	for child in _enemies_parent.get_children():
		if child is EnemyLocal:
			child.queue_free()


func _all_spawned_dead() -> bool:
	if not is_instance_valid(_enemies_parent):
		return true
	for child in _enemies_parent.get_children():
		if child is EnemyLocal:
			if (child as EnemyLocal).is_alive():
				return false
	return true
