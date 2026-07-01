extends PlayerState

@export var hit_duration_seconds := 0.45
@export var knockback_speed := 10.0
@export var knockback_duration_seconds := 0.15

var _time_remaining := 0.0
var _knockback_direction := Vector3.ZERO
var _knockback_time_remaining := 0.0


func enter() -> void:
	# player.play_damage_sound()
	_begin_hit_reaction()


func refresh_hit() -> void:
	_begin_hit_reaction()


func _begin_hit_reaction() -> void:
	_time_remaining = hit_duration_seconds
	_knockback_direction = player.get_hit_knockback_direction()
	_knockback_time_remaining = knockback_duration_seconds
	if _knockback_direction.length_squared() < 0.0001:
		_knockback_time_remaining = 0.0
	player.velocity.y = 0.0
	_apply_knockback_velocity()
	if player.footsteps_particles:
		player.footsteps_particles.emitting = false
	player.spawn_damage_vfx()
	player.play_hit_animation()


func physics_update(delta: float) -> void:
	if not player.is_on_floor():
		player_state_machine.transition_to("falling")
		return
	_update_knockback(delta)
	_time_remaining -= delta
	if _time_remaining > 0.0:
		return
	player.resume_state_after_hit()


func _update_knockback(delta: float) -> void:
	if _knockback_time_remaining <= 0.0:
		player.velocity = Vector3.ZERO
		return
	_knockback_time_remaining = maxf(0.0, _knockback_time_remaining - delta)
	_apply_knockback_velocity()


func _apply_knockback_velocity() -> void:
	if _knockback_direction.length_squared() < 0.0001:
		player.velocity = Vector3.ZERO
		return
	player.velocity.x = _knockback_direction.x * knockback_speed
	player.velocity.z = _knockback_direction.z * knockback_speed
	player.look_at(player.global_position + _knockback_direction, Vector3.UP)
