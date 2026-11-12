class_name BreakableDeck
extends Node
## Knocks plates out of a station deck and puts them back, for fights where the floor itself is a threat.
##
## The floor GridMap stays the source of truth for collision: a broken cell is emptied, so a carrier on it falls,
## and refilled when it returns. The hull GridMap under it (the keel and the glowing edge trims) is emptied with
## it, or the hole would show a solid keel and read as walkable. GridMaps can't animate one cell, so the visible
## break uses short-lived copies of the cell's meshes: a crack warning on the plate, then the plate and its keel
## tumbling away, and on return the same rising back into place.
##
## Cells can also be added at runtime (`add_platform`), with their keel and trims, and crumbled away for good.
## Every respawn puts the deck back as the scene authored it.

signal cell_fell(cell: Vector2i)

const GROUP := &"breakable_deck"
const FLOOR_LAYER := -1
const HULL_LAYER := -2
## Edge trims sit on their own layers, one per side (see levelgen._station_hull).
const TRIM_LAYERS := {Vector2i(0, -1): -3, Vector2i(0, 1): -4, Vector2i(-1, 0): -5, Vector2i(1, 0): -6}
const TRIM_NAMES := {Vector2i(0, -1): "TrimN", Vector2i(0, 1): "TrimS", Vector2i(-1, 0): "TrimW", Vector2i(1, 0): "TrimE"}
const FALL_DEPTH := 28.0
const FALL_SECONDS := 1.8
const RISE_SECONDS := 0.6
const PERMANENT := -1.0

@export var floor_map: GridMap
@export var hull_map: GridMap
@export var crack_color := Color(1.0, 0.3, 0.12, 0.75)

## Cell -> {"floor": [item, orientation], "hull": {layer: [item, orientation]}, "until": seconds or INF}
var _broken := {}
## Cells showing a crack, about to fall, with their crack overlay: they still hold, but can't be broken again.
var _cracking := {}
## Cells added at runtime, which a respawn removes again.
var _added := {}
var _effects: Array[Node] = []
## Bumped by every restore, so timers started before a respawn do nothing after it.
var _generation := 0
var _crack_material: StandardMaterial3D


static func find(tree: SceneTree) -> BreakableDeck:
	return tree.get_first_node_in_group(GROUP) as BreakableDeck


func _ready() -> void:
	add_to_group(GROUP)
	add_to_group(&"checkpoint_resettable")
	_crack_material = StandardMaterial3D.new()
	_crack_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crack_material.albedo_color = crack_color
	_crack_material.disable_receive_shadows = true


# ---- Queries. ----

func cell_at(world_position: Vector3) -> Vector2i:
	var cell := floor_map.local_to_map(floor_map.to_local(world_position))
	return Vector2i(cell.x, cell.z)


## The middle of a cell's walking surface. The plate's top isn't the GridMap cell's top, so its height above the
## cell centre is measured once with a ray onto a standing plate.
func cell_top(cell: Vector2i) -> Vector3:
	var centre := floor_map.to_global(floor_map.map_to_local(Vector3i(cell.x, FLOOR_LAYER, cell.y)))
	return centre + Vector3.UP * _surface_offset()


var _offset_measured := false
var _offset := 0.0


func _surface_offset() -> float:
	if _offset_measured:
		return _offset
	for used in floor_map.get_used_cells():
		if used.y != FLOOR_LAYER:
			continue
		var centre := floor_map.to_global(floor_map.map_to_local(used))
		var query := PhysicsRayQueryParameters3D.create(centre + Vector3.UP * 4.0, centre + Vector3.DOWN * 2.0, floor_map.collision_layer)
		var hit := floor_map.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		_offset = (hit.position as Vector3).y - centre.y
		_offset_measured = true
		return _offset
	return 0.0


func has_tile(cell: Vector2i) -> bool:
	return floor_map.get_cell_item(Vector3i(cell.x, FLOOR_LAYER, cell.y)) != GridMap.INVALID_CELL_ITEM


## A plate that stands and isn't already cracking.
func is_intact(cell: Vector2i) -> bool:
	return has_tile(cell) and not _cracking.has(cell)


func hole_count() -> int:
	return _broken.size()


func is_broken(cell: Vector2i) -> bool:
	return _broken.has(cell)


## True when a living carrier stands over the cell.
func is_occupied(cell: Vector2i) -> bool:
	for player in _living_players():
		if cell_at(player.global_position) == cell:
			return true
	return false


# ---- Breaking. ----

## Cracks the plate for `crack_seconds`, then drops it. It comes back after `hole_seconds`, or never when that is
## PERMANENT. A cell already broken for a while is made permanent if asked. Returns false when there was nothing
## to break.
func break_cell(cell: Vector2i, crack_seconds: float, hole_seconds: float) -> bool:
	if _broken.has(cell):
		_extend_hole(cell, hole_seconds)
		return false
	if not is_intact(cell):
		return false
	_cracking[cell] = _show_crack(cell, crack_seconds)
	get_tree().create_timer(maxf(crack_seconds, 0.0)).timeout.connect(_drop_cell.bind(cell, hole_seconds, _generation))
	return true


