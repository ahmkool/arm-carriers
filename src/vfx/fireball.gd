class_name Fireball
extends Node3D

const DISAPPEAR_LEAD_SECONDS := 0.5
const HIT_SOUND := preload("res://assets/sounds/explosion/Small Explosion 2_1.wav")

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
	var damage_landed := Health.apply_damage(player, 9999, global_position)
	if damage_landed:
		_play_hit_sfx()
	queue_free()


func _play_hit_sfx() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var sfx := AudioStreamPlayer3D.new()
	scene_root.add_child(sfx)
	sfx.global_position = global_position
	sfx.bus = "SFX"
	sfx.stream = HIT_SOUND
	sfx.finished.connect(sfx.queue_free, CONNECT_ONE_SHOT)
	sfx.play()
