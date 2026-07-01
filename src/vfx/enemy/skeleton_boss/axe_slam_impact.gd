extends Node3D

@export var damage: int = 1

const HIT_SOUND := preload("res://assets/sounds/damage.wav")

@onready var _hitbox: Area3D = $Hitbox

var _was_monitoring := false


func _ready() -> void:
	_was_monitoring = _hitbox.monitoring
	_hitbox.body_entered.connect(_on_hitbox_body_entered)


func _physics_process(_delta: float) -> void:
	if _hitbox.monitoring == _was_monitoring:
		return
	_was_monitoring = _hitbox.monitoring
	if not _hitbox.monitoring:
		return
	call_deferred("_hurt_overlapping_bodies")


func _on_hitbox_body_entered(body: Node) -> void:
	_apply_damage_to_body(body)


func _hurt_overlapping_bodies() -> void:
	if not _hitbox.monitoring:
		return
	for body in _hitbox.get_overlapping_bodies():
		_apply_damage_to_body(body)


func _apply_damage_to_body(body: Node) -> void:
	if body is not PlayerLocal:
		return
	var player := body as PlayerLocal
	if player == null:
		return
	if player.is_dead:
		return
	CameraFeedback.add_trauma_hurt()
	if not Health.apply_damage(player, damage, global_position):
		return
	_play_hit_sfx()


func _play_hit_sfx() -> void:
	var sfx := AudioStreamPlayer3D.new()
	add_child(sfx)
	sfx.global_position = global_position
	sfx.bus = "SFX"
	sfx.stream = HIT_SOUND
	sfx.finished.connect(sfx.queue_free, CONNECT_ONE_SHOT)
	sfx.play()
