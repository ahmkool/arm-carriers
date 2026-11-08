extends EnemyState
## Runs one Clanker move: plays its animation, then lands its effect at the authored moment.
## Timing lives here, not in animation tracks, so moves can be shorter than their clips.

const ANIM_REQUEST := {
	&"punch": &"parameters/Punch/request",
	&"smash": &"parameters/Smash/request",
	&"mortar": &"parameters/Mortar/request",
	&"roar": &"parameters/Roar/request",
}
## effect: seconds until the move lands. late: seconds until its second beat. duration: total length.
## The smash lands when the fists hit the ground in Melee_Unarmed_Smash (2.2 s, measured on the Frost Golem).
const TIMING := {
	&"punch": {"effect": 0.45, "late": 0.75, "duration": 1.2},
	&"smash": {"effect": 2.15, "duration": 2.9},
	&"mortar": {"effect": 0.45, "duration": 1.3},
	&"roar": {"effect": 0.6, "duration": 2.4},
}

var _move: StringName = &""
var _elapsed := 0.0
var _effect_done := false
var _late_done := false
var _moves: ClankerMoves
var _behavior: ClankerBehavior


func enter() -> void:
	super.enter()
	_moves = enemy.get_node("ClankerMoves") as ClankerMoves
	_behavior = enemy.behavior as ClankerBehavior
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
		&"punch":
			_moves.set_punch_active(true)
		&"smash":
			_moves.smash(_behavior.is_overheated())
		&"mortar":
			_moves.fire_mortar(_behavior.is_overheated())
		&"roar":
			_moves.overheat()


func _try_run_late_beat() -> void:
	if _late_done:
		return
	if not TIMING[_move].has(&"late"):
		return
	if _elapsed < _get_timing(&"late"):
		return
	_late_done = true
	_moves.set_punch_active(false)


func _get_timing(key: StringName) -> float:
	return TIMING[_move].get(key, 0.0)


func _finish_move() -> void:
	if enemy.get_move_direction().length_squared() > 0.0001:
		enemy_state_machine.transition_to("running")
		return
	enemy_state_machine.transition_to("idle")
