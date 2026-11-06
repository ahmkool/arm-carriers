class_name KatanaRobotBehavior
extends EnemyBehavior
## 4GTN, a robot samurai. Walks the carriers down and cuts at them with its katana, and
## lunges across the deck when they keep their distance. Below half health the blade
## charges up: lunges come in pairs, and a slam sends plasma waves out in a fan, which
## the pulse rifle can shoot down. Below 15% it goes into a rage: it blinks to a spot
## away from the carriers and lunges, over and over, with no pause between moves.

const MOVE_TAUNT := &"taunt"
const MOVE_SLASH := &"slash"
const MOVE_DASH := &"dash"
const MOVE_WAVES := &"waves"
const MOVE_TELEPORT := &"teleport"
const RAGE_PHASE := 3

@export_group("Distances")
@export var slash_distance := 5.0
## Stops walking a little inside slash range, so it doesn't stand on the carriers.
@export var stop_distance := 3.5
@export var dash_min_distance := 7.0
## The camera sees about 12 m ahead and less behind: a lunge from further away could start off screen.
@export var dash_max_distance := 10.0
## A lunge overshoots its target, so the follow-up usually starts close behind the carriers
## and turns back across them. Closer than this, the follow-up is a slash instead.
@export var follow_up_dash_min_distance := 2.0
@export var waves_max_distance := 13.0

@export_group("Cooldowns")
@export var gap_between_moves := 0.9
@export var enraged_gap_between_moves := 0.5
@export var slash_cooldown := 1.6
@export var enraged_slash_cooldown := 1.1
@export var dash_cooldown := 5.0
@export var enraged_dash_cooldown := 3.5
@export var waves_cooldown := 6.0
## In the rage phase a lunge follows a blink straight away, and the next blink the lunge.
@export var rage_gap_between_moves := 0.0

@export_group("Movement")
@export var enraged_speed := 3.4

var _gap_remaining := 0.0
var _slash_remaining := 0.0
var _dash_remaining := 2.0
var _waves_remaining := 0.0
var _taunt_pending := true
var _follow_up_dash_pending := false
## True while the current move is the second lunge of a pair, which winds up faster.
var is_follow_up_dash := false
var _phase_controller: BossPhaseController
var _moves: KatanaRobotMoves
## In the rage phase blinks and lunges alternate: true when the next move is a blink.
var _rage_teleport_next := true


func _ready() -> void:
	super._ready()
	_moves = enemy.get_node("KatanaRobotMoves") as KatanaRobotMoves
	_phase_controller = BossPhaseController.from_enemy(enemy)
	if _phase_controller == null:
		return
	_phase_controller.phase_changed.connect(_on_phase_changed)


func is_enraged() -> bool:
	if _phase_controller == null:
		return false
	return _phase_controller.is_phase_at_least(2)


func is_raging() -> bool:
	if _phase_controller == null:
		return false
	return _phase_controller.is_phase_at_least(RAGE_PHASE)


func _on_phase_changed(phase_index: int) -> void:
	if phase_index < 2:
		return
	_taunt_pending = true
	_waves_remaining = 0.0
	enemy.speed = enraged_speed
	_follow_up_dash_pending = false
	_rage_teleport_next = true


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

	is_follow_up_dash = false
	var move := _pick_move(distance)
	if not move.is_empty():
		_start_move(move)
		return
	if distance <= stop_distance:
		return
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
	_slash_remaining = maxf(_slash_remaining - delta, 0.0)
	_dash_remaining = maxf(_dash_remaining - delta, 0.0)
	_waves_remaining = maxf(_waves_remaining - delta, 0.0)


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
	if _taunt_pending:
		return MOVE_TAUNT
	if is_raging():
		return _pick_rage_move(distance)
	if _follow_up_dash_pending:
		return _pick_follow_up(distance)
	if _gap_remaining > 0.0:
		return &""
	if _slash_remaining <= 0.0 and distance <= slash_distance:
		return MOVE_SLASH
	if _can_dash(distance):
		return MOVE_DASH
	if _can_cast_waves(distance):
		return MOVE_WAVES
	return &""


## The second beat of an enraged lunge: another lunge aimed at wherever the carriers
## dodged to, or a slash when they're too close for one. It ignores the cooldowns.
func _pick_follow_up(distance: float) -> StringName:
	_follow_up_dash_pending = false
	if distance < follow_up_dash_min_distance:
		return MOVE_SLASH
	is_follow_up_dash = true
	return MOVE_DASH


## Rage: blink to a spot away from the carriers, then lunge at them from there. When no
## spot is safe it lunges from where it stands, or slashes if they are on top of it.
func _pick_rage_move(distance: float) -> StringName:
	if _gap_remaining > 0.0:
		return &""
	if _rage_teleport_next and _moves.plan_teleport(enemy.target_player):
		return MOVE_TELEPORT
	if distance < follow_up_dash_min_distance:
		return MOVE_SLASH
	return MOVE_DASH


func _can_dash(distance: float) -> bool:
	if _dash_remaining > 0.0:
		return false
	return distance >= dash_min_distance and distance <= dash_max_distance


func _can_cast_waves(distance: float) -> bool:
	if not is_enraged():
		return false
	if _waves_remaining > 0.0:
		return false
	return distance <= waves_max_distance


func _start_move(move: StringName) -> void:
	intent.requested_attack = move
	intent.requested_locomotion = &"attacking"
	_gap_remaining = _get_gap_between_moves()
	_rage_teleport_next = move != MOVE_TELEPORT
	_apply_move_cooldown(move)


func _get_gap_between_moves() -> float:
	if is_raging():
		return rage_gap_between_moves
	return enraged_gap_between_moves if is_enraged() else gap_between_moves


func _apply_move_cooldown(move: StringName) -> void:
	match move:
		MOVE_TAUNT:
			_taunt_pending = false
		MOVE_SLASH:
			_slash_remaining = enraged_slash_cooldown if is_enraged() else slash_cooldown
		MOVE_DASH:
			_start_dash_cooldown()
		MOVE_WAVES:
			_waves_remaining = waves_cooldown


## Enraged lunges come in pairs: the first one queues the second, which doesn't queue a third.
func _start_dash_cooldown() -> void:
	var was_first_of_pair := _dash_remaining <= 0.0
	_dash_remaining = enraged_dash_cooldown if is_enraged() else dash_cooldown
	if is_raging():
		return
	if not is_enraged() or not was_first_of_pair:
		return
	_follow_up_dash_pending = true
