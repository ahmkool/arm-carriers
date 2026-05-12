class_name NormalEnemyGroup
extends EnemyGroup

var signal_emitted := false

var enemy_scene: PackedScene = preload("res://src/enemy/enemy_local.tscn")

var initial_positions: Array[Vector3]
var initial_rotations: Array[Quaternion]
var initial_is_offensives: Array[bool]

## Parent of [EnemyLocal] instances. Prefer a child named InstancedEnemies; falls back to this node for older scenes.
var _enemy_instances_parent: Node


func _ready() -> void:
	_enemy_instances_parent = get_node_or_null(^"InstancedEnemies") as Node
	if _enemy_instances_parent == null:
		_enemy_instances_parent = self
	for enemy in _list_enemy_locals():
		initial_positions.append(enemy.global_position)
		#initial_rotations.append(enemy.global_rotation)
		initial_is_offensives.append(enemy.is_offensive)


func trigger(offensive: bool = true) -> void:
	for enemy in _list_enemy_locals():
		enemy.is_offensive = offensive


func reset() -> void:
	signal_emitted = false
	for enemy in _list_enemy_locals():
		enemy.queue_free()
	for i in range(initial_positions.size()):
		var enemy := enemy_scene.instantiate() as EnemyLocal
		_enemy_instances_parent.add_child(enemy)
		enemy.global_position = initial_positions[i]
		#enemy.global_rotation = initial_rotations[i]
		enemy.is_offensive = initial_is_offensives[i]


func _physics_process(_delta: float) -> void:
	if signal_emitted:
		return
	var alive_enemies := _list_enemy_locals().filter(func(enemy: EnemyLocal) -> bool: return enemy.is_alive())
	if alive_enemies.is_empty():
		signal_emitted = true
		print("NormalEnemyGroup: All enemies defeated")
		enemies_defeated.emit()


func mark_as_defeated() -> void:
	for enemy in _list_enemy_locals():
		enemy.queue_free()
	signal_emitted = true


func _list_enemy_locals() -> Array[EnemyLocal]:
	var out: Array[EnemyLocal] = []
	for child in _enemy_instances_parent.get_children():
		if child is EnemyLocal:
			out.append(child as EnemyLocal)
	return out
