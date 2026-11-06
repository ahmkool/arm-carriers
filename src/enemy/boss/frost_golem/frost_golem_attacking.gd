extends EnemyState
## Runs one Frost Golem move: plays its animation, then lands its effect at the authored moment.
## Timing lives here, not in animation tracks, so moves can be shorter than their clips.

const ANIM_REQUEST := {
	&"sweep": &"parameters/Sweep/request",
	&"slam": &"parameters/Slam/request",
	&"spikes": &"parameters/Smash/request",
	&"roar": &"parameters/Roar/request",
}
## effect: seconds until the move lands. late: seconds until its second beat. duration: total length.
## Slam and spikes land when the axe and the fist hit the ground in their clips (1.36 s and 2.2 s, measured).
const TIMING := {
	&"sweep": {"effect": 0.55, "late": 0.9, "duration": 1.4},
	&"slam": {"effect": 1.35, "duration": 2.2},
	&"spikes": {"effect": 2.15, "duration": 2.8},
	&"roar": {"effect": 0.5, "duration": 1.7},
}

var _move: StringName = &""
var _elapsed := 0.0
var _effect_done := false
var _late_done := false
var _moves: FrostGolemMoves
var _behavior: FrostGolemBehavior


func enter() -> void:
	super.enter()
	_moves = enemy.get_node("FrostGolemMoves") as FrostGolemMoves
	_behavior = enemy.behavior as FrostGolemBehavior
	_move = _behavior.intent.requested_attack
	_elapsed = 0.0
	_effect_done = false
	_late_done = false
	enemy.velocity = Vector3.ZERO
	_set_animation_request(AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_moves.begin_move(_move)


func exit() -> void:
	super.exit()
	_set_animation_request(AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_moves.end_move()


func physics_update(delta: float) -> void:
	enemy.velocity = Vector3.ZERO
	_face_target_until_effect(delta)
	_elapsed += delta
	_try_run_effect()
	_try_run_late_beat()
	if _elapsed < _get_timing(&"duration"):
		return
	_finish_move()


func _set_animation_request(request: AnimationNodeOneShot.OneShotRequest) -> void:
	if enemy.animation_tree == null:
		return
	if not ANIM_REQUEST.has(_move):
		return
	enemy.animation_tree.set(ANIM_REQUEST[_move], request)


func _face_target_until_effect(delta: float) -> void:
	if _effect_done:
		return
	if not is_instance_valid(enemy.target_player):
		return
	var to_target := enemy.target_player.global_position - enemy.global_position
	enemy.smooth_rotate_toward(Vector3(to_target.x, 0.0, to_target.z), delta)


func _try_run_effect() -> void:
	if _effect_done:
		return
	if _elapsed < _get_timing(&"effect"):
		return
	_effect_done = true
	_run_effect()


func _run_effect() -> void:
	match _move:
		&"sweep":
			_moves.set_sweep_active(true)
		&"slam":
			_moves.slam(_behavior.is_enraged())
		&"spikes":
			_moves.cast_spikes(_behavior.get_spike_lines())
		&"roar":
			_moves.roar()


func _try_run_late_beat() -> void:
	if _late_done:
		return
	if not TIMING[_move].has(&"late"):
		return
	if _elapsed < _get_timing(&"late"):
		return
	_late_done = true
	_moves.set_sweep_active(false)


func _get_timing(key: StringName) -> float:
	return TIMING[_move].get(key, 0.0)


func _finish_move() -> void:
	if enemy.get_move_direction().length_squared() > 0.0001:
		enemy_state_machine.transition_to("running")
		return
	enemy_state_machine.transition_to("idle")
