class_name SurvivalEnemyGroup
extends EnemyGroup

const SURVIVAL_TIMER_PATH := "UI/SurvivalTimer"

@export var enemy_scene: PackedScene = preload("res://src/enemy/enemy_local.tscn")
@export var spawner_scene: PackedScene = preload("res://src/enemy/spawn/enemy_spawner.tscn")
@export var spawn_interval_curve: Curve
@export_range(0.1, 600.0, 0.1) var fight_duration: float = 60.0
## Shows the HUD countdown (UI/SurvivalTimer) while this wave runs.
@export var show_timer_ui := true
## Max HP given to each spawned enemy. 0 keeps the enemy scene's own.
@export_range(0, 999) var enemy_max_hp := 0
## Keeps spawning past fight_duration until stop() is called (StopSurvivalEvent), then ends like a timed wave:
## enemies_defeated once the ones left are dead. The interval curve still ramps over fight_duration, then holds its
## last value. Turn show_timer_ui off: there's no countdown.
@export var endless := false
## No spawn while this many spawned enemies are alive, so a long endless wave can't pile up. 0: no cap.
@export_range(0, 200) var max_alive := 0

var signal_emitted := false

var _started := false
var _stopped := false
var _fight_elapsed := 0.0
var _spawn_timer := 0.0

var _enemies_parent: Node
var _spawn_point_nodes: Array[Node3D] = []
var _spawn_polygon_nodes: Array[Node3D] = []


func _ready() -> void:
	_resolve_containers()
	_cache_spawn_sources()
	_validate_spawn_interval_curve()


func trigger(offensive: bool = true) -> void:
	if signal_emitted or not offensive:
		return
	if _started:
		return
	_started = true
	_fight_elapsed = 0.0
	_spawn_timer = 0.0
	_spawn_one()
	_bind_timer_ui()


## True from trigger until the wave is cleared or reset.
func is_running() -> bool:
	return _started and not signal_emitted


## Ends an endless wave's spawning; enemies_defeated follows once the ones left are dead.
func stop() -> void:
	_stopped = true


## True while new enemies can still appear.
func is_spawning() -> bool:
	return is_running() and not _spawning_over()


func get_time_remaining() -> float:
	return maxf(fight_duration - _fight_elapsed, 0.0)


func _bind_timer_ui() -> void:
	if not show_timer_ui:
		return
	var world := LevelNodes.find_world(self)
	if world == null:
		return
	var timer_ui := world.get_node_or_null(SURVIVAL_TIMER_PATH) as SurvivalTimer
	if timer_ui == null:
		return
	timer_ui.bind(self)


func reset() -> void:
	signal_emitted = false
	_started = false
	_stopped = false
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
	_process_spawning()
	if not _fight_ended_and_cleared():
		return
	signal_emitted = true
	_started = false
	print("SurvivalEnemyGroup: Timer ended and all enemies defeated")
	enemies_defeated.emit()


func _process_spawning() -> void:
	if _spawning_over():
		return
	if max_alive > 0 and _alive_count() >= max_alive:
		_spawn_timer = minf(_spawn_timer, _spawn_interval_at(_fight_elapsed))
		return
	var interval := _spawn_interval_at(_fight_elapsed)
	if _spawn_timer < interval:
		return
	_spawn_timer -= interval
	_spawn_one()


func _spawn_interval_at(elapsed: float) -> float:
	if spawn_interval_curve == null or spawn_interval_curve.get_point_count() == 0:
		return 120.0
	if fight_duration <= 0.0:
		return clampf(spawn_interval_curve.sample(0.0), 0.05, 120.0)
	var t := clampf(elapsed / fight_duration, 0.0, 1.0)
	return clampf(spawn_interval_curve.sample(t), 0.05, 120.0)


func _validate_spawn_interval_curve() -> void:
	if spawn_interval_curve == null:
		push_warning("SurvivalEnemyGroup: spawn_interval_curve is required on %s" % str(get_path()))
		return
	if spawn_interval_curve.get_point_count() == 0:
		push_warning("SurvivalEnemyGroup: spawn_interval_curve has no points on %s" % str(get_path()))


func _fight_ended_and_cleared() -> bool:
	if not _spawning_over():
		return false
	return _all_spawned_dead()


func _spawning_over() -> bool:
	if endless:
		return _stopped
	return _fight_elapsed >= fight_duration


