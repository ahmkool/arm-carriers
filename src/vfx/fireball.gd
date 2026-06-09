class_name Fireball
extends Node3D

@export var lifetime_seconds := 5.0

var velocity := Vector3.ZERO
var _time_alive := 0.0
var _spent := false

func launch(initial_velocity: Vector3) -> void:
	velocity = initial_velocity
	if velocity.length_squared() > 0.0001:
		look_at(global_position + velocity, Vector3.UP)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	_time_alive += delta
	if _time_alive >= lifetime_seconds:
		queue_free()
		
func _on_body_collision(body: Node3D) -> void:
	if _spent:
		return
	var player := body as PlayerLocal
	if player == null or player.is_dead:
		return
	_spent = true
	set_physics_process(false)
	CameraFeedback.add_trauma_hurt()
	Health.apply_damage(player, 9999)
	queue_free()
