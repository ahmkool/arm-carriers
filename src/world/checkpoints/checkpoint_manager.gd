class_name CheckpointManager
extends Node

@export var current_checkpoint: Checkpoint

signal checkpoint_changed(new_checkpoint: Checkpoint, previous_checkpoint: Checkpoint, entered_by: Node)

var _checkpoints: Array[Checkpoint] = []

# Called when the node enters the scene tree for the first time.
func _ready():
	_refresh_checkpoints()
	if current_checkpoint == null and not _checkpoints.is_empty():
		# Default to the first checkpoint found, so other systems can query immediately.
		current_checkpoint = _checkpoints[0]

func register_checkpoint(checkpoint: Checkpoint) -> void:
	if checkpoint == null:
		return
	if _checkpoints.has(checkpoint):
		return
	_checkpoints.append(checkpoint)
	if current_checkpoint == null:
		current_checkpoint = checkpoint


func unregister_checkpoint(checkpoint: Checkpoint) -> void:
	if checkpoint == null:
		return
	_checkpoints.erase(checkpoint)
	if current_checkpoint == checkpoint:
		current_checkpoint = _checkpoints[0] if not _checkpoints.is_empty() else null


func set_current_checkpoint(checkpoint: Checkpoint, entered_by: Node = null) -> void:
	if checkpoint == null:
		return
	if current_checkpoint == checkpoint:
		return
	var previous := current_checkpoint
	current_checkpoint = checkpoint
	checkpoint_changed.emit(current_checkpoint, previous, entered_by)


func get_spawn_transform() -> Transform3D:
	if current_checkpoint == null:
		return Transform3D.IDENTITY
	return current_checkpoint.get_spawn_transform()


func get_shooter_transform() -> Transform3D:
	if current_checkpoint == null:
		return Transform3D.IDENTITY
	return current_checkpoint.get_shooter_transform()


func _refresh_checkpoints() -> void:
	_checkpoints.clear()
	for child in get_children():
		var checkpoint := child as Checkpoint
		if checkpoint == null:
			continue
		_checkpoints.append(checkpoint)
