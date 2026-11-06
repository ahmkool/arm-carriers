class_name NecromancerBehavior
extends EnemyBehavior
## Keeps its distance and casts: bolts, summons and, once enraged, eruptions under the players.
## Carriers who stay close get a scythe swing, then the boss blinks away.

const MOVE_VOLLEY := &"volley"
const MOVE_SUMMON := &"summon"
const MOVE_GRAVES := &"graves"
const MOVE_SWING := &"swing"
const MOVE_BLINK := &"blink"
const MOVE_TAUNT := &"taunt"

@export_group("Distances")
@export var approach_distance := 11.0
@export var retreat_distance := 5.0
@export var cast_max_distance := 16.0
@export var swing_distance := 3.8
@export var crowded_distance := 5.0
@export var crowded_seconds_before_blink := 2.5

@export_group("Cooldowns")
@export var gap_between_moves := 1.2
@export var enraged_gap_between_moves := 0.7
@export var volley_cooldown := 3.5
@export var enraged_volley_cooldown := 2.5
@export var summon_cooldown := 14.0
@export var enraged_summon_cooldown := 10.0
@export var graves_cooldown := 7.0
@export var swing_cooldown := 3.0
@export var blink_cooldown := 8.0

@export_group("Numbers")
@export var volley_bolts := 3
@export var enraged_volley_bolts := 5
@export var minions_per_summon := 2
@export var enraged_minions_per_summon := 3
@export var minion_cap := 3
@export var enraged_minion_cap := 5

var _gap_remaining := 0.0
var _volley_remaining := 1.0
var _summon_remaining := 4.0
var _graves_remaining := 2.0
var _swing_remaining := 0.0
var _blink_remaining := 0.0
var _crowded_seconds := 0.0
var _taunt_pending := true
var _phase_controller: BossPhaseController
var _spells: NecromancerSpells


func _ready() -> void:
	super._ready()
	_phase_controller = BossPhaseController.from_enemy(enemy)
	_spells = enemy.get_node_or_null("NecromancerSpells") as NecromancerSpells
	if _phase_controller == null:
		return
	_phase_controller.phase_changed.connect(_on_phase_changed)


func is_enraged() -> bool:
	if _phase_controller == null:
		return false
	return _phase_controller.is_phase_at_least(2)


func get_volley_bolts() -> int:
	return enraged_volley_bolts if is_enraged() else volley_bolts


func get_minions_to_summon() -> int:
	var per_summon := enraged_minions_per_summon if is_enraged() else minions_per_summon
	return mini(per_summon, _get_free_minion_slots())


func _on_phase_changed(phase_index: int) -> void:
	if phase_index < 2:
		return
	_taunt_pending = true
	_summon_remaining = 0.0
	_blink_remaining = 0.0
	_graves_remaining = 0.0


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
	var toward_target := _get_direction(flat_to_target)
	intent.face_direction = toward_target
	_track_crowding(delta, distance)

	var move := _pick_move(distance)
	if not move.is_empty():
		_start_move(move)
		return
	intent.move_direction = _get_walk_direction(distance)


func _is_busy() -> bool:
	if enemy.enemy_state_machine == null:
		return true
	var state_machine := enemy.enemy_state_machine
	if state_machine.is_in_state("dead"):
		return true
	return state_machine.is_in_state("attacking")


func _tick_cooldowns(delta: float) -> void:
	_gap_remaining = maxf(_gap_remaining - delta, 0.0)
	_volley_remaining = maxf(_volley_remaining - delta, 0.0)
	_summon_remaining = maxf(_summon_remaining - delta, 0.0)
	_graves_remaining = maxf(_graves_remaining - delta, 0.0)
	_swing_remaining = maxf(_swing_remaining - delta, 0.0)
	_blink_remaining = maxf(_blink_remaining - delta, 0.0)


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


func _track_crowding(delta: float, distance: float) -> void:
	if distance > crowded_distance:
		_crowded_seconds = 0.0
		return
	_crowded_seconds += delta


func _pick_move(distance: float) -> StringName:
	if _taunt_pending:
		return MOVE_TAUNT
	if _can_blink():
		return MOVE_BLINK
	if _can_swing(distance):
		return MOVE_SWING
	if _gap_remaining > 0.0 or distance > cast_max_distance:
		return &""
	return _pick_spell()


func _pick_spell() -> StringName:
	if _can_summon():
		return MOVE_SUMMON
	if is_enraged() and _graves_remaining <= 0.0:
		return MOVE_GRAVES
	if _volley_remaining <= 0.0:
		return MOVE_VOLLEY
	return &""


func _can_blink() -> bool:
	if _blink_remaining > 0.0:
		return false
	return _crowded_seconds >= crowded_seconds_before_blink


func _can_swing(distance: float) -> bool:
	if _swing_remaining > 0.0:
		return false
	return distance <= swing_distance


func _can_summon() -> bool:
	if _summon_remaining > 0.0:
		return false
	return _get_free_minion_slots() > 0


func _get_free_minion_slots() -> int:
	if _spells == null:
		return 0
	var cap := enraged_minion_cap if is_enraged() else minion_cap
	return maxi(cap - _spells.count_minions(), 0)


func _start_move(move: StringName) -> void:
	intent.requested_attack = move
	intent.requested_locomotion = &"attacking"
	_gap_remaining = enraged_gap_between_moves if is_enraged() else gap_between_moves
	_apply_move_cooldown(move)


func _apply_move_cooldown(move: StringName) -> void:
	match move:
		MOVE_TAUNT:
			_taunt_pending = false
		MOVE_BLINK:
			_blink_remaining = blink_cooldown
			_crowded_seconds = 0.0
		MOVE_SWING:
			_swing_remaining = swing_cooldown
		MOVE_SUMMON:
			_summon_remaining = enraged_summon_cooldown if is_enraged() else summon_cooldown
		MOVE_GRAVES:
			_graves_remaining = graves_cooldown
		MOVE_VOLLEY:
			_volley_remaining = enraged_volley_cooldown if is_enraged() else volley_cooldown


func _get_walk_direction(distance: float) -> Vector3:
	if distance > approach_distance:
		return enemy.get_path_direction_to(enemy.target_player.global_position)
	if distance < retreat_distance:
		return enemy.get_flee_path_direction_from(enemy.target_player.global_position, 4.0)
	return Vector3.ZERO
