class_name RotorBarge
extends Node3D
## A large rotor deck that flies between stops, for fights on a moving platform. BargeVoyageEvent drives it.
## Stop 0 is where it is placed in the scene. The others are offsets from there, in the order it flies them.

signal arrived(stop: int)

## Offsets of each stop from the barge's placed position. Stop 0 must be Vector3.ZERO.
@export var stops: PackedVector3Array = PackedVector3Array([Vector3.ZERO])
## Cruising speed, in metres per second. Each leg eases in and out, so its average speed is lower.
@export var speed := 3.4

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _elapsed := 0.0
var _duration := 0.0
var _target_stop := 0
var _moving := false

@onready var body: AnimatableBody3D = $AnimatableBody3D
@onready var deck: MovingFloor = $AnimatableBody3D/MovingFloor


func is_moving() -> bool:
	return _moving


## The stop it sits at or is flying to.
func target_stop() -> int:
	return _target_stop


func fly_to(stop: int) -> void:
	_from = body.position
	_to = stops[stop]
	_target_stop = stop
	_elapsed = 0.0
	# Easing in and out doubles the peak speed over an even leg, so the leg takes that much longer.
	_duration = maxf(_from.distance_to(_to) / speed * 1.5, 0.1)
	_moving = true


func snap_to(stop: int) -> void:
	_moving = false
	_target_stop = stop
	body.position = stops[stop]


func _physics_process(delta: float) -> void:
	if not _moving:
		return
	_elapsed = minf(_elapsed + delta, _duration)
	body.position = _from.lerp(_to, smoothstep(0.0, 1.0, _elapsed / _duration))
	if _elapsed < _duration:
		return
	_moving = false
	arrived.emit(_target_stop)
