extends Node3D

## Flickers a brazier's light and flame. The phase comes from its position so they never pulse together.
@export var base_energy: float = 3.0
@export var flicker_amount: float = 0.22

@onready var _light: OmniLight3D = $Light
@onready var _flame: Node3D = $Flame

var _phase: float
var _flame_scale: Vector3


func _ready() -> void:
	_phase = global_position.x * 1.7 + global_position.z * 0.9
	_flame_scale = _flame.scale


func _process(_delta: float) -> void:
	var time := Time.get_ticks_msec() / 1000.0 + _phase
	var wave := sin(time * 9.0) * 0.5 + sin(time * 23.0) * 0.3 + sin(time * 3.7) * 0.2
	_light.light_energy = base_energy * (1.0 + wave * flicker_amount)
	_flame.scale = _flame_scale * Vector3(1.0 - wave * 0.08, 1.0 + wave * 0.18, 1.0 - wave * 0.08)
