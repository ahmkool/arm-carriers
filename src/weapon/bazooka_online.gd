extends Node3D

@export var carry_distance: float = 2.2
@export var carry_height: float = 0.55
@export var ground_y: float = 0.35
@export var bullet_scene: PackedScene = preload("res://src/weapon/bazooka_bullet.tscn")

var _is_carried: bool = false

@onready var _spawn_location: Node3D = get_node_or_null("../SpawnLocation")
@onready var _muzzle: Marker3D = get_node_or_null("Muzzle")

func _ready():
	_drop_to_ground()


func _process(_delta):
	var players := _get_two_players()
	if players.size() < 2:
		_is_carried = false
		_drop_to_ground()
		return

	var p1: Node3D = players[0]
	var p2: Node3D = players[1]
	var midpoint := (p1.global_position + p2.global_position) * 0.5
	var are_close_enough := p1.global_position.distance_to(p2.global_position) <= carry_distance

	if are_close_enough:
		_is_carried = true
		global_position = midpoint + Vector3.UP * carry_height
		var flat_target := Vector3(p2.global_position.x, global_position.y, p2.global_position.z)
		if flat_target.distance_squared_to(global_position) > 0.0001:
			look_at(flat_target, Vector3.UP)
	else:
		_is_carried = false
		_drop_to_ground()

	if _is_carried and Input.is_action_just_pressed("ui_accept"):
		_request_fire_bullet()


func _get_two_players() -> Array[Node3D]:
	if _spawn_location == null:
		return []

	var players: Array[Node3D] = []
	for child in _spawn_location.get_children():
		if child is Node3D:
			players.append(child)
		if players.size() == 2:
			break
	return players


func _drop_to_ground() -> void:
	global_position.y = ground_y


func _request_fire_bullet() -> void:
	if _muzzle == null:
		return
	if multiplayer.is_server():
		_spawn_bullet_on_all.rpc(_muzzle.global_position, -_muzzle.global_transform.basis.z)
	else:
		_fire_bullet_request.rpc_id(1)


@rpc("any_peer", "reliable")
func _fire_bullet_request() -> void:
	if not multiplayer.is_server():
		return
	if not _is_carried or _muzzle == null:
		return
	_spawn_bullet_on_all.rpc(_muzzle.global_position, -_muzzle.global_transform.basis.z)


@rpc("authority", "call_local", "reliable")
func _spawn_bullet_on_all(spawn_pos: Vector3, shoot_direction: Vector3) -> void:
	if bullet_scene == null:
		return

	var bullet := bullet_scene.instantiate() as Node3D
	if bullet == null:
		return

	get_tree().current_scene.add_child(bullet)
	bullet.global_position = spawn_pos

	if bullet.has_method("setup"):
		bullet.call("setup", shoot_direction)
