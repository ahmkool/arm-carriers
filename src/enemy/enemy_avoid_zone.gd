class_name EnemyAvoidZone
extends RefCounted
## Places ground enemies keep out of, such as moving spike walls, which the baked navmesh knows nothing about.
## A zone is any node in GROUP with these methods:
##   keeps_out(point: Vector3, margin: float) -> bool
##   push_out(point: Vector3, margin: float) -> Vector3   the nearest point clear of the zone
##   get_escape_direction() -> Vector3                     flat, the way out
## EnemyLocal moves its goal out of every zone, and steers so it never walks into one.

const GROUP := &"enemy_avoid_zones"
## How close an enemy will come to a zone.
const MARGIN := 0.9
## How far ahead an enemy checks before taking a step.
const LOOKAHEAD := 0.5


static func zones(tree: SceneTree) -> Array[Node]:
	return tree.get_nodes_in_group(GROUP)


## The goal moved clear of every zone.
static func clear_goal(zone_list: Array[Node], goal: Vector3) -> Vector3:
	for zone in zone_list:
		goal = zone.push_out(goal, MARGIN)
	return goal


## The direction an enemy at `from` should take instead of `direction`: straight out of a zone it is inside,
## or along the edge of one it is about to walk into.
static func steer(zone_list: Array[Node], from: Vector3, direction: Vector3) -> Vector3:
	for zone in zone_list:
		if zone.keeps_out(from, MARGIN):
			return zone.get_escape_direction()
	for zone in zone_list:
		direction = _slide_along(zone, from, direction)
	return direction


static func _slide_along(zone: Node, from: Vector3, direction: Vector3) -> Vector3:
	if not zone.keeps_out(from + direction * LOOKAHEAD, MARGIN):
		return direction
	var out: Vector3 = zone.get_escape_direction()
	var slid := direction - out * minf(0.0, direction.dot(out))
	if slid.length_squared() < 0.01:
		return Vector3.ZERO
	return slid.normalized()
