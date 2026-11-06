class_name FrostGround
extends Node
## Freezes floor cells for a while by swapping them to their "Ice_" tile, which IceFloor makes slippery,
## then thaws them back. Cells that were ice already, and tiles with no ice version (props), are left alone.
## Everything thaws when this node leaves the tree, so a reset boss leaves no ice behind.

const FLOOR_PATH := "Level/NavigationRegion3D/GridMapFloor"
const ICE_PREFIX := "Ice_"
const FLOOR_LAYER := -1

## Cell -> {"until": seconds, "item": original item, "orientation": original orientation}.
var _frozen := {}
var _grid: GridMap


func freeze(center: Vector3, radius: float, seconds: float) -> int:
	var grid := _get_grid()
	if grid == null:
		return 0
	var until := Time.get_ticks_msec() / 1000.0 + seconds
	var reach := int(ceil(radius / grid.cell_size.x)) + 1
	var middle := grid.local_to_map(grid.to_local(center))
	var count := 0
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			count += _freeze_cell(grid, Vector3i(middle.x + dx, FLOOR_LAYER, middle.z + dz), center, radius, until)
	return count


func thaw_all() -> void:
	for cell in _frozen.keys():
		_thaw(cell)


func frozen_count() -> int:
	return _frozen.size()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for cell in _frozen.keys():
		if _frozen[cell]["until"] > now:
			continue
		_thaw(cell)


func _exit_tree() -> void:
	thaw_all()


func _freeze_cell(grid: GridMap, cell: Vector3i, center: Vector3, radius: float, until: float) -> int:
	var cell_centre := grid.to_global(grid.map_to_local(cell))
	if Vector2(cell_centre.x - center.x, cell_centre.z - center.z).length() > radius:
		return 0
	if _frozen.has(cell):
		_frozen[cell]["until"] = maxf(_frozen[cell]["until"], until)
		return 0
	var item := grid.get_cell_item(cell)
	if item == GridMap.INVALID_CELL_ITEM:
		return 0
	var name := grid.mesh_library.get_item_name(item)
	if name.begins_with(ICE_PREFIX):
		return 0
	var ice := grid.mesh_library.find_item_by_name(ICE_PREFIX + name)
	if ice < 0:
		return 0
	var orientation := grid.get_cell_item_orientation(cell)
	_frozen[cell] = {"until": until, "item": item, "orientation": orientation}
	grid.set_cell_item(cell, ice, orientation)
	return 1


func _thaw(cell: Vector3i) -> void:
	var grid := _get_grid()
	var original: Dictionary = _frozen[cell]
	_frozen.erase(cell)
	if grid == null:
		return
	grid.set_cell_item(cell, original["item"], original["orientation"])


func _get_grid() -> GridMap:
	if is_instance_valid(_grid):
		return _grid
	var scene := get_tree().current_scene if is_inside_tree() else null
	if scene == null:
		return null
	_grid = scene.get_node_or_null(FLOOR_PATH) as GridMap
	return _grid
