extends Area3D

@onready var sword_specifics: SwordSpecifics = get_parent() as SwordSpecifics


func _on_hit_area_body_entered(body: Node) -> void:
	if body is not EnemyLocal:
		return
	if sword_specifics == null:
		return
	if not sword_specifics.is_strike_active:
		return
	(body as EnemyLocal).die()
