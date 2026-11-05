class_name MenuSpring
extends RefCounted
## Damped spring used for the menu's bouncy motion. A damping ratio below 1 overshoots.

var value: float
var target: float
var velocity := 0.0

var _stiffness: float
var _damping: float


func _init(initial: float, stiffness: float, damping_ratio: float) -> void:
	value = initial
	target = initial
	_stiffness = stiffness
	_damping = 2.0 * damping_ratio * sqrt(stiffness)


func step(delta: float) -> void:
	velocity += (_stiffness * (target - value) - _damping * velocity) * delta
	value += velocity * delta
