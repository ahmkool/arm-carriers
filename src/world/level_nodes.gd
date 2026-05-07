class_name LevelNodes
extends RefCounted


static func find_world(from_node: Node) -> WorldLocal:
	var current: Node = from_node
	while current != null:
		var world := current as WorldLocal
		if world != null:
			return world
		current = current.get_parent()
	return null


static func get_players(from_node: Node) -> Players:
	var world := find_world(from_node)
	if world == null:
		return null
	return world.get_node_or_null("Players") as Players
