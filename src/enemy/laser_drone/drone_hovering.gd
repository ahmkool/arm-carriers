extends EnemyState
## Active flying state for the Laser Drone: hovers over the arena and aims/fires its 3D laser cannon.

const LaserDroneBehaviorScript := preload("res://src/enemy/laser_drone/laser_drone_behavior.gd")


func enter() -> void:
	var behavior := _drone_behavior()
	if behavior != null:
		behavior.capture_home()


func exit() -> void:
	var behavior := _drone_behavior()
	if behavior != null:
		behavior.shutdown_weapon()


func physics_update(delta: float) -> void:
	var behavior := _drone_behavior()
	if behavior != null:
		behavior.step_hover(delta)
	enemy.move_and_slide()


func _drone_behavior() -> LaserDroneBehaviorScript:
	if enemy == null:
		return null
	if enemy.behavior is LaserDroneBehaviorScript:
		return enemy.behavior as LaserDroneBehaviorScript
	return enemy.get_node_or_null("LaserDroneBehavior") as LaserDroneBehaviorScript
