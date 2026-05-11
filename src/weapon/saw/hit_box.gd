extends Area3D

func _on_hit_area_body_entered(body: Node) -> void:
	if body is not EnemyLocal:
		return
	(body as EnemyLocal).die()
