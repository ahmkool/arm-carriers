extends Node3D

## Gently bobs a decorative floating island. Not for anything players stand on.
@export var amplitude: float = 0.6
@export var period_seconds: float = 7.0

var _base_y: float
var _phase: float


func _ready() -> void:
	_base_y = position.y
	_phase = position.x * 0.37 + position.z * 0.21


func _process(_delta: float) -> void:
	var time := Time.get_ticks_msec() / 1000.0
	position.y = _base_y + sin(time * TAU / period_seconds + _phase) * amplitude
