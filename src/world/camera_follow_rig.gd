class_name CameraFollowRig
extends Node3D

@export var follow_offset: Vector3 = Vector3(0.0, 7.0, 3.0)
@export var follow_smooth_speed: float = 8.0
@export var zoom_per_unit: float = 0.6
@export var max_zoom_out: float = 14.0
@export var aim_target_distance: float = 9.0

var players: Node
var big_weapon: BigWeapon

var _cutscene_active: bool = false


func _ready():
	_find_players_node()
	_find_big_weapon_node()


func _process(delta):
	if _cutscene_active:
		return
	if not is_instance_valid(players):
		_find_players_node()
		return
	if not is_instance_valid(big_weapon):
		_find_big_weapon_node()

	global_position = global_position.lerp(compute_desired_follow_position(), clampf(follow_smooth_speed * delta, 0.0, 1.0))


## World-space point the rig should frame (e.g. bridge midpoint); uses same offset as normal follow.
func run_focus_on_point(world_focal_point: Vector3, hold_sec: float, move_in_sec: float, move_out_sec: float) -> void:
	_cutscene_active = true
	var focus_dest := world_focal_point + follow_offset
	if follow_offset.length_squared() > 0.0001:
		focus_dest += follow_offset.normalized() * min(max_zoom_out * 0.35, 5.0)

	var tween_in := create_tween()
	tween_in.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween_in.tween_property(self, "global_position", focus_dest, move_in_sec)
	await tween_in.finished

	await get_tree().create_timer(hold_sec).timeout

	var elapsed_out := 0.0
	while elapsed_out < move_out_sec:
		await get_tree().process_frame
		elapsed_out += get_process_delta_time()
		global_position = global_position.lerp(
			compute_desired_follow_position(),
			clampf(follow_smooth_speed * get_process_delta_time(), 0.0, 1.0)
		)

	_cutscene_active = false


func compute_desired_follow_position() -> Vector3:
	if not is_instance_valid(players):
		_find_players_node()
	if not is_instance_valid(players):
		return global_position
	if not is_instance_valid(big_weapon):
		_find_big_weapon_node()

	var player_positions := _get_player_positions()
	if player_positions.is_empty():
		return global_position
	if _is_jointly_carrying_big_weapon():
		player_positions.append_array(_get_aim_target_positions())

	var midpoint := _get_midpoint(player_positions)
	var spread := _get_max_distance_from(midpoint, player_positions)
	var zoom_amount = min(spread * zoom_per_unit, max_zoom_out)
	return midpoint + follow_offset + follow_offset.normalized() * zoom_amount


func _find_players_node() -> void:
	var found_players := get_node_or_null("../Players")
	if found_players == null:
		return
	players = found_players


func _find_big_weapon_node() -> void:
	var found_big_weapon := get_node_or_null("../Weapon").get_child(0) as BigWeapon
	if found_big_weapon == null:
		return
	big_weapon = found_big_weapon


func _get_player_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for child in players.get_children():
		if child is Node3D:
			positions.append(child.global_position)
	return positions


func _is_jointly_carrying_big_weapon() -> bool:
	if not is_instance_valid(big_weapon):
		return false
	var pick_and_drop_handler: PickAndDropHandler = big_weapon.get_node("PickAndDropHandler")
	var carry_info = pick_and_drop_handler.get_carry_info()
	if pick_and_drop_handler == null:
		return false
	return is_instance_valid(carry_info.main_carrier) and is_instance_valid(carry_info.secondary_carrier)


func _get_aim_target_positions() -> Array[Vector3]:
	if not is_instance_valid(big_weapon):
		return []
	var camera_addons: Node3D = big_weapon.get_node("WeaponSpecifics/CameraAddons")
	if camera_addons == null:
		return []
	var positions: Array[Vector3] = []
	for child in camera_addons.get_children():
		if child is Marker3D:
			positions.append(child.global_position)
	return positions


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
