class_name FootstepSurface
extends RefCounted
## Which footstep sound a floor makes.
## A floor body (or one of its parents) can say so with a `footstep_surface` metadata: grass, wood, stone or metal.
## Tiled GridMap floors are looked up by their MeshLibrary. Anything else counts as grass.

const GRASS := &"grass"
const WOOD := &"wood"
const STONE := &"stone"
const METAL := &"metal"
## Returned when the body touched no floor this frame, so the caller can keep the last surface.
const UNKNOWN := &""

const META := &"footstep_surface"
const MAX_PARENTS_CHECKED := 3
const MIN_FLOOR_NORMAL_Y := 0.7

const BY_MESH_LIBRARY := {
	"res://src/world/elements/dungeon/dungeon_tiles.tres": STONE,
	"res://src/world/elements/lava/lava_tiles.tres": STONE,
	"res://src/world/elements/medieval/castle_tiles.tres": STONE,
	"res://src/world/elements/sky_decks/deck_tiles.tres": WOOD,
	"res://src/world/elements/space/space_tiles.tres": METAL,
}


## The surface under a body, from its last move_and_slide.
static func under(body: CharacterBody3D) -> StringName:
	var floor_node := _floor_collider(body)
	if floor_node == null:
		return UNKNOWN
	return of_node(floor_node)


static func of_node(node: Node) -> StringName:
	var tagged := _tagged_self_or_parent(node)
	if tagged:
		return StringName(tagged.get_meta(META))
	if node is GridMap:
		return _of_grid_map(node)
	return GRASS


static func _floor_collider(body: CharacterBody3D) -> Node:
	for index in body.get_slide_collision_count():
		var collision := body.get_slide_collision(index)
		if collision.get_normal().y < MIN_FLOOR_NORMAL_Y:
			continue
		return collision.get_collider() as Node
	return null


static func _tagged_self_or_parent(node: Node) -> Node:
	var current := node
	for _step in MAX_PARENTS_CHECKED + 1:
		if current == null:
			return null
		if current.has_meta(META):
			return current
		current = current.get_parent()
	return null


static func _of_grid_map(grid_map: GridMap) -> StringName:
	if grid_map.mesh_library == null:
		return GRASS
	return BY_MESH_LIBRARY.get(grid_map.mesh_library.resource_path, GRASS)
