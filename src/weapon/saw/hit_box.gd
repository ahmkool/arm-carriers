extends Area3D

@export var damage: int = 1
@export var hit_cooldown_seconds: float = 1.0

@onready var _hit_sfx: AudioStreamPlayer3D = $AudioStreamPlayer3D

const PITCH_MIN := 0.88
const PITCH_MAX := 1.12
const OVERLAP_CHECK_INTERVAL := 0.1

var _last_hit_msec_by_enemy: Dictionary = {}


func _ready() -> void:
	body_exited.connect(_on_hit_area_body_exited)
	_setup_overlap_check_timer()


func _on_hit_area_body_entered(body: Node) -> void:
	_try_hit_enemy(body)


func _on_hit_area_body_exited(body: Node) -> void:
	if body is not EnemyLocal:
		return
	_last_hit_msec_by_enemy.erase(body.get_instance_id())


func _check_overlapping_enemies() -> void:
	for body in get_overlapping_bodies():
		_try_hit_enemy(body)


func _try_hit_enemy(body: Node) -> bool:
	if not _can_hit_enemy(body):
		return false
	if not Health.apply_damage(body, damage, global_position):
		return false
	_last_hit_msec_by_enemy[body.get_instance_id()] = Time.get_ticks_msec()
	_play_hit_sfx()
	return true


func _can_hit_enemy(body: Node) -> bool:
	if body is not EnemyLocal:
		return false
	var enemy_id := body.get_instance_id()
	var last_hit_msec: int = _last_hit_msec_by_enemy.get(enemy_id, -999999)
	var cooldown_msec := int(hit_cooldown_seconds * 1000.0)
	return Time.get_ticks_msec() - last_hit_msec >= cooldown_msec


func _setup_overlap_check_timer() -> void:
	var timer := Timer.new()
	timer.wait_time = OVERLAP_CHECK_INTERVAL
	timer.autostart = true
	timer.timeout.connect(_check_overlapping_enemies)
	add_child(timer)


func _play_hit_sfx() -> void:
	_hit_sfx.pitch_scale = randf_range(PITCH_MIN, PITCH_MAX)
	_hit_sfx.play()
