extends EnemyState
## The ninja's one dodge: a quick dash sideways, with KayKit's Dodge_Left or Dodge_Right roll,
## while it keeps facing the way it faced. The direction comes from `NinjaBehavior`.

const DODGE_SEC := 0.4
const ANIM_DODGE_LEFT := &"parameters/DodgeLeft/request"
const ANIM_DODGE_RIGHT := &"parameters/DodgeRight/request"
const WHOOSH := preload("res://assets/sounds/slash_2.wav")

var _velocity := Vector3.ZERO
var _time_left := 0.0


func enter() -> void:
	super.enter()
	var behavior := enemy.behavior as NinjaBehavior
	var direction := behavior.take_dodge_direction() if behavior != null else Vector3.ZERO
	if direction.length_squared() < 0.0001:
		# Resumed after a hit, with no dodge left to make.
		enemy_state_machine.transition_to("idle")
		return
	_time_left = DODGE_SEC
	_velocity = direction * (behavior.dodge_distance / DODGE_SEC)
	_play_animation(direction)
	ImpactFeedback.play_sfx(WHOOSH, enemy.global_position, randf_range(1.3, 1.5), -4.0)


func physics_update(delta: float) -> void:
	enemy.velocity.x = _velocity.x
	enemy.velocity.z = _velocity.z
	_time_left -= delta
	if _time_left > 0.0:
		return
	enemy.velocity.x = 0.0
	enemy.velocity.z = 0.0
	enemy_state_machine.transition_to("idle")


## The enemy faces -Z, so its right is forward x up.
func _play_animation(direction: Vector3) -> void:
	if enemy.animation_tree == null:
		return
	var forward := -enemy.global_basis.z
	var right := forward.cross(Vector3.UP)
	var request := ANIM_DODGE_RIGHT if direction.dot(right) > 0.0 else ANIM_DODGE_LEFT
	enemy.animation_tree.set(request, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
