extends EnemyState

const ANIM_PARAM_SLASH_REQUEST := &"parameters/Slash/request"
const ANIM_PARAM_SLASH_ACTIVE := &"parameters/Slash/internal_active"
const ANIM_PARAM_STAB_REQUEST := &"parameters/Stab/request"
const ANIM_PARAM_STAB_ACTIVE := &"parameters/Stab/internal_active"

const ATTACK_SLASH := &"slash"
const ATTACK_STAB := &"stab"

var _active_attack: StringName = &""


func enter() -> void:
	super.enter()
	_active_attack = _resolve_attack_kind()
	enemy.velocity = Vector3.ZERO
	if enemy.footsteps_particles:
		enemy.footsteps_particles.emitting = false
	_play_attack_animation()


func physics_update(delta: float) -> void:
	if not enemy.is_on_floor():
		enemy_state_machine.transition_to("falling")
		return

	enemy.velocity = Vector3.ZERO
	_rotate_toward_target(delta)

	if _is_attack_animation_playing():
		return

	_finish_attack()


func _resolve_attack_kind() -> StringName:
	if enemy.behavior == null:
		return ATTACK_SLASH
	var requested := enemy.behavior.intent.requested_attack
	if requested.is_empty():
		return ATTACK_SLASH
	return requested


func _play_attack_animation() -> void:
	if enemy.animation_tree == null:
		return
	if not enemy.animation_tree.active:
		return
	if _active_attack == ATTACK_STAB:
		enemy.animation_tree.set(ANIM_PARAM_STAB_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		return
	enemy.animation_tree.set(ANIM_PARAM_SLASH_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _is_attack_animation_playing() -> bool:
	if enemy.animation_tree == null:
		return false
	if not enemy.animation_tree.active:
		return false
	if _active_attack == ATTACK_STAB:
		return enemy.animation_tree.get(ANIM_PARAM_STAB_ACTIVE)
	return enemy.animation_tree.get(ANIM_PARAM_SLASH_ACTIVE)


func _rotate_toward_target(delta: float) -> void:
	if not is_instance_valid(enemy.target_player):
		return
	var to_target := enemy.target_player.global_position - enemy.global_position
	var face := Vector3(to_target.x, 0.0, to_target.z)
	enemy.smooth_rotate_toward(face, delta)


func _finish_attack() -> void:
	if enemy.get_move_direction().length_squared() > 0.0001:
		enemy_state_machine.transition_to("running")
		return
	enemy_state_machine.transition_to("idle")
