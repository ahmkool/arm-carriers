class_name BargeCrewGroup
extends NormalEnemyGroup
## A crew that rides its own RotorBarge into a fight. Place the barge at its hidden parking spot (stop 0) with its
## fight spot as stop 1, and the crew standing on its deck. Until triggered, the group and the barge are hidden and
## the crew waits. Triggered, the barge shows, flies to its fight spot, and the crew turns offensive on arrival; the
## barge then sways left and right until the crew is dead, and stays where it stopped.
## A checkpoint reset puts the barge back at its parking spot, hidden, with a fresh crew aboard. Marked as defeated,
## the barge hovers empty at its fight spot.

@export var barge: RotorBarge
@export var sway_amplitude := 4.5
@export var sway_period_seconds := 6.0
## Firing range given to the crew on arrival, in metres. They can't cross the gap to close in, so their usual range,
## meant for enemies that can walk up, would leave some unable to reach the carriers' barge.
@export var engage_range := 18.0

## Range exports on the behaviours that fight at a distance.
const RANGE_PROPERTIES: Array[StringName] = [&"max_distance", &"cast_max_distance"]

## Bumped to abandon an approach in progress when the group is reset.
var _approach := 0
var _triggered := false


func _ready() -> void:
	super._ready()
	# Deferred: the barge sits under Level, which is set up after Enemies.
	_stow.call_deferred()


func trigger(offensive: bool = true) -> void:
	if _triggered or not offensive or signal_emitted:
		return
	_triggered = true
	_approach += 1
	_fly_in(_approach)


func reset() -> void:
	super.reset()
	_triggered = false
	_approach += 1
	_stow()


func mark_as_defeated() -> void:
	super.mark_as_defeated()
	_approach += 1
	if barge == null:
		return
	barge.snap_to(1)
	barge.visible = true


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if signal_emitted and barge != null and barge.is_swaying():
		barge.stop_sway()


func _stow() -> void:
	visible = false
	if barge == null:
		return
	barge.snap_to(0)
	barge.visible = false


func _fly_in(approach: int) -> void:
	if barge == null:
		return
	visible = true
	barge.visible = true
	barge.fly_to(1)
	while barge.is_moving():
		await get_tree().physics_frame
		if approach != _approach:
			return
	for enemy in _list_enemy_locals():
		_extend_range(enemy)
		enemy.is_offensive = true
	if signal_emitted:
		return
	barge.sway(sway_amplitude, sway_period_seconds)


func _extend_range(enemy: EnemyLocal) -> void:
	if enemy.behavior == null:
		return
	for property in RANGE_PROPERTIES:
		var current: Variant = enemy.behavior.get(property)
		if current == null:
			continue
		enemy.behavior.set(property, maxf(float(current), engage_range))
