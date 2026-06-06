class_name CheckpointManager
extends Node

@export var current_checkpoint: Checkpoint

signal checkpoint_changed(new_checkpoint: Checkpoint, previous_checkpoint: Checkpoint, entered_by: Node)

var _checkpoints: Array[Checkpoint] = []

func _ready() -> void:
	_refresh_checkpoints()
	_apply_saved_progress()
	if current_checkpoint == null and not _checkpoints.is_empty():
		current_checkpoint = _checkpoints[0]
	_connect_save_tracking()


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


func set_current_checkpoint_silent(checkpoint: Checkpoint) -> void:
	if checkpoint == null:
		return
	current_checkpoint = checkpoint


func get_checkpoint_by_id(id: String) -> Checkpoint:
	if id.is_empty():
		return null
	for checkpoint in _checkpoints:
		if checkpoint.get_save_id() == id:
			return checkpoint
	for checkpoint in _checkpoints:
		if checkpoint.name == id:
			return checkpoint
	return null


func apply_saved_checkpoint(id: String) -> void:
	if id.is_empty():
		return
	var checkpoint := get_checkpoint_by_id(id)
	if checkpoint == null:
		push_warning("CheckpointManager: unknown saved checkpoint '%s'." % id)
		return
	set_current_checkpoint_silent(checkpoint)


func get_progress_order(checkpoint: Checkpoint) -> int:
	if checkpoint == null:
		return -1
	if checkpoint.order != 0:
		return checkpoint.order
	var index := _checkpoints.find(checkpoint)
	if index < 0:
		return -1
	return index


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


func _apply_saved_progress() -> void:
	var world := get_parent() as WorldLocal
	if world == null:
		return
	if world.skip_save:
		return
	var level_id: String = world.get_level_id()
	if level_id.is_empty():
		return
	if not GameSave.consume_apply_save_on_next_load():
		return
	GameSave.apply_to_manager(self, level_id)


func _connect_save_tracking() -> void:
	var world := get_parent() as WorldLocal
	if world == null:
		return
	if world.skip_save:
		return
	var level_id: String = world.get_level_id()
	if level_id.is_empty():
		return
	GameSave.track_manager(self, level_id)
