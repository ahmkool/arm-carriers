extends Node3D

## Slowly tumbles and bobs a piece of scenery, such as an asteroid. Not for anything players stand on.
@export var spin_degrees_per_second: float = 4.0
@export var amplitude: float = 0.8
@export var period_seconds: float = 11.0

var _base_y: float
var _phase: float
var _axis: Vector3


func _ready() -> void:
	_base_y = position.y
	_phase = position.x * 0.37 + position.z * 0.21
	_axis = Vector3(sin(_phase), 1.0, cos(_phase * 1.3)).normalized()


func _process(delta: float) -> void:
	var time := Time.get_ticks_msec() / 1000.0
	position.y = _base_y + sin(time * TAU / period_seconds + _phase) * amplitude
	rotate(_axis, deg_to_rad(spin_degrees_per_second) * delta)