## Crumbles cells for good, each after its own delay from now. `delays` maps Vector2i -> seconds.
func crumble(delays: Dictionary, crack_seconds: float) -> void:
	for cell in delays:
		get_tree().create_timer(delays[cell]).timeout.connect(_break_if_current.bind(cell, crack_seconds, PERMANENT, _generation))


func _break_if_current(cell: Vector2i, crack_seconds: float, hole_seconds: float, generation: int) -> void:
	if generation != _generation:
		return
	break_cell(cell, crack_seconds, hole_seconds)


func _extend_hole(cell: Vector2i, hole_seconds: float) -> void:
	if hole_seconds != PERMANENT:
		return
	_broken[cell]["until"] = INF


func _drop_cell(cell: Vector2i, hole_seconds: float, generation: int) -> void:
	if generation != _generation:
		return
	_free_effect(_cracking.get(cell))
	_cracking.erase(cell)
	if not has_tile(cell):
		return
	var record := {"floor": _take(floor_map, cell, FLOOR_LAYER), "hull": {}, "until": INF}
	var falling: Array[Dictionary] = [record["floor"]]
	for layer in [HULL_LAYER] + TRIM_LAYERS.values():
		var taken := _take(hull_map, cell, layer)
		if taken.is_empty():
			continue
		record["hull"][layer] = taken
		falling.append(taken)
	if hole_seconds != PERMANENT:
		record["until"] = _now() + hole_seconds
	_broken[cell] = record
	_spawn_falling(falling)
	cell_fell.emit(cell)


## Empties one GridMap cell and returns what was there, with where it stood, for the falling copy and the return.
func _take(map: GridMap, cell: Vector2i, layer: int) -> Dictionary:
	var at := Vector3i(cell.x, layer, cell.y)
	var item := map.get_cell_item(at)
	if item == GridMap.INVALID_CELL_ITEM:
		return {}
	var orientation := map.get_cell_item_orientation(at)
	var piece := {"map": map, "at": at, "item": item, "orientation": orientation}
	map.set_cell_item(at, GridMap.INVALID_CELL_ITEM)
	return piece


# ---- Returning. ----

func _process(_delta: float) -> void:
	var now := _now()
	for cell in _broken.keys():
		if _broken[cell]["until"] > now:
			continue
		_return_cell(cell)


func _return_cell(cell: Vector2i) -> void:
	var record: Dictionary = _broken[cell]
	_broken.erase(cell)
	var pieces: Array[Dictionary] = [record["floor"]]
	for layer in record["hull"]:
		pieces.append(record["hull"][layer])
	_spawn_rising(pieces)
	get_tree().create_timer(RISE_SECONDS).timeout.connect(_put_back_if_current.bind(pieces, _generation))


func _put_back_if_current(pieces: Array[Dictionary], generation: int) -> void:
	if generation != _generation:
		return
	_put_back(pieces)


func _put_back(pieces: Array[Dictionary]) -> void:
	for piece in pieces:
		var map := piece["map"] as GridMap
		map.set_cell_item(piece["at"], piece["item"], piece["orientation"])


## Puts every broken plate back at once and removes everything added at runtime. Runs on every respawn.
func restore_all() -> void:
	_generation += 1
	for effect in _effects:
		if is_instance_valid(effect):
			effect.queue_free()
	_effects.clear()
	_cracking.clear()
	for cell in _broken.keys():
		var record: Dictionary = _broken[cell]
		if _added.has(cell):
			continue
		var pieces: Array[Dictionary] = [record["floor"]]
		for layer in record["hull"]:
			pieces.append(record["hull"][layer])
		_put_back(pieces)
	_broken.clear()
	for cell in _added.keys():
		_clear_cell(cell)
	_added.clear()


func reset_to_checkpoint() -> void:
	restore_all()


# ---- Adding platforms. ----

## Adds plates (with keel and edge trims) on `cells`, rising into place with a short stagger.
func add_platform(cells: Array[Vector2i]) -> void:
	var lookup := {}
	for cell in cells:
		lookup[cell] = true
	var plate := _item_like(floor_map, "Plate", FLOOR_LAYER)
	var keel := _item_like(hull_map, "Hull", HULL_LAYER)
	var index := 0
	for cell in cells:
		var pieces: Array[Dictionary] = [{"map": floor_map, "at": Vector3i(cell.x, FLOOR_LAYER, cell.y), "item": plate, "orientation": 0}]
		pieces.append({"map": hull_map, "at": Vector3i(cell.x, HULL_LAYER, cell.y), "item": keel, "orientation": 0})
		pieces.append_array(_trims_for(cell, lookup))
		_added[cell] = true
		get_tree().create_timer(0.03 * index).timeout.connect(_rise_and_place.bind(pieces, _generation))
		index += 1


