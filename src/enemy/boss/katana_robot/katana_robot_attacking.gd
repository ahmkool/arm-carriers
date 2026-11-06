extends EnemyState
## Runs one 4GTN move. Every beat is timed in animation seconds, measured from the clips:
## the clock runs at the move's playback speed, so a slowed wind-up keeps the beats on
## the swing. KatanaRobotMoves shows the telegraphs and owns the hitboxes.

const ANIM_REQUEST := {
	&"taunt": &"parameters/Taunt/request",
	&"slash": &"parameters/Slash/request",
	&"dash": &"parameters/Stab/request",
	&"waves": &"parameters/Slam/request",
}
const ANIM_SPEED_PARAM := &"parameters/Speed/scale"

## face: turns toward the target until then. strike / strike_end: the hit window.
## end: when the move hands back to walking. Melee_1H_Slash sweeps at 0.50-0.65,
## Melee_1H_Stab thrusts at 0.60-0.75 and Melee_2H_Slam lands at 1.0.
const TIMING := {
	&"taunt": {"face": 0.3, "strike": 0.35, "strike_end": 0.35, "end": 1.05},
	&"slash": {"face": 0.4, "strike": 0.5, "strike_end": 0.7, "end": 1.45},
	&"dash": {"face": 0.35, "strike": 0.58, "strike_end": 0.8, "end": 1.3},
	&"waves": {"face": 0.6, "strike": 0.98, "strike_end": 1.1, "end": 2.3},
	## No clip: it vanishes on entering, reappears at the strike, and lunges right after.
	&"teleport": {"face": 0.0, "strike": 0.22, "strike_end": 0.22, "end": 0.4},
}
const SLASH_SPEED := 1.0
const ENRAGED_SLASH_SPEED := 1.25
## The lunge's wind-up plays slowly, so the carriers have time to read the lane.
const DASH_WINDUP_SPEED := 0.55
const ENRAGED_DASH_WINDUP_SPEED := 0.7
const ENRAGED_FOLLOW_UP_WINDUP_SPEED := 0.85
## Rage lunges come straight out of a blink: still slow enough to read the lane.
const RAGE_DASH_WINDUP_SPEED := 0.8

var _move: StringName = &""
var _anim_time := 0.0
var _speed := 1.0
var _struck := false
var _strike_ended := false
var _dash_direction := Vector3.FORWARD
var _dash_length := 0.0
var _is_follow_up := false
var _moves: KatanaRobotMoves
var _behavior: KatanaRobotBehavior


func enter() -> void:
	super.enter()
	_moves = enemy.get_node("KatanaRobotMoves") as KatanaRobotMoves
	_behavior = enemy.behavior as KatanaRobotBehavior
	_is_follow_up = _behavior.is_follow_up_dash
	_move = _behavior.intent.requested_attack
	_anim_time = 0.0
	_struck = false
	_strike_ended = false
	enemy.velocity = Vector3.ZERO
	_set_animation_request(AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_moves.begin_move(_move)


func exit() -> void:
	super.exit()
	_set_animation_request(AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_set_speed(1.0)
	_moves.end_move()


func physics_update(delta: float) -> void:
	_set_speed(_get_speed())
	_anim_time += delta * _speed
	_face_target(delta)
	_update_telegraph()
	_try_strike()
	_try_end_strike()
	_move_body()
	if _anim_time < _get_timing("end"):
		return
	_finish_move()


func _get_speed() -> float:
	match _move:
		&"slash":
			return ENRAGED_SLASH_SPEED if _behavior.is_enraged() else SLASH_SPEED
		&"dash":
			return _get_dash_speed()
	return 1.0


func _get_dash_speed() -> float:
	if _anim_time >= _get_timing("strike"):
		return 1.0
	if _behavior.is_raging():
		return RAGE_DASH_WINDUP_SPEED
	if not _behavior.is_enraged():
		return DASH_WINDUP_SPEED
	return ENRAGED_FOLLOW_UP_WINDUP_SPEED if _is_follow_up else ENRAGED_DASH_WINDUP_SPEED


func _set_speed(speed: float) -> void:
	_speed = speed
	if enemy.animation_tree == null:
		return
	enemy.animation_tree.set(ANIM_SPEED_PARAM, speed)


func _set_animation_request(request: AnimationNodeOneShot.OneShotRequest) -> void:
	if enemy.animation_tree == null:
		return
	if not ANIM_REQUEST.has(_move):
		return
	enemy.animation_tree.set(ANIM_REQUEST[_move], request)


func _face_target(delta: float) -> void:
	if _anim_time >= _get_timing("face"):
		return
	if not is_instance_valid(enemy.target_player):
		return
	var to_target := enemy.target_player.global_position - enemy.global_position
	enemy.smooth_rotate_toward(Vector3(to_target.x, 0.0, to_target.z), delta)


## Telegraphs grow brighter toward the strike, and the lunge's lane locks once it stops turning.
func _update_telegraph() -> void:
	if _struck:
		return
	_moves.set_telegraph_progress(clampf(_anim_time / _get_timing("strike"), 0.0, 1.0))
	if _move != &"dash":
		return
	_dash_direction = _get_forward()
	_dash_length = _moves.measure_dash(_dash_direction, _get_target_distance())
	_moves.show_dash_lane(_dash_length)


func _try_strike() -> void:
	if _struck:
		return
	if _anim_time < _get_timing("strike"):
		return
	_struck = true
	_moves.strike(_move)


func _try_end_strike() -> void:
	if not _struck or _strike_ended:
		return
	if _anim_time < _get_timing("strike_end"):
		return
	_strike_ended = true
	enemy.velocity = Vector3.ZERO
	_moves.end_strike(_move)


func _move_body() -> void:
	if _move != &"dash" or not _struck or _strike_ended:
		enemy.velocity = Vector3.ZERO
		return
	var strike_seconds := _get_timing("strike_end") - _get_timing("strike")
	var velocity := _dash_direction * (_dash_length / strike_seconds)
	if not _moves.can_dash_through(enemy.global_position + velocity * get_physics_process_delta_time() * 2.0):
		enemy.velocity = Vector3.ZERO
		return
	enemy.velocity = velocity


func _get_forward() -> Vector3:
	var forward := -enemy.global_basis.z
	forward.y = 0.0
	return forward.normalized()


func _get_target_distance() -> float:
	if not is_instance_valid(enemy.target_player):
		return 0.0
	var to_target := enemy.target_player.global_position - enemy.global_position
	return Vector2(to_target.x, to_target.z).length()


func _get_timing(key: String) -> float:
	return TIMING[_move][key]


func _finish_move() -> void:
	if enemy.get_move_direction().length_squared() > 0.0001:
		enemy_state_machine.transition_to("running")
		return
	enemy_state_machine.transition_to("idle")
