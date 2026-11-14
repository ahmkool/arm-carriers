extends EnemyState
## The ninja stops, turns to its target and throws a shuriken with KayKit's Throw clip. The one in
## its hand disappears when it lets go, and comes back as it walks off.

## When, into the throw, the shuriken leaves the hand.
@export var release_sec := 0.45
## When the ninja may run again.
@export var throw_sec := 1.0
@export var shuriken_speed := 11.0
## Damage to a carrier. They have 3 health.
@export var damage := 1
## The hand that throws; it holds the shuriken model, which hides while one is in the air.
@export var hand: Node3D
@export var hand_shuriken: Node3D

const SHURIKEN_SCENE := preload("res://src/enemy/ninja/ninja_shuriken.tscn")
const THROW_SOUND := preload("res://assets/sounds/slash_4.wav")
## Point on the target to aim at, above its feet.
const AIM_HEIGHT := 0.9

var _time := 0.0
var _released := false


func enter() -> void:
	super.enter()
	_time = 0.0
	_released = false
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0
	if enemy.footsteps_particles:
		enemy.footsteps_particles.emitting = false
	enemy.play_cast_animation()


func exit() -> void:
	_set_hand_shuriken_visible(true)


func physics_update(delta: float) -> void:
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0
	_face_target(delta)
	_time += delta
	if _time >= release_sec and not _released:
		_released = true
		_throw()
	if _time < throw_sec:
		return
	enemy_state_machine.transition_to("idle")


func _face_target(delta: float) -> void:
	if not is_instance_valid(enemy.target_player):
		return
	var to_target := enemy.target_player.global_position - enemy.global_position
	enemy.smooth_rotate_toward(Vector3(to_target.x, 0.0, to_target.z), delta)


func _throw() -> void:
	if not is_instance_valid(enemy.target_player):
		return
	var origin := hand.global_position if hand != null else enemy.global_position + Vector3.UP * 1.2
	var aim := enemy.target_player.global_position + Vector3.UP * AIM_HEIGHT
	var direction := aim - origin
	if direction.length_squared() < 0.0001:
		return
	var shuriken := SHURIKEN_SCENE.instantiate() as Fireball
	shuriken.damage = damage
	enemy.get_tree().current_scene.add_child(shuriken)
	shuriken.global_position = origin
	shuriken.launch(direction.normalized() * shuriken_speed)
	_set_hand_shuriken_visible(false)
	ImpactFeedback.play_sfx(THROW_SOUND, origin, randf_range(1.4, 1.7), -6.0)


func _set_hand_shuriken_visible(shown: bool) -> void:
	if hand_shuriken == null:
		return
	hand_shuriken.visible = shown
