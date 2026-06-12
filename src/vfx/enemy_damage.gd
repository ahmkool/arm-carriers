extends Node3D

@onready var _particles: GPUParticles3D = $GPUParticles3D

var _damage_source_position := Vector3.ZERO
var _has_damage_source := false


func set_damage_source(damage_source_position: Vector3) -> void:
	_damage_source_position = damage_source_position
	_has_damage_source = true


func _ready() -> void:
	call_deferred("_start_effect")
	_schedule_cleanup()


func _start_effect() -> void:
	if _has_damage_source:
		_orient_particles_away_from_source()
	_particles.emitting = true


func _orient_particles_away_from_source() -> void:
	var away := global_position - _damage_source_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return
	_particles.look_at(global_position + away.normalized(), Vector3.UP)


func _schedule_cleanup() -> void:
	var delay := _particles.lifetime + 0.15
	get_tree().create_timer(delay).timeout.connect(queue_free, CONNECT_ONE_SHOT)
