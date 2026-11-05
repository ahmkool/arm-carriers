extends Area3D

@export var damage: int = 1

@onready var _hit_sfx: AudioStreamPlayer3D = $AudioStreamPlayer3D
@onready var sword_specifics: SwordSpecifics = get_parent() as SwordSpecifics

const PITCH_MIN := 0.88
const PITCH_MAX := 1.12
const SLASH_SCENE := preload("res://src/vfx/sword_slash.tscn")
const SLASH_HEIGHT := 1.0
## Each further enemy hit in one dash raises the pitch, up to `COMBO_PITCH_MAX_STEPS`.
const COMBO_PITCH_STEP := 1.12
const COMBO_PITCH_MAX_STEPS := 5


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
	_play_hit_sfx(body as Node3D, sword_specifics.register_dash_hit())
	_spawn_slash(body as Node3D)
	ImpactFeedback.play_sword_hit()


## Each hit gets its own player, so several hits in one tick don't cut each other off.
func _play_hit_sfx(enemy: Node3D, previous_hits: int) -> void:
	var combo_steps := mini(previous_hits, COMBO_PITCH_MAX_STEPS)
	var pitch := randf_range(PITCH_MIN, PITCH_MAX) * pow(COMBO_PITCH_STEP, combo_steps)
	ImpactFeedback.play_sfx(_hit_sfx.stream, enemy.global_position, pitch, _hit_sfx.volume_db)


func _spawn_slash(enemy: Node3D) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var slash := SLASH_SCENE.instantiate() as SwordSlash
	scene_root.add_child(slash)
	slash.global_position = enemy.global_position + Vector3.UP * SLASH_HEIGHT
	slash.align_to(sword_specifics.travel_direction)


func _get_damage_source_position() -> Vector3:
	var blade_start := get_node_or_null("../BladeStart") as Node3D
	if blade_start != null:
		return blade_start.global_position
	return global_position
