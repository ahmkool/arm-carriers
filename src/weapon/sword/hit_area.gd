extends Area3D

@onready var sword_specifics: SwordSpecifics = get_parent() as SwordSpecifics


func _on_hit_area_body_entered(body: Node) -> void:
	if body is not EnemyLocal:
		return
	if sword_specifics == null:
		return
	if not sword_specifics.is_strike_active:
		return
	(body as EnemyLocal).die(_get_damage_source_position())

func _on_hit_area_body_exited(body: Node) -> void:
	if body is not EnemyLocal:
		return
	if sword_specifics == null:
		return
	if not sword_specifics.is_strike_active:
		return
	(body as EnemyLocal).die(_get_damage_source_position())


func _get_damage_source_position() -> Vector3:
	var blade_start := get_node_or_null("../BladeStart") as Node3D
	if blade_start != null:
		return blade_start.global_position
	return global_position
