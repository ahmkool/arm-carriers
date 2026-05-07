extends Node3D

@export var move_speed: float = 1.5
@export var touch_distance: float = 0.7

var _target_player: Node3D = null

@onready var _spawn_location: Node3D = get_node_or_null("../../SpawnLocation")
@onready var _hit_area: Area3D = $Area3D
@onready var _game_state_manager: Node = get_node_or_null("../../GameStateManager")
@onready var _visual: Node3D = get_node_or_null("Skeleton_Warrior")

func _enter_tree():
	# Server (peer 1) owns enemy state for MultiplayerSynchronizer replication.
	set_multiplayer_authority(1)


func _ready():
	add_to_group("enemy")
	if _hit_area != null:
		_hit_area.body_entered.connect(_on_body_entered)
	_pick_target_player()


func _process(delta):
	if not multiplayer.is_server():
		return

	if _check_touching_any_player():
		return

	if _target_player == null or not is_instance_valid(_target_player):
		_pick_target_player()
		return

	var target_pos := _target_player.global_position
	var to_target := Vector3(
		target_pos.x - global_position.x,
		0.0,
		target_pos.z - global_position.z
	)

	if to_target.length_squared() > 0.0001:
		var direction := to_target.normalized()
		_face_walk_direction(direction)
		global_position += direction * move_speed * delta

	# Keep enemy on the same height as players.
	global_position.y = target_pos.y

	_check_touching_any_player()


func _face_walk_direction(direction: Vector3) -> void:
	if _visual == null:
		return
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		return
	flat = flat.normalized()
	_visual.look_at(_visual.global_position + flat, Vector3.UP)
	_visual.rotate_y(PI)


func _pick_target_player() -> void:
	if _spawn_location == null:
		_target_player = null
		return

	var players: Array[Node3D] = []
	for child in _spawn_location.get_children():
		if child is Node3D:
			players.append(child)

	if players.is_empty():
		_target_player = null
		return

	_target_player = players[randi() % players.size()]


func _on_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return

	if body == null:
		return
	if not (body is CharacterBody3D):
		return
	if _game_state_manager == null:
		return
	if not _game_state_manager.has_method("trigger_game_over"):
		return
	_game_state_manager.call("trigger_game_over")


func _check_touching_any_player() -> bool:
	if _spawn_location == null:
		return false

	var max_distance_sq := touch_distance * touch_distance
	for child in _spawn_location.get_children():
		var player := child as CharacterBody3D
		if player == null:
			continue
		if global_position.distance_squared_to(player.global_position) <= max_distance_sq:
			if _game_state_manager != null and _game_state_manager.has_method("trigger_game_over"):
				_game_state_manager.call("trigger_game_over")
			return true

	return false
