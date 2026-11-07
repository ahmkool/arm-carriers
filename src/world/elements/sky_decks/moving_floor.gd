class_name MovingFloor
extends Node3D
## The walkable top of a platform that moves, such as a rotor barge. Moving platforms can't be in the navmesh, so
## enemies standing on one steer straight at their target instead, kept inside this rectangle (see EnemyLocal).
## Sits at the centre of the deck's top surface, under the moving body so it travels with it.

const GROUP := &"moving_floors"
## How far above or below the deck top a body still counts as standing on it.
const HEIGHT_BELOW := 1.0
const HEIGHT_ABOVE := 2.5

## Width (x) and depth (z) of the walkable top, in metres.
@export var size := Vector2(15.0, 12.0)


func _enter_tree() -> void:
	add_to_group(GROUP)


## The moving floor under a point, or null when it is over solid ground or the void.
static func under(tree: SceneTree, point: Vector3) -> MovingFloor:
	for node in tree.get_nodes_in_group(GROUP):
		var moving_floor := node as MovingFloor
		if moving_floor.contains(point):
			return moving_floor
	return null


## Whether the point is over the deck, at least `margin` in from every edge.
func contains(point: Vector3, margin := 0.0) -> bool:
	var local := global_transform.affine_inverse() * point
	if local.y < -HEIGHT_BELOW or local.y > HEIGHT_ABOVE:
		return false
	return absf(local.x) <= size.x * 0.5 - margin and absf(local.z) <= size.y * 0.5 - margin


## The closest point to `point` that is at least `margin` in from the edges, at the point's own height.
func clamp_inside(point: Vector3, margin: float) -> Vector3:
	var local := global_transform.affine_inverse() * point
	var half_x := maxf(size.x * 0.5 - margin, 0.0)
	var half_z := maxf(size.y * 0.5 - margin, 0.0)
	local.x = clampf(local.x, -half_x, half_x)
	local.z = clampf(local.z, -half_z, half_z)
	var clamped := global_transform * local
	clamped.y = point.y
	return clamped
