extends Node3D

const GROUP_NAME := &"camera_shake"

@export var decay_per_second: float = 2.8
@export var max_position_offset: float = 0.35
@export var max_rotation_degrees: float = 2.2
@export var noise_frequency: float = 18.0
@export var use_trauma_squared: bool = true

var trauma: float = 0.0

var _time: float = 0.0
var _noise: FastNoiseLite


func _ready() -> void:
	add_to_group(GROUP_NAME)
	if Engine.is_editor_hint():
		return
	var cf := get_node_or_null("/root/CameraFeedback")
	if cf != null and cf.has_method("register_shake_pivot"):
		cf.register_shake_pivot(self)
	_noise = FastNoiseLite.new()
	_noise.seed = randi()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.85


func add_trauma(amount: float) -> void:
	trauma = minf(1.0, trauma + amount)


func get_trauma() -> float:
	return trauma


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	trauma *= exp(-decay_per_second * delta)
	if trauma < 0.001:
		trauma = 0.0
		position = Vector3.ZERO
		rotation = Vector3.ZERO
		return
	_time += delta * noise_frequency
	var amp := trauma
	if use_trauma_squared:
		amp *= trauma
	var pos_scale := max_position_offset * amp
	var x := _noise.get_noise_3d(_time, 100.0, 200.0)
	var y := _noise.get_noise_3d(300.0, _time, 400.0)
	var z := _noise.get_noise_3d(500.0, 600.0, _time)
	position = Vector3(x, y, z) * pos_scale
	var rx := _noise.get_noise_3d(_time + 50.0, 50.0, 50.0)
	var ry := _noise.get_noise_3d(150.0, _time + 50.0, 250.0)
	var rz := _noise.get_noise_3d(350.0, 450.0, _time + 50.0)
	var rot_scale := deg_to_rad(max_rotation_degrees) * amp
	rotation = Vector3(rx * rot_scale, ry * rot_scale, rz * rot_scale)
