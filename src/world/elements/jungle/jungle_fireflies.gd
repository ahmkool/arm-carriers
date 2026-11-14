class_name JungleFireflies
extends Node3D
## Drifting bioluminescent fireflies and rising jungle spores in a volume that follows the camera.
## Purely visual: no collision and no gameplay interaction.

@export var follow_offset := Vector3(0.0, -9.0, -10.0)

@onready var _fireflies: GPUParticles3D = $Fireflies
@onready var _spores: GPUParticles3D = $Spores


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var target := Vector3(camera.global_position.x + follow_offset.x, 1.8, camera.global_position.z + follow_offset.z)
	_fireflies.global_position = target
	_spores.global_position = target
