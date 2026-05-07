extends Node3D

var peer = ENetMultiplayerPeer.new()
@export var player_scene: PackedScene
const PORT = 8080
## Distance from the midpoint to each spawn (sphere centers are 2× this apart on the floor).
const HALF_SPAWN_SEPARATION := 1.0
var _spawn_pair_heading: float = 0.0

func _ready():
	# Preload the player scene so the server can spawn it
	player_scene = preload("res://src/player/online_player.tscn")
	_setup_overcooked_style_camera()

func _setup_overcooked_style_camera() -> void:
	pass
	# var cam := $Camera3D as Camera3D
	# Elevated corner, looking down at the play area (similar to Overcooked's 3/4 overhead view).
	# cam.position = Vector3(11.5, 14.0, 11.5)
	# cam.look_at(Vector3(0.0, 0.25, 0.0), Vector3.UP)
	# cam.fov = 52.0

func _on_host_button_pressed():
	# 1. Start the server
	peer.create_server(PORT)
	multiplayer.multiplayer_peer = peer
	
	# 2. Listen for clients connecting/disconnecting
	multiplayer.peer_connected.connect(_add_player)
	multiplayer.peer_disconnected.connect(_remove_player)
	
	# 3. Add the host's own player character
	_add_player(multiplayer.get_unique_id())
	
	# 4. Hide the menu
	$UI.hide()

func _on_join_button_pressed():
	# Connect to the local server
	peer.create_client("127.0.0.1", PORT)
	multiplayer.multiplayer_peer = peer
	$UI.hide()

func _add_player(id):
	var player = player_scene.instantiate()
	# The name MUST be the peer ID for the MultiplayerSynchronizer to know who owns it
	player.name = str(id)
	var index := $SpawnLocation.get_child_count()
	var pos: Vector3
	if index < 2:
		if index == 0:
			_spawn_pair_heading = randf() * TAU
		var dir := Vector3(cos(_spawn_pair_heading), 0.0, sin(_spawn_pair_heading))
		# Two players: opposite sides of the midpoint along `dir` (side-by-side, never same cell).
		var side := float(index * 2 - 1)
		pos = dir * (HALF_SPAWN_SEPARATION * side) + Vector3(0, 1, 0)
	else:
		pos = Vector3(randf_range(-3, 3), 1, randf_range(-3, 3))
	player.position = pos
	$SpawnLocation.add_child(player)

func _remove_player(id):
	var player_node = $SpawnLocation.get_node_or_null(str(id))
	if player_node:
		player_node.queue_free()
