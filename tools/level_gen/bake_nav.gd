extends SceneTree
## Bakes a navmesh from a level's floor GridMap and writes it to JSON. Never saves the scene.
## Run through godot.sh. Compile errors about autoloads are expected in --script mode and harmless here:
## the scene is only instantiated, not added to the tree, so no gameplay script runs.


func _initialize() -> void:
	var level: Node = (load(OS.get_environment("LEVEL_SCENE")) as PackedScene).instantiate()
	var source := level.get_node("Level/NavigationRegion3D/GridMapFloor") as GridMap
	var region := NavigationRegion3D.new()
	region.navigation_mesh = NavigationMesh.new()
	region.add_child(source.duplicate())
	root.add_child(region)
	await process_frame
	region.bake_navigation_mesh(false)
	_write_result(region.navigation_mesh)


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
