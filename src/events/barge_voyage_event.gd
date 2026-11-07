class_name BargeVoyageEvent
extends LevelEvent
## A fight on a flying barge. Triggering it calls the barge from stop 0 to its dock (stop 1). Once every living
## carrier is aboard it sets off. On each leg one wave drops on board, and at the end of the leg the barge hovers
## until that wave is dead. A last leg with no wave brings it to its final dock.
## So with N waves the barge needs N + 3 stops: parked, dock, one per wave, final dock.
##
## Listed in a checkpoint's events_completed, the checkpoint's restore puts the barge back at its dock, waiting for
## the carriers to board again. List the waves in the same checkpoint's enemy_groups_reset.

@export var barge: RotorBarge
@export var waves: Array[BoardingEnemyGroup]
## Seconds after a leg begins before its wave drops on board.
@export var board_delay_seconds := 2.0
## Woken when the given leg begins, such as mages on decks the barge flies past. Optional.
@export var escort_group: EnemyGroup
@export var escort_leg := -1

## Bumped to abandon a voyage in progress, when a checkpoint restore puts the barge back.
var _voyage := 0
var _running := false


func trigger() -> void:
	if _running:
		return
	_voyage += 1
	_run(_voyage, false)


func _complete_event() -> void:
	_voyage += 1
	_running = false
	barge.snap_to(1)
	_run.call_deferred(_voyage, true)


func is_running() -> bool:
	return _running


func _run(voyage: int, docked: bool) -> void:
	_running = true
	if not docked:
		barge.fly_to(1)
		if not await _until(func() -> bool: return not barge.is_moving(), voyage):
			return
	if not await _until(_all_carriers_aboard, voyage):
		return
	if not await _wait(0.4, voyage):
		return
	for leg in waves.size():
		barge.fly_to(leg + 2)
		if leg == escort_leg and escort_group != null:
			escort_group.trigger(true)
		if not await _wait(board_delay_seconds, voyage):
			return
		waves[leg].trigger(true)
		if not await _until(func() -> bool: return not barge.is_moving() and waves[leg].signal_emitted, voyage):
			return
	barge.fly_to(waves.size() + 2)
	if not await _until(func() -> bool: return not barge.is_moving(), voyage):
		return
	_running = false
	completed.emit(self)
	execute_next_event()


## Waits a physics frame at a time until the condition holds. False if the voyage was abandoned meanwhile.
func _until(condition: Callable, voyage: int) -> bool:
	while not condition.call():
		await get_tree().physics_frame
		if voyage != _voyage:
			return false
	return voyage == _voyage


func _wait(seconds: float, voyage: int) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	return await _until(func() -> bool: return Time.get_ticks_msec() >= end, voyage)


func _all_carriers_aboard() -> bool:
	var players := get_node_or_null(^"../../../Players")
	if players == null:
		return false
	var aboard := 0
	for child in players.get_children():
		var player := child as PlayerLocal
		if player == null or player.is_dead:
			continue
		if not barge.deck.contains(player.global_position, 0.3):
			return false
		aboard += 1
	return aboard > 0
