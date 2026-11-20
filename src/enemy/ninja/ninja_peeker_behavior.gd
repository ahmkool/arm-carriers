class_name NinjaPeekerBehavior
extends EnemyBehavior
## A ninja that holds cover: it waits behind a `ShotCover` billboard, darts out past one end of it
## (`ninja_darting.gd`), throws a shuriken at the nearer carrier (`ninja_throwing.gd`) and darts back.
## Where it hides is where it stands when it wakes; `peek_offsets` are where it steps out to, one picked at
## random each time.
##
## The launcher's star can't hurt it (`Shuriken.STAR_PROOF_GROUP`), so the carriers have to bring the star
## alongside the cover and scatter the kunai in behind it, or catch it with a kunai while it is out.

## World offsets from the hiding spot to the spots it steps out to.
@export var peek_offsets: Array[Vector3] = [Vector3(0.0, 0.0, 2.2), Vector3(0.0, 0.0, -2.2)]
@export var first_peek_delay := 1.5
@export var hide_min := 2.0
@export var hide_max := 3.5

## Close enough to a spot to count as there.
const ARRIVE_DISTANCE := 0.1

enum Phase { HIDDEN, GOING_OUT, THROWING, GOING_BACK }

var _phase := Phase.HIDDEN
var _hide_timer := 0.0
var _hide_spot := Vector3.ZERO
var _dart_target := Vector3.ZERO
var _throw_started := false
var _was_offensive := false


func _ready() -> void:
	super()
	enemy.add_to_group(Shuriken.STAR_PROOF_GROUP)


## Where the Darting state runs to.
func get_dart_target() -> Vector3:
	return _dart_target


func is_hidden() -> bool:
	return _phase == Phase.HIDDEN


func _think(delta: float) -> void:
	if enemy == null or _is_busy():
		return
	if not enemy.is_offensive:
		_was_offensive = false
		return
	_on_wake_up()
	enemy.update_target_player()
	match _phase:
		Phase.HIDDEN:
			_wait_hidden(delta)
		Phase.GOING_OUT:
			_arrive_then(Phase.THROWING)
		Phase.THROWING:
			_throw()
		Phase.GOING_BACK:
			_arrive_then(Phase.HIDDEN)


func _is_busy() -> bool:
	var machine := enemy.enemy_state_machine
	if machine == null:
		return true
	if machine.is_in_state("dead"):
		return true
	return machine.is_in_state("darting")


func _on_wake_up() -> void:
	if _was_offensive:
		return
	_was_offensive = true
	_hide_spot = enemy.global_position
	_phase = Phase.HIDDEN
	_hide_timer = first_peek_delay


func _wait_hidden(delta: float) -> void:
	_face_target()
	_hide_timer -= delta
	if _hide_timer > 0.0:
		return
	_dart_to(_hide_spot + peek_offsets.pick_random(), Phase.GOING_OUT)


## Once the dart has ended at its target, moves on to `next`; darts again if something pushed it off.
func _arrive_then(next: Phase) -> void:
	if not _is_at(_dart_target):
		_dart_to(_dart_target, _phase)
		return
	_phase = next
	_throw_started = false
	_hide_timer = randf_range(hide_min, hide_max)


func _throw() -> void:
	if enemy.enemy_state_machine.is_in_state("throwing"):
		_throw_started = true
		return
	if not _throw_started:
		_face_target()
		intent.requested_locomotion = &"throwing"
		return
	_dart_to(_hide_spot, Phase.GOING_BACK)


func _dart_to(target: Vector3, phase: Phase) -> void:
	_dart_target = Vector3(target.x, enemy.global_position.y, target.z)
	_phase = phase
	intent.requested_locomotion = &"darting"


func _is_at(point: Vector3) -> bool:
	var offset := point - enemy.global_position
	return Vector2(offset.x, offset.z).length() <= ARRIVE_DISTANCE


func _face_target() -> void:
	if not is_instance_valid(enemy.target_player):
		return
	var to_target := enemy.target_player.global_position - enemy.global_position
	intent.face_direction = Vector3(to_target.x, 0.0, to_target.z)
