extends MechState
## Gun burst: brakes (in the air or on foot), aims, fires a few bolts at the target, then hands back to `return_state`.
## Recoil is procedural (a nose-up kick and a spinning barrel): the KayKit 2H shoot clip swings the gun far off the
## aim line at the moment of each shot, which made the bolts leave sideways from the barrel.

@export var bolt_emitter: FireballEmitter
## The minigun's barrel cluster, spun around its own axis while the burst lasts.
@export var spinning_barrel: Node3D
## The state to go back to after the burst: hovering for the winged mech, idle for the one on foot.
@export var return_state := &"hovering"
@export var bolt_count := 3
## Delay before the first bolt, so the stop and the aim read as a tell.
@export var aim_seconds := 0.45
@export var seconds_between_bolts := 0.3
@export var hold_after_seconds := 0.5
@export var brake := 4.0
@export var recoil_kick_degrees := 8.0
## How quickly the recoil settles, roughly per second.
@export var recoil_recovery := 10.0
## Barrel spin at full speed, in turns per second.
@export var barrel_spin_turns_per_second := 4.0

var _bolts_left := 0
var _next_bolt_in := 0.0
var _hold_remaining := 0.0
var _recoil_degrees := 0.0


func enter() -> void:
	super.enter()
	_bolts_left = bolt_count
	_next_bolt_in = aim_seconds
	_hold_remaining = hold_after_seconds
	_recoil_degrees = 0.0


func physics_update(delta: float) -> void:
	_brake(delta)
	hold_height(delta)
	_recoil_degrees *= exp(-recoil_recovery * delta)
	aim_gun(delta, _recoil_degrees)
	_spin_barrel(delta)
	if _bolts_left > 0:
		_tick_burst(delta)
		return
	_hold_remaining -= delta
	if _hold_remaining > 0.0:
		return
	enemy_state_machine.transition_to(String(return_state))


func _brake(delta: float) -> void:
	var w := 1.0 - exp(-brake * delta)
	enemy.velocity.x = lerpf(enemy.velocity.x, 0.0, w)
	enemy.velocity.z = lerpf(enemy.velocity.z, 0.0, w)


func _spin_barrel(delta: float) -> void:
	if spinning_barrel == null:
		return
	spinning_barrel.rotate_object_local(Vector3.BACK, TAU * barrel_spin_turns_per_second * delta)


func _tick_burst(delta: float) -> void:
	_next_bolt_in -= delta
	if _next_bolt_in > 0.0:
		return
	_next_bolt_in = seconds_between_bolts
	_bolts_left -= 1
	_fire()


func _fire() -> void:
	_recoil_degrees = recoil_kick_degrees
	if bolt_emitter == null:
		return
	bolt_emitter.spawn_fireball()
