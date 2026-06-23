extends Node3D

@export var damage: int = 1

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
	Health.apply_damage(player, damage, global_position)
