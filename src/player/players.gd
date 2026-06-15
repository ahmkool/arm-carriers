class_name Players
extends Node

const SPAWN_POSITION_BY_DEVICE := {
	0: Vector3(0, 0, 0),
	1: Vector3(1, 0, 0),
}

@export var checkpoint_manager_path: NodePath = NodePath("../CheckpointManager")

var main_player_index = -1

@export var player_scenes: Array[PackedScene] = [
	preload("res://src/player/player_local.tscn"),
	preload("res://src/player/player_local_02.tscn"),
]

func add_player(device_id: int):
	#Check that the player is not already added
	for player in get_children():
		if player.device_id == device_id:
			return
	var scene := _get_player_scene_for_device(device_id)
	var player = scene.instantiate()
	player.device_id = device_id
	add_child(player)
	_apply_spawn_for_device(player, device_id)
	if main_player_index == -1:
		main_player_index = player.player_id


func reset_players_to_spawn() -> void:
	for child in get_children():
		var pl := child as PlayerLocal
		if pl == null:
			continue
		_apply_spawn_for_device(pl, pl.player_id)
		pl.revive()


func _apply_spawn_for_device(player: Node3D, device_id: int) -> void:
	var local_offset = SPAWN_POSITION_BY_DEVICE.get(device_id, Vector3.ZERO)
	var manager = _get_checkpoint_manager()
	if manager != null and manager.has_method("get_spawn_transform"):
		var spawn_transform: Transform3D = manager.call("get_spawn_transform")
		player.global_position = spawn_transform.origin + local_offset
		player.global_rotation = spawn_transform.basis.get_euler()
		return

	player.global_position = local_offset


func _get_checkpoint_manager() -> Node:
	if checkpoint_manager_path == NodePath():
		return null
	return get_node_or_null(checkpoint_manager_path)


func _get_player_scene_for_device(device_id: int) -> PackedScene:
	if device_id < 0 or device_id >= player_scenes.size():
		_fail_invalid_player_scene(device_id, "device_id is out of range for player_scenes")
		return null
	var scene := player_scenes[device_id]
	if scene == null:
		_fail_invalid_player_scene(device_id, "player_scenes entry is null")
		return null
	return scene


func _fail_invalid_player_scene(device_id: int, reason: String) -> void:
	push_error(
		"Players: cannot spawn device_id %s — %s (configured scenes: %s)"
		% [device_id, reason, player_scenes.size()]
	)
	get_tree().quit(1)
