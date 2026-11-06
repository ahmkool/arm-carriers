extends Node
## Lists each camera framing in a level, and whether the enemies inside it can be reached on foot.
## A framing is only needed when some can't: a melee weapon can't touch them, and a gun must aim from far off.
## Run through godot.sh test with any level. Reachable means a navmesh path from the trigger that adds the framing.

var world: WorldLocal


func _ready() -> void:
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(3.0).timeout
	for area in _all_areas(world.get_node("Level")):
		_report_area(area)
	print("RESULT fails=0")
	get_tree().quit(0)


func _all_areas(node: Node) -> Array:
	var found: Array = []
	for child in node.get_children():
		if child is Area3D and child.has_signal("all_players_inside"):
			found.append(child)
		found.append_array(_all_areas(child))
	return found


func _report_area(area: Area3D) -> void:
	var corners: Array = []
	for connection in area.get_signal_connection_list("all_players_inside"):
		var target: Object = connection["callable"].get_object()
		if target is Node and "focal_point" in target and target.focal_point != null:
			corners.append((target.focal_point as Node3D).global_position)
	if corners.is_empty():
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in corners:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.z))
		hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.z))
	var reachable := 0
	var unreachable: Array = []
	var inside := 0
	for spot in _enemy_spots():
		if spot.x < lo.x - 1.5 or spot.x > hi.x + 1.5 or spot.z < lo.y - 1.5 or spot.z > hi.y + 1.5:
			continue
		inside += 1
		if _walkable_between(area.global_position, spot):
			reachable += 1
		else:
			unreachable.append("(%.0f, %.0f)" % [spot.x, spot.z])
	print("FRAMING %s: %d enemies inside, %d reachable on foot, unreachable at %s" % [area.name, inside, reachable, ", ".join(unreachable)])


func _enemy_spots() -> Array:
	var spots: Array = []
	for group in world.get_node("Enemies").get_children():
		var instanced := group.get_node_or_null("InstancedEnemies")
		if instanced != null:
			for e in instanced.get_children():
				spots.append((e as Node3D).global_position)
		var points := group.get_node_or_null("SpawnPoints")
		if points != null:
			for p in points.get_children():
				spots.append((p as Node3D).global_position)
	return spots


func _walkable_between(from: Vector3, to: Vector3) -> bool:
	var map := world.get_world_3d().navigation_map
	var target := NavigationServer3D.map_get_closest_point(map, to)
	if target.distance_to(Vector3(to.x, target.y, to.z)) > 1.5:
		return false
	var path := NavigationServer3D.map_get_path(map, from, target, true)
	return path.size() > 0 and path[path.size() - 1].distance_to(target) < 0.6
