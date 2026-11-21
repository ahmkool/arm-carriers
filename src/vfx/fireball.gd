class_name Fireball
extends Node3D

const DISAPPEAR_LEAD_SECONDS := 0.5
const HIT_SOUND := preload("res://assets/sounds/explosion/Small Explosion 2_1.wav")
const REFLECTED_SPEED_MULTIPLIER := 1.35
const REFLECTED_ENEMY_DAMAGE := 3
const REFLECT_COOLDOWN_SECONDS := 0.08
const REFLECT_CLEARANCE := 0.25
const REFLECTED_LIGHT_COLOR := Color(0.45, 0.95, 1.0)
## Layer 2 ("enemy"): reflected projectiles strike enemies instead of players.
const ENEMY_COLLISION_MASK := 2

@export var lifetime_seconds := 5.0
## Lethal by default: a mage fireball kills a carrier outright.
@export var damage := 9999

@onready var _animation_player: AnimationPlayer = $AnimationPlayer

var velocity := Vector3.ZERO
var _time_alive := 0.0
var _spent := false
var _disappear_started := false
var _reflected := false
var _reflect_cooldown := 0.0

func _ready() -> void:
	add_to_group(Checkpoint.ENEMY_PROJECTILE_GROUP)

func launch(initial_velocity: Vector3) -> void:
	velocity = initial_velocity
	if velocity.length_squared() > 0.0001:
		look_at(global_position + velocity, Vector3.UP)


func is_reflected() -> bool:
	return _reflected


## Consumes this projectile into a mirror so the mirror can re-emit its energy as a laser.
func absorb() -> bool:
	if _spent or _reflected:
		return false
	_spent = true
	set_physics_process(false)
	queue_free()
	return true


## Bounces this projectile off a mirror surface and turns it against enemies.
func reflect(surface_normal: Vector3, hit_point: Vector3 = Vector3.ZERO) -> bool:
	if _spent or _reflect_cooldown > 0.0:
		return false
	if velocity.length_squared() < 0.0001 or surface_normal.length_squared() < 0.0001:
		return false
	var normal := surface_normal.normalized()
	var incoming_dir := velocity.normalized()
	if incoming_dir.dot(normal) > 0.0:
		normal = -normal
	var reflected_dir := incoming_dir.bounce(normal).normalized()
	var speed := velocity.length() * (1.0 if _reflected else REFLECTED_SPEED_MULTIPLIER)
	_reflected = true
	_reflect_cooldown = REFLECT_COOLDOWN_SECONDS
	_time_alive = 0.0
	_disappear_started = false
	if hit_point != Vector3.ZERO:
		global_position = hit_point + normal * REFLECT_CLEARANCE
	launch(reflected_dir * speed)
	_switch_to_enemy_hits()
	_tint_reflected_visuals()
	return true


func _physics_process(delta: float) -> void:
	_reflect_cooldown = maxf(0.0, _reflect_cooldown - delta)
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
	if _reflected:
		_handle_reflected_collision(body)
		return
	var player := body as PlayerLocal
	if player == null or player.is_dead:
		return
	_spent = true
	set_physics_process(false)
	var damage_landed := Health.apply_damage(player, damage, global_position)
	if damage_landed:
		CameraFeedback.add_trauma_hurt()
		_play_hit_sfx()
	queue_free()


func _handle_reflected_collision(body: Node3D) -> void:
	var enemy := body as EnemyLocal
	if enemy == null or not enemy.is_alive():
		return
	_spent = true
	set_physics_process(false)
	var source := global_position - velocity.normalized()
	var damage_landed := Health.apply_damage(enemy, REFLECTED_ENEMY_DAMAGE, source)
	if damage_landed:
		ImpactFeedback.play_sword_hit()
		_play_hit_sfx()
	queue_free()


func _switch_to_enemy_hits() -> void:
	var area := get_node_or_null("Area3D") as Area3D
	if area == null:
		return
	area.collision_mask = ENEMY_COLLISION_MASK


func _tint_reflected_visuals() -> void:
	var light := get_node_or_null("OmniLight3D") as OmniLight3D
	if light != null:
		light.light_color = REFLECTED_LIGHT_COLOR
		light.light_energy = maxf(light.light_energy, 1.8)
	var visuals := get_node_or_null("Visuals") as Node3D
	if visuals != null:
		visuals.scale = Vector3.ONE


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
