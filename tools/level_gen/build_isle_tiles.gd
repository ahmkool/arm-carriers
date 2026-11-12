extends SceneTree
## Builds src/world/elements/storm_isles/isle_tiles.tres: the dungeon's stone blocks (Floor, Pillar, WallLow) standing
## in the sea, plus sea rocks copied from the green hill tiles. Everything uses isle_stone.gdshader.
## assets/mesh_library/ is git-ignored, so the result lives next to the rest of the storm isles art.
## Re-run only to change the items: the look is in the shader.
##   godot --headless --path . --script tools/level_gen/build_isle_tiles.gd
##
## Floor cells sit at GridMap y = -1 (top at world y = -1, like every level). A floor block runs 7 m down, past the
## water at y = -4.6, so its side shows as a sea wall. Pillars and low walls go one layer up (y = 0), on a floor cell.

const OUT := "res://src/world/elements/storm_isles/isle_tiles.tres"
const STONE_SHADER := "res://src/world/elements/storm_isles/isle_stone.gdshader"
const ROCK_SOURCE := "res://assets/mesh_library/tiles_Color1_no_shadows.tres"
const ROCKS: Array[String] = ["Rock_1_A", "Rock_1_C", "Rock_4_A", "Rock_5_A", "Rock_5_C", "Rock_6_A"]
const CELL := 2.999
const FLOOR_DEPTH := 7.0
const PILLAR_WIDTH := 1.7
## GridMap cells are 2 m tall and centred, so a block one layer above the floor (cell centre y = 1) starts 2 m
## below its centre, on the walking surface at y = -1.
const UPPER_BOTTOM := -2.0


func _initialize() -> void:
	var out := MeshLibrary.new()
	var floor_material := _stone(Color(0.31, 0.33, 0.37), Color(0.34, 0.36, 0.4), 1.5)
	var block_material := _stone(Color(0.42, 0.43, 0.46), Color(0.46, 0.47, 0.5), 1.25)
	_add_box(out, 0, "Floor", Vector3(CELL, FLOOR_DEPTH, CELL), -FLOOR_DEPTH, floor_material)
	_add_box(out, 1, "Pillar", Vector3(PILLAR_WIDTH, 2.8, PILLAR_WIDTH), UPPER_BOTTOM, block_material)
	_add_box(out, 2, "PillarBroken", Vector3(PILLAR_WIDTH, 1.3, PILLAR_WIDTH), UPPER_BOTTOM, block_material)
	_add_box(out, 3, "WallLow", Vector3(CELL, 1.0, CELL), UPPER_BOTTOM, block_material)
	var source := load(ROCK_SOURCE) as MeshLibrary
	for index in ROCKS.size():
		_add_rock(source, out, 4 + index, ROCKS[index], block_material)
	var error := ResourceSaver.save(out, OUT)
	print("SAVED items=", 4 + ROCKS.size(), " error=", error)
	quit(error)


func _stone(side: Color, top: Color, block_size: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(STONE_SHADER)
	material.set_shader_parameter("stone_color", side)
	material.set_shader_parameter("top_color", top)
	material.set_shader_parameter("block_size", block_size)
	return material


## A box whose bottom is `bottom` metres from the centre of the cell it is placed in. Floor blocks (y = -1, centre
## at world y = -1) hang below their centre, so their top is the walking surface.
func _add_box(out: MeshLibrary, id: int, item_name: String, size: Vector3, bottom: float, material: ShaderMaterial) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var shape := BoxShape3D.new()
	shape.size = size
	var offset := Transform3D(Basis.IDENTITY, Vector3(0, bottom + size.y * 0.5, 0))
	out.create_item(id)
	out.set_item_name(id, item_name)
	out.set_item_mesh(id, mesh)
	out.set_item_mesh_transform(id, offset)
	out.set_item_shapes(id, [shape, offset])


func _add_rock(source: MeshLibrary, out: MeshLibrary, id: int, rock_name: String, material: ShaderMaterial) -> void:
	var source_id := source.find_item_by_name(rock_name + "_Color1")
	assert(source_id >= 0, "missing tile " + rock_name)
	var mesh := source.get_item_mesh(source_id).duplicate() as ArrayMesh
	for surface in mesh.get_surface_count():
		mesh.surface_set_material(surface, material)
	out.create_item(id)
	out.set_item_name(id, rock_name)
	out.set_item_mesh(id, mesh)
	out.set_item_mesh_transform(id, source.get_item_mesh_transform(source_id))
