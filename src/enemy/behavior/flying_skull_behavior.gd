class_name FlyingSkullBehavior
extends EnemyBehavior

func _think(_delta: float) -> void:
	if enemy == null or not enemy.is_offensive:
		return

	if not is_instance_valid(enemy.target_player):
		enemy.update_target_player()
	if is_instance_valid(enemy.target_player) and enemy.target_player.is_dead:
		enemy.update_target_player()
	if not is_instance_valid(enemy.target_player):
		return

	var to_target := enemy.target_player.global_position - enemy.global_position
	if to_target.length_squared() < 0.0001:
		return

	intent.move_direction = to_target.normalized()
