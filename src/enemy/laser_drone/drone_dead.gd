extends "res://src/enemy/winged_mech/mech_dead.gd"
## Death state for the Laser Drone: immediately kills its laser beam and tumbles out of the air.

const LaserDroneBehaviorScript := preload("res://src/enemy/laser_drone/laser_drone_behavior.gd")

var _visual: Node3D


func enter() -> void:
	var behavior := enemy.behavior as LaserDroneBehaviorScript
	if behavior == null:
		behavior = enemy.get_node_or_null("LaserDroneBehavior") as LaserDroneBehaviorScript
	if behavior != null:
		behavior.shutdown_weapon()
	_visual = enemy.get_node_or_null("Visual") as Node3D
	super.enter()


func physics_update(delta: float) -> void:
	super.physics_update(delta)
	if _visual != null and absf(enemy.velocity.y) > 0.05:
		_visual.rotate_x(3.4 * delta)
		_visual.rotate_z(2.1 * delta)
