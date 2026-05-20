class_name ChaseBehavior
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

	intent.move_direction = enemy.get_path_direction_to(enemy.target_player.global_position)
