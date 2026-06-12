extends Area3D

@export var damage: int = 1

@onready var _hit_sfx: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var sword_specifics: SwordSpecifics = get_parent() as SwordSpecifics

const PITCH_MIN := 0.88
const PITCH_MAX := 1.12


func _on_hit_area_body_entered(body: Node) -> void:
	_try_apply_damage(body)


func _on_hit_area_body_exited(body: Node) -> void:
	_try_apply_damage(body)


func _try_apply_damage(body: Node) -> void:
	if body is not EnemyLocal:
		return
	if sword_specifics == null:
		return
	if not sword_specifics.is_strike_active:
		return
	if not Health.apply_damage(body, damage, _get_damage_source_position()):
		return
	_play_hit_sfx()


func _play_hit_sfx() -> void:
	_hit_sfx.pitch_scale = randf_range(PITCH_MIN, PITCH_MAX)
	_hit_sfx.play()


func _get_damage_source_position() -> Vector3:
	var blade_start := get_node_or_null("../BladeStart") as Node3D
	if blade_start != null:
		return blade_start.global_position
	return global_position
