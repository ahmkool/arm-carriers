class_name AxeFireSlashTrail
extends Node3D

const LIFETIME_SEC := 3.0
const MOVE_SPEED_MAX := 5.0
const MOVE_SPEED_START_RATIO := 0.04
const DAMAGE := 1

var _direction := Vector3.FORWARD
var _elapsed := 0.0
var _moving := false
var _damaged_player_ids: Array[int] = []


func launch(direction: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		flat = Vector3.FORWARD
	_direction = flat.normalized()
	_align_to_direction()
	_moving = true
	set_process(true)
	call_deferred("_hurt_initial_overlaps")


func _ready() -> void:
	set_process(false)


func _hurt_initial_overlaps() -> void:
	var area := get_node_or_null("Area3D") as Area3D
	if area == null:
		return
	for body in area.get_overlapping_bodies():
		_on_body_collision(body as Node3D)


func _on_body_collision(body: Node3D) -> void:
	var player := body as PlayerLocal
	if player == null or player.is_dead:
		return
	var player_id := player.get_instance_id()
	if _damaged_player_ids.has(player_id):
		return
	_damaged_player_ids.append(player_id)
	CameraFeedback.add_trauma_hurt()
	Health.apply_damage(player, DAMAGE, global_position)


func _process(delta: float) -> void:
	if not _moving:
		return
	global_position += _direction * _current_move_speed() * delta
	_elapsed += delta
	if _elapsed < LIFETIME_SEC:
		return
	queue_free()


func _current_move_speed() -> float:
	var t := clampf(_elapsed / LIFETIME_SEC, 0.0, 1.0)
	var eased := t * t
	var start_speed := MOVE_SPEED_MAX * MOVE_SPEED_START_RATIO
	return lerpf(start_speed, MOVE_SPEED_MAX, eased)


func _align_to_direction() -> void:
	look_at(global_position + _direction, Vector3.UP)
