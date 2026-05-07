extends Camera3D

@export var follow_offset: Vector3 = Vector3(0.0, 7.0, 9.0)
@export var follow_smooth_speed: float = 8.0
@export var zoom_per_unit: float = 0.6
@export var max_zoom_out: float = 14.0
@export var aim_target_distance: float = 9.0

var players: Node
var bazooka: Bazooka


func _ready():
	# Camera starts with the desired tilt from the scene transform,
	# then only follows translation.
	_find_players_node()
	_find_bazooka_node()


func _process(delta):
	if not is_instance_valid(players):
		_find_players_node()
		return
	if not is_instance_valid(bazooka):
		_find_bazooka_node()

	var player_positions := _get_player_positions()
	if player_positions.is_empty():
		return
	if _is_jointly_carrying_bazooka():
		player_positions.append(_get_aim_target_position())

	var midpoint = _get_midpoint(player_positions)
	var spread = _get_max_distance_from(midpoint, player_positions)
	var zoom_amount = min(spread * zoom_per_unit, max_zoom_out)
	var desired_position = midpoint + follow_offset + follow_offset.normalized() * zoom_amount
	global_position = global_position.lerp(desired_position, clampf(follow_smooth_speed * delta, 0.0, 1.0))


func _find_players_node() -> void:
	var found_players := get_node_or_null("../Players")
	if found_players == null:
		return
	players = found_players


func _find_bazooka_node() -> void:
	var found_bazooka := get_node_or_null("../Weapon/Bazooka")
	if found_bazooka == null:
		return
	bazooka = found_bazooka as Bazooka


func _get_player_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for child in players.get_children():
		if child is Node3D:
			positions.append(child.global_position)
	return positions


func _is_jointly_carrying_bazooka() -> bool:
	if not is_instance_valid(bazooka):
		return false
	var carry_info = bazooka.get_carry_info()
	return is_instance_valid(carry_info.shooter_player) and is_instance_valid(carry_info.direction_setter_player)


func _get_aim_target_position() -> Vector3:
	if not is_instance_valid(bazooka):
		return Vector3.ZERO
	var muzzle := bazooka.get_node_or_null("Muzzle") as Marker3D
	if muzzle == null:
		return bazooka.global_position
	var forward := muzzle.global_transform.basis.z.normalized()
	return muzzle.global_position + (forward * aim_target_distance)


func _get_midpoint(positions: Array[Vector3]) -> Vector3:
	var sum := Vector3.ZERO
	for position in positions:
		sum += position
	return sum / float(positions.size())


func _get_max_distance_from(point: Vector3, positions: Array[Vector3]) -> float:
	var max_distance := 0.0
	for position in positions:
		max_distance = maxf(max_distance, point.distance_to(position))
	return max_distance
