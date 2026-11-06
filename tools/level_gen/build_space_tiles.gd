extends SceneTree
## Builds src/world/elements/space/space_tiles.tres: station deck plating, its hull, glowing rim trims,
## and KayKit Space Base props standing on a plate. Each prop item is one GridMap cell, so props block
## movement and the navmesh bakes around them with no extra work.
##   godot --headless --path . --script tools/level_gen/build_space_tiles.gd
## Space Base pieces sit on a 2 m grid; PROP_SCALE fits them to the game's 3 m cells.

const OUT := "res://src/world/elements/space/space_tiles.tres"
const PANEL_SHADER := "res://src/world/elements/space/station_panels.gdshader"
const PROPS_DIR := "res://assets/models/space_base/"
const CELL := 2.999
const PROP_SCALE := 1.5
## A cell at GridMap layer y has its centre at 2y + 1. The floor is layer -1, so its top is at local +0.01.
const FLOOR_TOP := 0.01
const PLATE_DEPTH := 1.0
const TRIM_COLOR := Color(0.3, 0.85, 1.0)
## Rim trims share the floor's cells, so they go on lower layers and are lifted back up (see _add_trim).
const TRIM_LAYERS := {"TrimN": -3, "TrimS": -4, "TrimW": -5, "TrimE": -6}
## name: [gltf, collision shrink]. Collision is the prop's bounding box, shrunk so carriers can brush past.
const PROPS := {
	"BaseModuleA": ["basemodule_A", 0.85], "BaseModuleB": ["basemodule_B", 0.85], "BaseModuleC": ["basemodule_C", 0.85],
	"BaseModuleD": ["basemodule_D", 0.85], "BaseModuleE": ["basemodule_E", 0.85], "Garage": ["basemodule_garage", 0.85],
	"Dome": ["dome", 0.85], "EcoModule": ["eco_module", 0.85], "StructureTall": ["structure_tall", 0.8],
	"StructureLow": ["structure_low", 0.8], "WaterStorage": ["water_storage", 0.85], "CargoDepot": ["cargodepot_A", 0.85],
	"CargoA": ["cargo_A_stacked", 0.9], "CargoB": ["cargo_B_stacked", 0.9], "LandingPad": ["landingpad_large", 0.9],
	"LandingPadSmall": ["landingpad_small", 0.9], "Lander": ["lander_A", 0.8], "Dropship": ["dropship", 0.85],
	"SolarRoof": ["roofmodule_solarpanels", 0.9], "Antenna": ["windturbine_tall", 0.5], "Lights": ["lights", 0.6],
	"Drill": ["drill_structure", 0.8], "Command": ["mobile_base_command", 0.85], "Tunnel": ["tunnel_straight_A", 0.9],
}
## Scenery with no plate and no collision: asteroids.
const ROCKS := {"RocksA": "rocks_A", "RocksB": "rocks_B"}

var _library := MeshLibrary.new()
var _next_id := 0
var _panel := ShaderMaterial.new()
var _hull := ShaderMaterial.new()
var _trim := StandardMaterial3D.new()
## Every Space Base piece uses the same texture, so they all share the first material found.
var _prop_material: Material


func _initialize() -> void:
	_setup_materials()
	_add_plate()
	_add_hull()
	for trim in TRIM_LAYERS:
		_add_trim(trim, TRIM_LAYERS[trim])
	for prop in PROPS:
		_add_prop(prop, PROPS[prop][0], PROPS[prop][1])
	for rock in ROCKS:
		_add_rock(rock, ROCKS[rock])
	var error := ResourceSaver.save(_library, OUT)
	print("SAVED items=", _next_id, " error=", error)
	quit(error)


func _setup_materials() -> void:
	_panel.shader = load(PANEL_SHADER)
	_hull.shader = load(PANEL_SHADER)
	_hull.set_shader_parameter("hull_color", Color(0.12, 0.13, 0.17))
	_hull.set_shader_parameter("window_strength", 0.0)
	_trim.albedo_color = TRIM_COLOR
	_trim.emission_enabled = true
	_trim.emission = TRIM_COLOR
	_trim.emission_energy_multiplier = 2.5
	_trim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED


func _plate_transform() -> Transform3D:
	return Transform3D(Basis(), Vector3(0, FLOOR_TOP - PLATE_DEPTH / 2.0, 0))


func _plate_mesh() -> BoxMesh:
	var box := BoxMesh.new()
	box.size = Vector3(CELL, PLATE_DEPTH, CELL)
	return box


