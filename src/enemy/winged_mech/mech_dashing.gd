extends MechState
## Dash: rears back and glows (the tell), locks the target's spot, rockets through it and a little past,
## then brakes and hands back to hovering, which climbs back to altitude.

enum Phase { WINDUP, DASH, RECOVER }

## Only on during the DASH phase. Its body_entered goes to EnemyLocal._on_hit_box_body_entered.
@export var hit_box: Area3D
## Lit during the windup and the dash, so the dash can be seen coming.
@export var tell_light: OmniLight3D
@export var trail: GPUParticles3D
@export var tell_light_energy := 6.0
## How fast the mech backs off and rises during the windup.
@export var windup_back_speed := 2.0
@export var windup_rise := 0.8
@export var dash_pitch_degrees := -70.0
@export var windup_pitch_degrees := 20.0

var _phase := Phase.WINDUP
var _phase_time := 0.0
var _direction := Vector3.ZERO
var _lock_y := 0.0
var _travel_left := 0.0


func enter() -> void:
	super.enter()
	_phase = Phase.WINDUP
	_phase_time = 0.0
	_set_tell(true)


func exit() -> void:
	_set_hit_box(false)
	_set_tell(false)


func physics_update(delta: float) -> void:
	var behavior := mech_behavior()
	if behavior == null:
		return
	_phase_time += delta
	if _phase == Phase.WINDUP:
		_windup(behavior, delta)
		return
	if _phase == Phase.DASH:
		_dash(behavior, delta)
		return
	_recover(behavior, delta)


func _windup(behavior: WingedMechBehavior, delta: float) -> void:
	face_target(delta)
	turn_model_to_rest(delta)
	lean_visual(windup_pitch_degrees, 0.0, delta)
	var back := -_flat_forward() * windup_back_speed
	enemy.velocity = Vector3(back.x, altitude_velocity(behavior.desired_altitude + windup_rise), back.z)
	_ramp_tell(_phase_time / behavior.dash_windup_seconds)
	if _phase_time < behavior.dash_windup_seconds:
		return
	_start_dash(behavior)


func _start_dash(behavior: WingedMechBehavior) -> void:
	if not is_instance_valid(enemy.target_player):
		enemy_state_machine.transition_to("hovering")
		return
	var lock := enemy.target_player.global_position + Vector3.UP * behavior.dash_floor_clearance
	var to_lock := lock - enemy.global_position
	_lock_y = lock.y
	_direction = to_lock.normalized()
	_travel_left = to_lock.length() + behavior.dash_overshoot
	_phase = Phase.DASH
	_phase_time = 0.0
	_set_hit_box(true)
	_ramp_tell(1.0)


func _dash(behavior: WingedMechBehavior, delta: float) -> void:
	_level_out_at_lock_height()
	enemy.velocity = _direction * behavior.dash_speed
	face_flat(_direction, delta * 3.0)
	turn_model_to_rest(delta * 2.0)
	lean_visual(dash_pitch_degrees, 0.0, delta * 2.0)
	_travel_left -= behavior.dash_speed * delta
	if not _dash_finished(behavior):
		return
	_phase = Phase.RECOVER
	_phase_time = 0.0
	_set_hit_box(false)
	_set_tell(false)


## Once down at the target's height the dash flies flat instead of diving into the floor.
func _level_out_at_lock_height() -> void:
	if _direction.y >= 0.0:
		return
	if enemy.global_position.y > _lock_y:
		return
	var flat := Vector3(_direction.x, 0.0, _direction.z)
	if flat.length_squared() < 0.0001:
		flat = _flat_forward()
	_direction = flat.normalized()


func _dash_finished(behavior: WingedMechBehavior) -> bool:
	if _travel_left <= 0.0:
		return true
	if _phase_time >= behavior.dash_max_seconds:
		return true
	return enemy.is_on_wall()


func _recover(behavior: WingedMechBehavior, delta: float) -> void:
	var t := clampf(_phase_time / behavior.dash_recover_seconds, 0.0, 1.0)
	var carry := _direction * behavior.dash_speed * (1.0 - t) * (1.0 - t)
	enemy.velocity = Vector3(carry.x, altitude_velocity(behavior.desired_altitude) * t, carry.z)
	lean_visual(0.0, 0.0, delta)
	if t < 1.0:
		return
	enemy_state_machine.transition_to("hovering")


func _flat_forward() -> Vector3:
	var forward := -enemy.global_basis.z
	return Vector3(forward.x, 0.0, forward.z).normalized()


func _set_hit_box(on: bool) -> void:
	if hit_box == null:
		return
	hit_box.set_deferred("monitoring", on)


func _set_tell(on: bool) -> void:
	if trail != null:
		trail.emitting = on
	if tell_light == null:
		return
	tell_light.visible = on
	tell_light.light_energy = 0.0


func _ramp_tell(amount: float) -> void:
	if tell_light == null:
		return
	tell_light.light_energy = tell_light_energy * clampf(amount, 0.0, 1.0)
