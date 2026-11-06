class_name FrostGolemBehavior
extends EnemyBehavior
## Walks the carriers down. Up close it sweeps its axe; nearby it slams the deck, which freezes the floor around it;
## from afar it sends lines of ice spikes. Below half health it roars and enrages: faster, longer ice, three lines.

const MOVE_SWEEP := &"sweep"
const MOVE_SLAM := &"slam"
const MOVE_SPIKES := &"spikes"
const MOVE_ROAR := &"roar"

@export_group("Distances")
@export var sweep_distance := 4.2
@export var slam_distance := 6.5
@export var spikes_min_distance := 6.0
@export var spikes_max_distance := 22.0

@export_group("Cooldowns")
@export var gap_between_moves := 1.4
@export var enraged_gap_between_moves := 0.8
@export var sweep_cooldown := 2.5
@export var slam_cooldown := 7.0
@export var enraged_slam_cooldown := 5.0
@export var spikes_cooldown := 5.0
@export var enraged_spikes_cooldown := 3.5

@export_group("Numbers")
@export var spike_lines := 1
@export var enraged_spike_lines := 3

var _gap_remaining := 1.5
var _sweep_remaining := 0.0
var _slam_remaining := 3.0
var _spikes_remaining := 2.0
var _roar_pending := false
var _phase_controller: BossPhaseController


func _ready() -> void:
	super._ready()
	_phase_controller = BossPhaseController.from_enemy(enemy)
	if _phase_controller == null:
		return
	_phase_controller.phase_changed.connect(_on_phase_changed)


func is_enraged() -> bool:
	if _phase_controller == null:
		return false
	return _phase_controller.is_phase_at_least(2)


func get_spike_lines() -> int:
	return enraged_spike_lines if is_enraged() else spike_lines


func _on_phase_changed(phase_index: int) -> void:
	if phase_index < 2:
		return
	_roar_pending = true
	_slam_remaining = 0.0


func _think(delta: float) -> void:
	if enemy == null or not enemy.is_offensive:
		return
	if _is_busy():
		return
	enemy.update_target_player()
	_tick_cooldowns(delta)
	if not _has_valid_target():
		return

	var flat_to_target := _get_flat_to_target()
	var distance := flat_to_target.length()
	intent.face_direction = _get_direction(flat_to_target)
	var move := _pick_move(distance)
	if not move.is_empty():
		_start_move(move)
		return
	if distance > sweep_distance * 0.8:
		intent.move_direction = enemy.get_path_direction_to(enemy.target_player.global_position)


func _is_busy() -> bool:
	if enemy.enemy_state_machine == null:
		return true
	var state_machine := enemy.enemy_state_machine
	if state_machine.is_in_state("dead"):
		return true
	return state_machine.is_in_state("attacking")


func _tick_cooldowns(delta: float) -> void:
	_gap_remaining = maxf(_gap_remaining - delta, 0.0)
	_sweep_remaining = maxf(_sweep_remaining - delta, 0.0)
	_slam_remaining = maxf(_slam_remaining - delta, 0.0)
	_spikes_remaining = maxf(_spikes_remaining - delta, 0.0)


func _has_valid_target() -> bool:
	if not is_instance_valid(enemy.target_player):
		return false
	return not enemy.target_player.is_dead


func _get_flat_to_target() -> Vector3:
	var to_target := enemy.target_player.global_position - enemy.global_position
	return Vector3(to_target.x, 0.0, to_target.z)


func _get_direction(flat: Vector3) -> Vector3:
	if flat.length_squared() < 0.0001:
		return Vector3.FORWARD
	return flat.normalized()


func _pick_move(distance: float) -> StringName:
	if _roar_pending:
		return MOVE_ROAR
	if _gap_remaining > 0.0:
		return &""
	if distance <= sweep_distance and _sweep_remaining <= 0.0:
		return MOVE_SWEEP
	if distance <= slam_distance and _slam_remaining <= 0.0:
		return MOVE_SLAM
	if distance >= spikes_min_distance and distance <= spikes_max_distance and _spikes_remaining <= 0.0:
		return MOVE_SPIKES
	return &""


func _start_move(move: StringName) -> void:
	intent.requested_attack = move
	intent.requested_locomotion = &"attacking"
	_gap_remaining = enraged_gap_between_moves if is_enraged() else gap_between_moves
	_apply_move_cooldown(move)


func _apply_move_cooldown(move: StringName) -> void:
	match move:
		MOVE_ROAR:
			_roar_pending = false
		MOVE_SWEEP:
			_sweep_remaining = sweep_cooldown
		MOVE_SLAM:
			_slam_remaining = enraged_slam_cooldown if is_enraged() else slam_cooldown
		MOVE_SPIKES:
			_spikes_remaining = enraged_spikes_cooldown if is_enraged() else spikes_cooldown
