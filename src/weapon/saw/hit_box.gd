extends Area3D

@export var damage: int = 1

@onready var _hit_sfx: AudioStreamPlayer3D = $AudioStreamPlayer3D

const PITCH_MIN := 0.88
const PITCH_MAX := 1.12


func _on_hit_area_body_entered(body: Node) -> void:
	if body is not EnemyLocal:
		return
	if not Health.apply_damage(body, damage, global_position):
		return
	_play_hit_sfx()


func _play_hit_sfx() -> void:
	_hit_sfx.pitch_scale = randf_range(PITCH_MIN, PITCH_MAX)
	_hit_sfx.play()