func _alive_count() -> int:
	if not is_instance_valid(_enemies_parent):
		return 0
	return _enemies_parent.get_children().filter(func(c): return c is EnemyLocal and (c as EnemyLocal).is_alive()).size()


func _resolve_containers() -> void:
	var time_enemies := get_node_or_null(^"TimeEnemies") as Node
	if time_enemies != null:
		_enemies_parent = time_enemies.get_node_or_null(^"Enemies")
	else:
		_enemies_parent = get_node_or_null(^"Enemies")
	if _enemies_parent == null:
		push_warning("SurvivalEnemyGroup: Missing Enemies container under %s" % str(get_path()))


func _cache_spawn_sources() -> void:
	_spawn_point_nodes.clear()
	_spawn_polygon_nodes.clear()
	var spawn_points_root := _spawn_config_root(^"SpawnPoints")
	if spawn_points_root != null:
		_cache_node3d_children(spawn_points_root, _spawn_point_nodes)
	var spawn_polygons_root := _spawn_config_root(^"SpawnPolygons")
	if spawn_polygons_root == null:
		return
	for child in spawn_polygons_root.get_children():
		if child is Node3D:
			_spawn_polygon_nodes.append(child as Node3D)


func _spawn_config_root(child_name: NodePath) -> Node:
	var time_enemies := get_node_or_null(^"TimeEnemies") as Node
	if time_enemies != null:
		return time_enemies.get_node_or_null(child_name)
	return get_node_or_null(child_name)


func _cache_node3d_children(root: Node, out: Array[Node3D]) -> void:
	for child in root.get_children():
		if child is Node3D:
			out.append(child as Node3D)


func _has_spawn_sources() -> bool:
	return not _spawn_point_nodes.is_empty() or not _spawn_polygon_nodes.is_empty()


func _spawn_one() -> void:
	print("Spawn enemy at %.2f s" % _fight_elapsed)
	if not is_instance_valid(_enemies_parent) or not _has_spawn_sources():
		return
	if spawner_scene == null:
		return
	var enemy := enemy_scene.instantiate() as EnemyLocal
	_apply_max_hp(enemy)
	_enemies_parent.add_child(enemy)
	enemy.global_transform = _pick_spawn_transform()
	enemy.is_offensive = true


## Set before the enemy enters the tree, so its Health fills up to the new max in _ready.
func _apply_max_hp(enemy: EnemyLocal) -> void:
	if enemy_max_hp <= 0:
		return
	var health := Health.from_target(enemy)
	if health == null:
		return
	health.max_hp = enemy_max_hp


func _pick_spawn_transform() -> Transform3D:
	var source_count := _spawn_point_nodes.size() + _spawn_polygon_nodes.size()
	var index := randi() % source_count
	if index < _spawn_point_nodes.size():
		return _rotation_only_transform(_spawn_point_nodes[index])
	var polygon := _spawn_polygon_nodes[index - _spawn_point_nodes.size()]
	return _spawn_transform_in_polygon(polygon)


func _rotation_only_transform(source: Node3D) -> Transform3D:
	return Transform3D(source.global_basis.orthonormalized(), source.global_position)


func _spawn_transform_in_polygon(polygon: Node3D) -> Transform3D:
	var vertices := _polygon_vertices(polygon)
	if vertices.size() < 3:
		push_warning(
			"SurvivalEnemyGroup: Polygon %s needs at least 3 vertex nodes" % str(polygon.get_path())
		)
		return _rotation_only_transform(polygon)
	var position := _random_point_in_polygon_vertices(vertices)
	return Transform3D(polygon.global_basis.orthonormalized(), position)


func _polygon_vertices(polygon: Node3D) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for child in polygon.get_children():
		if child is not Node3D:
			continue
		out.append((child as Node3D).global_position)
	return out


func _random_point_in_polygon_vertices(vertices: Array[Vector3]) -> Vector3:
	if vertices.size() == 3:
		return _random_point_in_triangle(vertices[0], vertices[1], vertices[2])
	if randf() < 0.5:
		return _random_point_in_triangle(vertices[0], vertices[1], vertices[2])
	return _random_point_in_triangle(vertices[0], vertices[2], vertices[3])


func _random_point_in_triangle(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var r1 := randf()
	var r2 := randf()
	if r1 + r2 > 1.0:
		r1 = 1.0 - r1
		r2 = 1.0 - r2
	return a + r1 * (b - a) + r2 * (c - a)


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
