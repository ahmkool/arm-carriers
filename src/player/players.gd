class_name Players
extends Node

const SPAWN_POSITION_BY_DEVICE := {
	0: Vector3(0, 0, 0),
	1: Vector3(1, 0, 0),
}

@export var checkpoint_manager_path: NodePath = NodePath("../CheckpointManager")

var main_player_index = -1

## Character model for each device_id. Change these to swap who players play as.
@export var character_scenes: Array[PackedScene] = []

const PLAYER_SCENE := preload("res://src/player/player_local.tscn")


## Runs before the children enter the tree, so the players placed in the scene get their character in time.
func _enter_tree() -> void:
	for child in get_children():
		var player := child as PlayerLocal
		if player == null:
			continue
		player.character_scene = _get_character_scene_for_device(player.device_id)


func add_player(device_id: int):
	#Check that the player is not already added
	for player in get_children():
		if player.device_id == device_id:
			return
	var player = PLAYER_SCENE.instantiate()
	player.device_id = device_id
	player.character_scene = _get_character_scene_for_device(device_id)
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


func _get_character_scene_for_device(device_id: int) -> PackedScene:
	var picked := CharacterRoster.scene_for_device(device_id)
	if picked != null:
		return picked
	if device_id < 0 or device_id >= character_scenes.size():
		_fail_invalid_character_scene(device_id, "device_id is out of range for character_scenes")
		return null
	var scene := character_scenes[device_id]
	if scene == null:
		_fail_invalid_character_scene(device_id, "character_scenes entry is null")
		return null
	return scene


func _fail_invalid_character_scene(device_id: int, reason: String) -> void:
	push_error(
		"Players: cannot set character for device_id %s — %s (configured scenes: %s)"
		% [device_id, reason, character_scenes.size()]
	)
	get_tree().quit(1)
