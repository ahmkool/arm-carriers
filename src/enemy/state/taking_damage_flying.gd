extends EnemyState

@export var hit_duration_seconds := 0.35

var _time_remaining := 0.0


func enter() -> void:
	super.enter()
	_begin_hit_reaction()


func refresh_hit() -> void:
	_begin_hit_reaction()


func _begin_hit_reaction() -> void:
	_time_remaining = hit_duration_seconds
	enemy.velocity = Vector3.ZERO
	enemy.play_hit_animation()


func physics_update(delta: float) -> void:
	enemy.velocity = Vector3.ZERO
	_time_remaining -= delta
	if _time_remaining > 0.0:
		return
	enemy.resume_state_after_hit()
