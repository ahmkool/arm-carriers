extends Node3D

@onready var _debris: GPUParticles3D = $Debris
@onready var _fire: GPUParticles3D = $Fire
@onready var _sfx: AudioStreamPlayer3D = $AudioStreamPlayer3D


func _ready() -> void:
	_debris.emitting = true
	_fire.emitting = true
	_sfx.play()
	await get_tree().create_timer(0.8).timeout
	queue_free()