func _plate_shape() -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(CELL, PLATE_DEPTH, CELL)
	return shape


func _new_item(item_name: String, mesh: Mesh, shapes: Array) -> void:
	_library.create_item(_next_id)
	_library.set_item_name(_next_id, item_name)
	_library.set_item_mesh(_next_id, mesh)
	_library.set_item_shapes(_next_id, shapes)
	_next_id += 1


func _add_plate() -> void:
	var mesh := ArrayMesh.new()
	_append(mesh, _plate_mesh(), _plate_transform(), _panel)
	_new_item("Plate", mesh, [_plate_shape(), _plate_transform()])


func _add_hull() -> void:
	## Layer -2, under each plate: a slightly inset keel, so deck edges read as thick station slabs.
	var box := BoxMesh.new()
	box.size = Vector3(CELL - 0.3, 2.0, CELL - 0.3)
	var mesh := ArrayMesh.new()
	_append(mesh, box, Transform3D(Basis(), Vector3(0, 0.01, 0)), _hull)
	_new_item("Hull", mesh, [])


func _add_trim(trim_name: String, layer: int) -> void:
	var lift := (FLOOR_TOP - 0.03) - (2 * layer + 1 - (2 * -1 + 1))
	var half := CELL / 2.0 - 0.05
	var box := BoxMesh.new()
	var offset := Vector3.ZERO
	match trim_name:
		"TrimN":
			box.size = Vector3(CELL, 0.08, 0.1)
			offset = Vector3(0, lift, -half)
		"TrimS":
			box.size = Vector3(CELL, 0.08, 0.1)
			offset = Vector3(0, lift, half)
		"TrimW":
			box.size = Vector3(0.1, 0.08, CELL)
			offset = Vector3(-half, lift, 0)
		"TrimE":
			box.size = Vector3(0.1, 0.08, CELL)
			offset = Vector3(half, lift, 0)
	var mesh := ArrayMesh.new()
	_append(mesh, box, Transform3D(Basis(), offset), _trim)
	_new_item(trim_name, mesh, [])


func _add_prop(prop_name: String, file: String, shrink: float) -> void:
	var mesh := ArrayMesh.new()
	_append(mesh, _plate_mesh(), _plate_transform(), _panel)
	var placed := Transform3D(Basis().scaled(Vector3.ONE * PROP_SCALE), Vector3(0, FLOOR_TOP, 0))
	var bounds := _append_scene(mesh, file, placed)
	var shape := BoxShape3D.new()
	var size := bounds.size
	shape.size = Vector3(size.x * shrink, size.y, size.z * shrink)
	var shapes := [_plate_shape(), _plate_transform(), shape, Transform3D(Basis(), bounds.get_center())]
	_new_item(prop_name, mesh, shapes)


func _add_rock(rock_name: String, file: String) -> void:
	var mesh := ArrayMesh.new()
	_append_scene(mesh, file, Transform3D())
	_new_item(rock_name, mesh, [])


## Adds every mesh in a glTF scene to `mesh`, and returns their combined bounds after `placed`.
func _append_scene(mesh: ArrayMesh, file: String, placed: Transform3D) -> AABB:
	var scene := (load(PROPS_DIR + file + ".gltf") as PackedScene).instantiate()
	var bounds := AABB()
	var first := true
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		var xform := placed * _transform_to_root(instance, scene)
		for surface in instance.mesh.get_surface_count():
			_append_surface(mesh, instance.mesh, surface, xform, _shared_prop_material(instance.mesh.surface_get_material(surface)))
		var piece := xform * instance.mesh.get_aabb()
		bounds = piece if first else bounds.merge(piece)
		first = false
	scene.free()
	assert(not first, "no meshes in " + file)
	return bounds


func _shared_prop_material(found: Material) -> Material:
	if _prop_material == null:
		_prop_material = found
	return _prop_material


func _transform_to_root(node: Node3D, root: Node) -> Transform3D:
	var xform := node.transform
	var parent := node.get_parent()
	while parent != root and parent is Node3D:
		xform = (parent as Node3D).transform * xform
		parent = parent.get_parent()
	return xform


func _append(mesh: ArrayMesh, source: Mesh, xform: Transform3D, material: Material) -> void:
	_append_surface(mesh, source, 0, xform, material)


func _append_surface(mesh: ArrayMesh, source: Mesh, surface: int, xform: Transform3D, material: Material) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.append_from(source, surface, xform)
	tool.commit(mesh)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)
