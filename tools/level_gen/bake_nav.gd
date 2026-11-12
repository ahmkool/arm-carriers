extends SceneTree
## Bakes a navmesh from a level's floor GridMap and writes it to JSON. Never saves the scene.
## FLOOR_GRIDMAP picks another floor node (default Level/NavigationRegion3D/GridMapFloor). BAKE_CELL_Z_MIN and
## BAKE_CELL_Z_MAX keep only cells in that z range, to bake one part of a level on its own.
## BAKE_PLATFORMS_UNDER names a node whose children are walkway platforms (bridge platforms that stay raised):
## each adds a flat floor cell (item BAKE_PLATFORM_ITEM, default 62, the castle tiles' flat top) where it stands,
## so the navmesh runs over the walkways too.
## Children of the navigation region with the metadata `bake_walkways` (true) are baked too, as they stand: decks
## that aren't GridMap tiles, such as narrow wooden tracks, so enemies can walk them.
## Run through godot.sh. Compile errors about autoloads are expected in --script mode and harmless here:
## the scene is only instantiated, not added to the tree, so no gameplay script runs.


func _initialize() -> void:
	var level: Node = (load(OS.get_environment("LEVEL_SCENE")) as PackedScene).instantiate()
	var floor_path := OS.get_environment("FLOOR_GRIDMAP")
	if floor_path.is_empty():
		floor_path = "Level/NavigationRegion3D/GridMapFloor"
	var source := (level.get_node(floor_path) as GridMap).duplicate() as GridMap
	_keep_cells_between(source, OS.get_environment("BAKE_CELL_Z_MIN"), OS.get_environment("BAKE_CELL_Z_MAX"))
	_add_platform_cells(source, level, OS.get_environment("BAKE_PLATFORMS_UNDER"), OS.get_environment("BAKE_PLATFORM_ITEM"))
	var region := NavigationRegion3D.new()
	region.navigation_mesh = NavigationMesh.new()
	region.add_child(source)
	if OS.get_environment("FLOOR_GRIDMAP").is_empty():
		for child in level.get_node("Level/NavigationRegion3D").get_children():
			if child.get_meta("bake_walkways", false):
				region.add_child(child.duplicate())
				continue
			if child is not GridMap or child.name == "GridMapFloor":
				continue
			var extra := (child as GridMap).duplicate() as GridMap
			_keep_cells_between(extra, OS.get_environment("BAKE_CELL_Z_MIN"), OS.get_environment("BAKE_CELL_Z_MAX"))
			region.add_child(extra)
	root.add_child(region)
	await process_frame
	region.bake_navigation_mesh(false)
	_write_result(region.navigation_mesh)


func _keep_cells_between(grid: GridMap, z_min_text: String, z_max_text: String) -> void:
	var z_min := -100000 if z_min_text.is_empty() else int(z_min_text)
	var z_max := 100000 if z_max_text.is_empty() else int(z_max_text)
	for cell in grid.get_used_cells():
		if cell.z < z_min or cell.z > z_max:
			grid.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)


func _add_platform_cells(grid: GridMap, level: Node, parent_path: String, item_text: String) -> void:
	if parent_path.is_empty():
		return
	var item := 62 if item_text.is_empty() else int(item_text)
	var added := 0
	for platform in level.get_node(parent_path).get_children():
		if platform is not Node3D:
			continue
		var cell := grid.local_to_map((platform as Node3D).position)
		grid.set_cell_item(Vector3i(cell.x, -1, cell.z), item)
		added += 1
	print("BAKED platform cells=", added)


func _write_result(mesh: NavigationMesh) -> void:
	var polygons: Array = []
	for i in mesh.get_polygon_count():
		polygons.append(mesh.get_polygon(i))
	print("BAKED vertices=", mesh.get_vertices().size(), " polygons=", polygons.size())
	var file := FileAccess.open(OS.get_environment("BAKE_OUT"), FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"uid": ResourceUID.id_to_text(ResourceUID.create_id()),
		"vertices": var_to_str(mesh.get_vertices()),
		"polygons": var_to_str(polygons),
	}))
	file.close()
	quit(0 if polygons.size() > 0 else 1)
