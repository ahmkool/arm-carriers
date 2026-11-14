extends Node3D
## Pulses a rooftop aviation warning beacon out of phase with neighbouring corners.

@export var cycle_seconds: float = 2.6

var _bulb: MeshInstance3D
var _phase: float = 0.0
var _mat: StandardMaterial3D


func _ready() -> void:
	_bulb = get_node_or_null("Bulb") as MeshInstance3D
	if _bulb == null:
		return
	_phase = global_position.x * 0.37 + global_position.z * 0.23
	_mat = (_bulb.material_override as StandardMaterial3D)
	if _mat == null:
		return
	_mat = _mat.duplicate() as StandardMaterial3D
	_bulb.material_override = _mat


func _process(_delta: float) -> void:
	if _mat == null:
		return
	var wave := 0.5 + 0.5 * sin((Time.get_ticks_msec() * 0.001 / cycle_seconds) * TAU + _phase)
	var pulse := pow(wave, 3.0)
	_mat.albedo_color = Color(0.35 + 1.85 * pulse, 0.05 + 0.14 * pulse, 0.06 + 0.12 * pulse, 1.0)
