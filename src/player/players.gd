class_name Players
extends Node

const SPAWN_POSITION_BY_DEVICE := {
	0: Vector3(0, 0, 0),
	1: Vector3(1, 0, 0),
}

@export var checkpoint_manager_path: NodePath = NodePath("../CheckpointManager")

var main_player_index = -1
var player_scene: PackedScene = preload("res://src/player/player_local.tscn")

func add_player(device_id: int):
	#Check that the player is not already added
	for player in get_children():
		if player.device_id == device_id:
			return
	var player = player_scene.instantiate()
	player.device_id = device_id
	print("Adding player ", device_id)
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
