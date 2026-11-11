class_name NormalEnemyGroup
extends EnemyGroup

## Keeps this group's enemies out of the level until [method trigger] is called with offensive on. Use it for a
## group that waits for the players further on, so they can't see it or kill it from an earlier section (and so
## an early kill can't fire [signal EnemyGroup.enemies_defeated] before the fight). The enemies appear where they
## were placed in the editor, in a puff, already offensive. A checkpoint reset puts the group back to not spawned,
## so the area or event that triggers it must be able to fire again (list it in the checkpoint's areas_to_reactivate).
@export var spawn_on_trigger := false

var signal_emitted := false

const _SNAPSHOT_FLAGS := Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_USE_INSTANTIATION
const _SPAWN_PUFF_SCENE := preload("res://src/vfx/puff_disappear.tscn")
const _SPAWN_PUFF_FREE_SEC := 1.5
const _SPAWN_PUFF_HEIGHT := 1.0

## Editor-placed enemy templates (scene type, children, overrides) captured at ready.
var _enemy_snapshots: Array[Node] = []

## Parent of [EnemyLocal] instances. Prefer a child named InstancedEnemies; falls back to this node for older scenes.
var _enemy_instances_parent: Node

## False while a [member spawn_on_trigger] group is waiting to be triggered: it has no enemies and can't be defeated.
var _is_spawned := true


func _ready() -> void:
	_enemy_instances_parent = get_node_or_null(^"InstancedEnemies") as Node
	if _enemy_instances_parent == null:
		_enemy_instances_parent = self
	for enemy in _list_enemy_locals():
		_enemy_snapshots.append(enemy.duplicate(_SNAPSHOT_FLAGS))
	if not spawn_on_trigger:
		return
	_free_enemies()
	_is_spawned = false


func trigger(offensive: bool = true) -> void:
	if _should_spawn_on(offensive):
		_spawn_from_snapshots(true)
	for enemy in _list_enemy_locals():
		enemy.is_offensive = offensive


func reset() -> void:
	signal_emitted = false
	_free_enemies()
	if spawn_on_trigger:
		_is_spawned = false
		return
	_spawn_from_snapshots(false)


func _physics_process(_delta: float) -> void:
	if signal_emitted:
		return
	if not _is_spawned:
		return
	var alive_enemies := _list_enemy_locals().filter(func(enemy: EnemyLocal) -> bool: return enemy.is_alive())
	if alive_enemies.is_empty():
		signal_emitted = true
		print("NormalEnemyGroup: All enemies defeated")
		enemies_defeated.emit()


func mark_as_defeated() -> void:
	_free_enemies()
	signal_emitted = true


func _should_spawn_on(offensive: bool) -> bool:
	if not offensive:
		return false
	if signal_emitted:
		return false
	return not _is_spawned


func _spawn_from_snapshots(with_puff: bool) -> void:
	_is_spawned = true
	for snapshot in _enemy_snapshots:
		var enemy := snapshot.duplicate(_SNAPSHOT_FLAGS) as Node3D
		_enemy_instances_parent.add_child(enemy)
		if with_puff:
			_play_spawn_puff(enemy.global_position)


func _play_spawn_puff(at: Vector3) -> void:
	var puff := _SPAWN_PUFF_SCENE.instantiate() as GPUParticles3D
	add_child(puff)
	puff.global_position = at + Vector3.UP * _SPAWN_PUFF_HEIGHT
	puff.emitting = true
	get_tree().create_timer(_SPAWN_PUFF_FREE_SEC).timeout.connect(puff.queue_free, CONNECT_ONE_SHOT)


func _free_enemies() -> void:
	for enemy in _list_enemy_locals():
		enemy.queue_free()


## Skips enemies already queued for freeing, so the group reads as empty straight after [method _free_enemies].
func _list_enemy_locals() -> Array[EnemyLocal]:
	var out: Array[EnemyLocal] = []
	for child in _enemy_instances_parent.get_children():
		if child is EnemyLocal and not child.is_queued_for_deletion():
			out.append(child as EnemyLocal)
	return out
