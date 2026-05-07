extends EnemyState

func enter() -> void:
	enemy.play_dead_animation()
	enemy.velocity = Vector3.ZERO
	enemy.set_collision_layer_value(1, false)
	enemy.set_collision_layer_value(2, false)
	enemy.set_collision_layer_value(3, false)
	enemy.set_collision_mask_value(1, false)
	enemy.set_collision_mask_value(2, false)
	enemy.set_collision_mask_value(3, false)
	var hit_box := enemy.get_node_or_null("HitBox") as Area3D
	if hit_box != null:
		hit_box.set_deferred("monitoring", false)
		hit_box.set_deferred("monitorable", false)
		for node in hit_box.find_children("*", "CollisionShape3D", true, false):
			var shape_node := node as CollisionShape3D
			if shape_node != null:
				shape_node.set_deferred("disabled", true)
	await enemy.get_tree().create_timer(enemy.DEATH_FREE_DELAY_SECONDS).timeout
	if is_instance_valid(enemy):
		enemy.queue_free()
