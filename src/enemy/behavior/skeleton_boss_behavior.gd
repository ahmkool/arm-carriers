class_name SkeletonBossBehavior
extends EnemyBehavior

@export var attack_min_distance := 1.2
@export var attack_max_distance := 3.5
@export var chase_max_distance := 14.0
@export var attack_cooldown := 3
@export var enraged_attack_cooldown := 2.5

@export_group("Phase 2 — enraged attack ranges")
@export var enraged_close_attack_threshold := 2.0
@export var enraged_slash_max_distance := 3.5
@export var enraged_stab_max_distance := 2.2
@export var enraged_slam_max_distance := 3.5

const ATTACK_SLASH := &"slash"
const ATTACK_STAB := &"stab"
const ATTACK_SLAM := &"slam"

var _attack_cooldown_remaining := 0.0
var _phase_controller: BossPhaseController
var _pending_phase2_slam := false


func _ready() -> void:
	super._ready()
	_phase_controller = BossPhaseController.from_enemy(enemy)
	_bind_phase_controller()


func _bind_phase_controller() -> void:
	if _phase_controller == null:
		return
	_phase_controller.phase_changed.connect(_on_phase_changed)


func _on_phase_changed(phase_index: int) -> void:
	if phase_index < 2:
		return
	_pending_phase2_slam = true
	_override_queued_attack_with_slam()


func _override_queued_attack_with_slam() -> void:
	if intent.requested_locomotion != &"attacking":
		return
	intent.requested_attack = ATTACK_SLAM
	_pending_phase2_slam = false


func _think(delta: float) -> void:
	if enemy == null or not enemy.is_offensive:
		return

	_ensure_target()

	if _is_attacking():
		return

	_attack_cooldown_remaining = maxf(_attack_cooldown_remaining - delta, 0.0)

	if not _has_valid_target():
		return

	var flat_to_target := _get_flat_to_target()
	var direction := Vector3.FORWARD
	if flat_to_target.length_squared() >= 0.0001:
		direction = flat_to_target.normalized()
	elif not _pending_phase2_slam:
		return

	var distance := flat_to_target.length()

	if _can_request_attack(distance):
		_request_attack(direction, distance)
		return

	if distance > _get_max_attack_distance() and distance <= chase_max_distance:
		intent.move_direction = enemy.get_path_direction_to(enemy.target_player.global_position)
		intent.face_direction = direction
		return

	if distance <= chase_max_distance:
		intent.face_direction = direction


func _would_block_attack_transition() -> bool:
	if enemy.enemy_state_machine == null:
		return false
	var state_machine := enemy.enemy_state_machine
	if state_machine.is_in_state("dead"):
		return true
	if state_machine.is_in_state("casting"):
		return true
	if state_machine.is_in_state("attacking"):
		return true
	if state_machine.is_in_state("spawning"):
		return true
	return false


func _is_attacking() -> bool:
	if enemy.enemy_state_machine == null:
		return false
	return enemy.enemy_state_machine.is_in_state("attacking")


func _ensure_target() -> void:
	if _has_valid_target():
		return
	enemy.update_target_player()


func _has_valid_target() -> bool:
	if not is_instance_valid(enemy.target_player):
		return false
	return not enemy.target_player.is_dead


func _get_flat_to_target() -> Vector3:
	var to_target := enemy.target_player.global_position - enemy.global_position
	return Vector3(to_target.x, 0.0, to_target.z)


func _can_request_attack(distance: float) -> bool:
	if _pending_phase2_slam:
		return not _would_block_attack_transition()
	if _attack_cooldown_remaining > 0.0:
		return false
	if distance < attack_min_distance:
		return false
	if _is_enraged():
		return not _get_enraged_eligible_attacks(distance).is_empty()
	if distance > attack_max_distance:
		return false
	return true


func _request_attack(face_direction: Vector3, distance: float) -> void:
	intent.face_direction = face_direction
	if _pending_phase2_slam:
		intent.requested_attack = ATTACK_SLAM
		_pending_phase2_slam = false
	else:
		intent.requested_attack = _pick_attack(distance)
	intent.requested_locomotion = &"attacking"
	_attack_cooldown_remaining = _get_attack_cooldown()


func _get_attack_cooldown() -> float:
	if _is_enraged():
		return enraged_attack_cooldown
	return attack_cooldown


func _get_max_attack_distance() -> float:
	if not _is_enraged():
		return attack_max_distance
	return maxf(
		enraged_slash_max_distance,
		maxf(enraged_stab_max_distance, enraged_slam_max_distance)
	)


func _pick_attack(distance: float) -> StringName:
	if not _is_enraged():
		return _pick_calm_attack()
	return _pick_enraged_attack(distance)


func _is_enraged() -> bool:
	if _phase_controller == null:
		return false
	return _phase_controller.is_phase_at_least(2)


func _pick_calm_attack() -> StringName:
	if randi() % 2 == 0:
		return ATTACK_SLASH
	return ATTACK_STAB


func _pick_enraged_attack(distance: float) -> StringName:
	var eligible := _get_enraged_eligible_attacks(distance)
	if eligible.is_empty():
		return ATTACK_SLASH
	return eligible[randi() % eligible.size()]


func _get_enraged_eligible_attacks(distance: float) -> Array[StringName]:
	var eligible: Array[StringName] = []
	if distance <= enraged_close_attack_threshold:
		_append_attack_if_in_range(eligible, ATTACK_SLASH, distance, enraged_slash_max_distance)
		_append_attack_if_in_range(eligible, ATTACK_STAB, distance, enraged_stab_max_distance)
		_append_attack_if_in_range(eligible, ATTACK_SLAM, distance, enraged_slam_max_distance)
		return eligible
	_append_attack_if_in_range(eligible, ATTACK_SLASH, distance, enraged_slash_max_distance)
	_append_attack_if_in_range(eligible, ATTACK_SLAM, distance, enraged_slam_max_distance)
	return eligible


func _append_attack_if_in_range(
	eligible: Array[StringName],
	attack: StringName,
	distance: float,
	max_distance: float
) -> void:
	if not _is_distance_in_attack_range(distance, max_distance):
		return
	eligible.append(attack)


func _is_distance_in_attack_range(distance: float, max_distance: float) -> bool:
	if distance < attack_min_distance:
		return false
	if distance > max_distance:
		return false
	return true
