class_name ClankerBehavior
extends EnemyBehavior
## Stomps after the carriers. Up close it punches; nearby it smashes the floor, and the shockwave sets off the magma
## pockets it passes; from afar its exhausts lob slag at the carriers. Below half health it overheats: it roars,
## which sets off every pocket around it, and from then on it lobs more slag with shorter gaps between moves.

const MOVE_PUNCH := &"punch"
const MOVE_SMASH := &"smash"
const MOVE_MORTAR := &"mortar"
const MOVE_ROAR := &"roar"

@export_group("Distances")
@export var punch_distance := 3.8
@export var smash_distance := 7.5
@export var mortar_min_distance := 6.5
@export var mortar_max_distance := 30.0

@export_group("Cooldowns")
@export var gap_between_moves := 1.5
@export var overheated_gap_between_moves := 0.9
@export var punch_cooldown := 2.2
@export var smash_cooldown := 8.0
@export var overheated_smash_cooldown := 6.0
@export var mortar_cooldown := 4.5
@export var overheated_mortar_cooldown := 3.2

var _gap_remaining := 1.5
var _punch_remaining := 0.0
var _smash_remaining := 3.0
var _mortar_remaining := 1.5
var _roar_pending := false
var _phase_controller: BossPhaseController


func _ready() -> void:
	super._ready()
	_phase_controller = BossPhaseController.from_enemy(enemy)
	if _phase_controller == null:
		return
	_phase_controller.phase_changed.connect(_on_phase_changed)


func is_overheated() -> bool:
	if _phase_controller == null:
		return false
	return _phase_controller.is_phase_at_least(2)


func _on_phase_changed(phase_index: int) -> void:
	if phase_index < 2:
		return
	_roar_pending = true


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
	if distance > punch_distance * 0.8:
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
	_punch_remaining = maxf(_punch_remaining - delta, 0.0)
	_smash_remaining = maxf(_smash_remaining - delta, 0.0)
	_mortar_remaining = maxf(_mortar_remaining - delta, 0.0)


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
	if distance <= punch_distance and _punch_remaining <= 0.0:
		return MOVE_PUNCH
	if distance <= smash_distance and _smash_remaining <= 0.0:
		return MOVE_SMASH
	if distance >= mortar_min_distance and distance <= mortar_max_distance and _mortar_remaining <= 0.0:
		return MOVE_MORTAR
	return &""


func _start_move(move: StringName) -> void:
	intent.requested_attack = move
	intent.requested_locomotion = &"attacking"
	_gap_remaining = overheated_gap_between_moves if is_overheated() else gap_between_moves
	_apply_move_cooldown(move)


func _apply_move_cooldown(move: StringName) -> void:
	match move:
		MOVE_ROAR:
			_roar_pending = false
		MOVE_PUNCH:
			_punch_remaining = punch_cooldown
		MOVE_SMASH:
			_smash_remaining = overheated_smash_cooldown if is_overheated() else smash_cooldown
		MOVE_MORTAR:
			_mortar_remaining = overheated_mortar_cooldown if is_overheated() else mortar_cooldown
