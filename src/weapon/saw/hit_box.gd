extends Area3D

@export var damage: int = 1

func _on_hit_area_body_entered(body: Node) -> void:
	if body is not EnemyLocal:
		return
	Health.apply_damage(body, damage, global_position)
