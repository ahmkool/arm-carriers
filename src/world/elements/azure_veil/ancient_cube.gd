extends Node3D
## Gently bobs and slowly turns an ancient floating monolith cube in the Uranian gas atmosphere.

@export var bob_amplitude: float = 0.75
@export var bob_period_seconds: float = 9.5
@export var spin_degrees_per_second: float = 3.2
@export var show_halo: bool = true

@onready var _halo: Node3D = get_node_or_null("ArcaneHalo")

var _base_y: float = 0.0
var _phase: float = 0.0
var _axis: Vector3 = Vector3.UP


func _ready() -> void:
	_base_y = position.y
	_phase = position.x * 0.31 + position.z * 0.19 + position.y * 0.13
	_axis = Vector3(sin(_phase) * 0.45, 1.0, cos(_phase * 1.3) * 0.45).normalized()
	if _halo != null:
		_halo.visible = show_halo


func _process(delta: float) -> void:
	var time := Time.get_ticks_msec() / 1000.0
	position.y = _base_y + sin(time * TAU / maxf(bob_period_seconds, 0.1) + _phase) * bob_amplitude
	if absf(spin_degrees_per_second) > 0.001:
		rotate(_axis, deg_to_rad(spin_degrees_per_second) * delta)
	if _halo != null and _halo.visible:
		_halo.rotate_y(-deg_to_rad(10.0) * delta)
