class_name Fireball
extends Node3D

const DISAPPEAR_LEAD_SECONDS := 0.5

@export var lifetime_seconds := 5.0

@onready var _animation_player: AnimationPlayer = $AnimationPlayer

var velocity := Vector3.ZERO
var _time_alive := 0.0
var _spent := false
var _disappear_started := false

func launch(initial_velocity: Vector3) -> void:
	velocity = initial_velocity
	if velocity.length_squared() > 0.0001:
		look_at(global_position + velocity, Vector3.UP)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	_time_alive += delta
	_try_start_disappear()
	if _time_alive >= lifetime_seconds:
		queue_free()

func _try_start_disappear() -> void:
	if _disappear_started:
		return
	var disappear_at := maxf(0.0, lifetime_seconds - DISAPPEAR_LEAD_SECONDS)
	if _time_alive < disappear_at:
		return
	_disappear_started = true
	_animation_player.play("disappear")
		
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
