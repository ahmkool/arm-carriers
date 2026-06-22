class_name BossAxeEnrageBurst
extends Node3D

const CLEANUP_PADDING_SEC := 0.15

@onready var _focus: GPUParticles3D = $Focus
@onready var _burst: GPUParticles3D = $Burst
@onready var _sfx: AudioStreamPlayer3D = $AudioStreamPlayer3D


func _ready() -> void:
	_focus.emitting = true
	_burst.emitting = true
	_sfx.play()
	_schedule_cleanup()


func _schedule_cleanup() -> void:
	var particle_lifetime := maxf(_focus.lifetime, _burst.lifetime)
	var delay := particle_lifetime + CLEANUP_PADDING_SEC
	delay = maxf(delay, _estimate_sfx_duration())
	get_tree().create_timer(delay).timeout.connect(queue_free, CONNECT_ONE_SHOT)


func _estimate_sfx_duration() -> float:
	if _sfx.stream == null:
		return 0.0
	return _sfx.stream.get_length() / _sfx.pitch_scale
