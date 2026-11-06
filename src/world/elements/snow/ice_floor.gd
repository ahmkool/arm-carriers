class_name IceFloor
extends RefCounted
## Whether a body stands on ice: a GridMap cell whose MeshLibrary item name starts with "Ice",
## or any floor body (or one of its parents) with a `slippery` metadata set to true.

const META := &"slippery"
const ITEM_PREFIX := "Ice"
const MIN_FLOOR_NORMAL_Y := 0.7
const MAX_PARENTS_CHECKED := 3


## From the body's last move_and_slide. Returns `fallback` on a frame where it touched no floor.
static func under(body: CharacterBody3D, fallback: bool) -> bool:
	for index in body.get_slide_collision_count():
		var collision := body.get_slide_collision(index)
		if collision.get_normal().y < MIN_FLOOR_NORMAL_Y:
			continue
		return _is_ice(collision.get_collider() as Node, collision.get_position())
	return fallback


static func _is_ice(node: Node, point: Vector3) -> bool:
	if node == null:
		return false
	var tagged := _tagged_self_or_parent(node)
	if tagged:
		return bool(tagged.get_meta(META))
	var grid := node as GridMap
	if grid == null or grid.mesh_library == null:
		return false
	var item := grid.get_cell_item(grid.local_to_map(grid.to_local(point + Vector3.DOWN * 0.1)))
	if item == GridMap.INVALID_CELL_ITEM:
		return false
	return grid.mesh_library.get_item_name(item).begins_with(ITEM_PREFIX)


static func _tagged_self_or_parent(node: Node) -> Node:
	var current := node
	for _step in MAX_PARENTS_CHECKED + 1:
		if current == null:
			return null
		if current.has_meta(META):
			return current
		current = current.get_parent()
	return null
