extends EnemyState

@export var hit_duration_seconds := 0.35
@export var knockback_speed := 7.0
@export var knockback_duration_seconds := 0.12

var _time_remaining := 0.0


func enter() -> void:
	super.enter()
	_begin_hit_reaction()


func refresh_hit() -> void:
	_begin_hit_reaction()


func _begin_hit_reaction() -> void:
	_time_remaining = hit_duration_seconds
	enemy.velocity = Vector3.ZERO
	enemy.begin_knockback(knockback_speed, knockback_duration_seconds)
	enemy.play_hit_animation()


func physics_update(delta: float) -> void:
	enemy.velocity.y = 0.0
	enemy.apply_knockback(delta, false)
	_time_remaining -= delta
	if _time_remaining > 0.0:
		return
	enemy.resume_state_after_hit()