func _rise_and_place(pieces: Array[Dictionary], generation: int) -> void:
	if generation != _generation:
		return
	_spawn_rising(pieces)
	get_tree().create_timer(RISE_SECONDS).timeout.connect(_put_back_if_current.bind(pieces, generation))


func _trims_for(cell: Vector2i, lookup: Dictionary) -> Array[Dictionary]:
	var trims: Array[Dictionary] = []
	for side in TRIM_LAYERS:
		if lookup.has(cell + side):
			continue
		var item := hull_map.mesh_library.find_item_by_name(TRIM_NAMES[side])
		if item < 0:
			continue
		trims.append({"map": hull_map, "at": Vector3i(cell.x, TRIM_LAYERS[side], cell.y), "item": item, "orientation": 0})
	return trims


## The item named `item_name`, or failing that whatever the first used cell of that layer holds.
func _item_like(map: GridMap, item_name: String, layer: int) -> int:
	var item := map.mesh_library.find_item_by_name(item_name)
	if item >= 0:
		return item
	for used in map.get_used_cells():
		if used.y == layer:
			return map.get_cell_item(used)
	return 0


func _clear_cell(cell: Vector2i) -> void:
	floor_map.set_cell_item(Vector3i(cell.x, FLOOR_LAYER, cell.y), GridMap.INVALID_CELL_ITEM)
	for layer in [HULL_LAYER] + TRIM_LAYERS.values():
		hull_map.set_cell_item(Vector3i(cell.x, layer, cell.y), GridMap.INVALID_CELL_ITEM)


# ---- Visuals. ----

func _show_crack(cell: Vector2i, seconds: float) -> Node3D:
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(floor_map.cell_size.x, floor_map.cell_size.z) * 0.92
	mesh.mesh = plane
	mesh.material_override = _crack_material.duplicate()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_effect(mesh)
	mesh.global_position = cell_top(cell) + Vector3.UP * 0.04
	var tween := mesh.create_tween().set_loops(maxi(1, int(seconds / 0.24)))
	tween.tween_property(mesh.material_override, "albedo_color:a", 0.15, 0.12)
	tween.tween_property(mesh.material_override, "albedo_color:a", crack_color.a, 0.12)
	return mesh


func _spawn_falling(pieces: Array[Dictionary]) -> void:
	var holder := _copy_pieces(pieces)
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 0.4), randf_range(-1.0, 1.0)) * 2.2
	var tween := holder.create_tween().set_parallel(true)
	tween.tween_property(holder, "global_position:y", holder.global_position.y - FALL_DEPTH, FALL_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(holder, "rotation", spin, FALL_SECONDS)
	tween.chain().tween_callback(_free_effect.bind(holder))


func _spawn_rising(pieces: Array[Dictionary]) -> void:
	var holder := _copy_pieces(pieces)
	var top := holder.global_position
	holder.global_position = top + Vector3.DOWN * 6.0
	var tween := holder.create_tween()
	tween.tween_property(holder, "global_position", top, RISE_SECONDS).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_free_effect.bind(holder))


## Mesh copies of GridMap cells, gathered under one node at the first piece's cell so they move together.
func _copy_pieces(pieces: Array[Dictionary]) -> Node3D:
	var holder := Node3D.new()
	_add_effect(holder)
	var first := pieces[0]
	var origin_map := first["map"] as GridMap
	holder.global_position = origin_map.to_global(origin_map.map_to_local(first["at"]))
	for piece in pieces:
		var map := piece["map"] as GridMap
		var library := map.mesh_library
		var mesh := MeshInstance3D.new()
		mesh.mesh = library.get_item_mesh(piece["item"])
		holder.add_child(mesh)
		var basis := map.get_basis_with_orthogonal_index(piece["orientation"])
		var cell_transform := map.global_transform * Transform3D(basis, map.map_to_local(piece["at"]))
		mesh.global_transform = cell_transform * library.get_item_mesh_transform(piece["item"])
	return holder


func _add_effect(node: Node3D) -> void:
	add_child(node)
	_effects.append(node)


func _free_effect(node: Node) -> void:
	_effects.erase(node)
	if is_instance_valid(node):
		node.queue_free()


# ---- Helpers. ----

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _living_players() -> Array[PlayerLocal]:
	var living: Array[PlayerLocal] = []
	var players := get_tree().current_scene.get_node_or_null(^"Players")
	if players == null:
		return living
	for child in players.get_children():
		var player := child as PlayerLocal
		if player == null or player.is_dead:
			continue
		living.append(player)
	return living
