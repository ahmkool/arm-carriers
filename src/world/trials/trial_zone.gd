class_name TrialZone
extends Node3D

signal trial_started
signal trial_finished

@export var enemy_scene: PackedScene = preload("res://src/enemy/enemy_local.tscn")
@export_range(1.0, 600.0, 1.0) var trial_duration_seconds := 60.0
@export_range(0.1, 10.0, 0.1) var spawn_interval_seconds := 2.0

@onready var spawn_zones: Node = $SpawnZones

var _is_active := false
var _remaining_time := 0.0
var _spawn_cooldown := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()

func _process(delta: float) -> void:
	if not _is_active:
		return

	_remaining_time -= delta
	_spawn_cooldown -= delta

	if _spawn_cooldown <= 0.0:
		_spawn_enemy()
		_spawn_cooldown = spawn_interval_seconds

	if _remaining_time <= 0.0:
		_finish_trial()

func _on_trigger_zone_body_entered(body: Node3D) -> void:
	if _is_active:
		return
	if body is not PlayerLocal:
		return
	_start_trial()

func _start_trial() -> void:
	_is_active = true
	_remaining_time = trial_duration_seconds
	_spawn_cooldown = 0.0
	trial_started.emit()

func _finish_trial() -> void:
	_is_active = false
	trial_finished.emit()

func _spawn_enemy() -> void:
	if enemy_scene == null:
		return
	var enemies_root := get_tree().current_scene.get_node_or_null("Enemies")
	if enemies_root == null:
		return

	var enemy_instance := enemy_scene.instantiate()
	var enemy_node := enemy_instance as Node3D
	if enemy_node == null:
		return

	enemies_root.add_child(enemy_instance)
	enemy_node.global_position = _pick_spawn_position()

func _pick_spawn_position() -> Vector3:
	if spawn_zones == null:
		return global_position

	var areas: Array[Area3D] = []
	for child in spawn_zones.get_children():
		var area := child as Area3D
		if area != null:
			areas.append(area)
	if areas.is_empty():
		return spawn_zones.global_position

	var area: Area3D = areas[_rng.randi_range(0, areas.size() - 1)]
	var shapes := _collision_shapes_in_area(area)
	if shapes.is_empty():
		return area.global_position

	var collision_shape: CollisionShape3D = shapes[_rng.randi_range(0, shapes.size() - 1)]
	if collision_shape.shape == null:
		return collision_shape.global_position

	var box_shape := collision_shape.shape as BoxShape3D
	if box_shape != null:
		var half_size := box_shape.size * 0.5
		var local_point := Vector3(
			_rng.randf_range(-half_size.x, half_size.x),
			_rng.randf_range(-half_size.y, half_size.y),
			_rng.randf_range(-half_size.z, half_size.z)
		)
		return collision_shape.global_transform * local_point

	return collision_shape.global_position


func _collision_shapes_in_area(area: Area3D) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for node in area.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node != null:
			out.append(shape_node)
	return out


func reset() -> void:
	_is_active = false
	_remaining_time = 0.0
	_spawn_cooldown = 0.0
	for child in get_children():
		var enemy := child as EnemyLocal
		if enemy is not EnemyLocal:
			continue
		enemy.queue_free()
