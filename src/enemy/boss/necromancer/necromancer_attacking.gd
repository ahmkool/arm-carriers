extends EnemyState
## Runs one necromancer move: plays its animation, then fires its effect at the authored moment.
## Timing lives here, not in animation tracks, because these clips are longer than the moves.

const ANIM_REQUEST := {
	&"volley": &"parameters/Shoot/request",
	&"summon": &"parameters/Summon/request",
	&"graves": &"parameters/Raise/request",
	&"swing": &"parameters/Swing/request",
	&"taunt": &"parameters/Taunt/request",
}
## effect: seconds until the move lands. late: seconds until its second beat. duration: total length.
const TIMING := {
	&"volley": {"effect": 0.55, "duration": 1.1},
	&"summon": {"effect": 0.9, "duration": 1.7},
	&"graves": {"effect": 0.5, "duration": 1.2},
	&"swing": {"effect": 0.5, "late": 0.8, "duration": 1.1},
	&"blink": {"effect": 0.15, "late": 0.6, "duration": 0.8},
	&"taunt": {"effect": 0.4, "duration": 1.1},
}

var _move: StringName = &""
var _elapsed := 0.0
var _effect_done := false
var _late_done := false
var _spells: NecromancerSpells
var _behavior: NecromancerBehavior


func enter() -> void:
	super.enter()
	_spells = enemy.get_node("NecromancerSpells") as NecromancerSpells
	_behavior = enemy.behavior as NecromancerBehavior
	_move = _behavior.intent.requested_attack
	_elapsed = 0.0
	_effect_done = false
	_late_done = false
	enemy.velocity = Vector3.ZERO
	_begin_move()


func exit() -> void:
	super.exit()
	_set_animation_request(AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_spells.end_move()


func physics_update(delta: float) -> void:
	enemy.velocity = Vector3.ZERO
	_face_target_until_effect(delta)
	_elapsed += delta
	_try_run_effect()
	_try_run_late_beat()
	if _elapsed < _get_timing(&"duration"):
		return
	_finish_move()


func _begin_move() -> void:
	_set_animation_request(AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_spells.begin_move(_move)


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
		&"volley":
			_spells.fire_volley(_behavior.get_volley_bolts())
		&"summon":
			_spells.summon_minions(_behavior.get_minions_to_summon())
		&"graves":
			_spells.erupt_graves()
		&"swing":
			_spells.set_swing_active(true)
		&"blink":
			_spells.blink_out()
		&"taunt":
			_spells.taunt_burst()


func _try_run_late_beat() -> void:
	if _late_done:
		return
	if not TIMING[_move].has(&"late"):
		return
	if _elapsed < _get_timing(&"late"):
		return
	_late_done = true
	_run_late_beat()


func _run_late_beat() -> void:
	if _move == &"swing":
		_spells.set_swing_active(false)
		return
	_spells.blink_in()


func _get_timing(key: StringName) -> float:
	return TIMING[_move].get(key, 0.0)


func _finish_move() -> void:
	if enemy.get_move_direction().length_squared() > 0.0001:
		enemy_state_machine.transition_to("running")
		return
	enemy_state_machine.transition_to("idle")
