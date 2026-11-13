extends SceneTree
## Builds src/world/elements/canyon/canyon_tiles.tres: the hill tiles' shapes and collision, with a sandstone material.
## assets/mesh_library/ is git-ignored, so the result lives next to the rest of the canyon art.
## Only needs re-running to change which tiles are included: the look is in canyon_rock.gdshader.
## Also saves the rocks in ROCKS as meshes in src/world/elements/canyon/rocks/, so a level can place them freely,
## at any size and angle, instead of on the GridMap's 3 m grid.
##   godot --headless --path . --script tools/level_gen/build_canyon_tiles.gd

const SOURCE := "res://assets/mesh_library/tiles_Color6_no_shadows.tres"
const OUT := "res://src/world/elements/canyon/canyon_tiles.tres"
const ROCK_SHADER := "res://src/world/elements/canyon/canyon_rock.gdshader"
const ROCK_DIR := "res://src/world/elements/canyon/rocks"
const ROCKS: Array[String] = [
	"Rock_3_A", "Rock_3_C", "Rock_3_F", "Rock_3_H", "Rock_3_K",
	"Rock_5_A", "Rock_5_C", "Rock_5_E",
	"Rock_6_A", "Rock_6_C", "Rock_6_E",
]
const ITEMS: Array[String] = [
	"Hill_Top_E_Center", "Hill_Top_F_Side", "Hill_Top_H_Side", "Hill_Top_G_OuterCorner", "Hill_Top_G_InnerCorner",
	"Hill_Cliff_Tall_H_Side", "Hill_Cliff_Tall_I_OuterCorner", "Hill_Cliff_Tall_I_InnerCorner",
	"Rock_1_A", "Rock_1_C", "Rock_1_F", "Rock_1_J", "Rock_2_A", "Rock_2_C",
]


func _initialize() -> void:
	var source := load(SOURCE) as MeshLibrary
	var material := ShaderMaterial.new()
	material.shader = load(ROCK_SHADER)
	var out := MeshLibrary.new()
	for index in ITEMS.size():
		_copy_item(source, out, index, material)
	var error := ResourceSaver.save(out, OUT)
	print("SAVED items=", ITEMS.size(), " error=", error)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROCK_DIR))
	for name in ROCKS:
		error = maxi(error, _save_rock(source, name, material))
	quit(error)


## Saves the rock as a mesh with the sandstone material, its item transform baked in, and prints its bounds:
## the level builder needs them to stand a rock on the ground.
func _save_rock(source: MeshLibrary, name: String, material: ShaderMaterial) -> int:
	var id := _find_item(source, name)
	var tool := SurfaceTool.new()
	var mesh := source.get_item_mesh(id)
	var item_transform := source.get_item_mesh_transform(id)
	var out := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		tool.create_from(mesh, surface)
		var arrays := tool.commit_to_arrays()
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		for i in vertices.size():
			vertices[i] = item_transform * vertices[i]
			normals[i] = (item_transform.basis * normals[i]).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(surface, material)
	var path := "%s/%s.res" % [ROCK_DIR, name.to_lower()]
	var error := ResourceSaver.save(out, path)
	var box := out.get_aabb()
	print("ROCK %s min=%s size=%s error=%d" % [name, box.position, box.size, error])
	return error


func _copy_item(source: MeshLibrary, out: MeshLibrary, index: int, material: ShaderMaterial) -> void:
	var name := ITEMS[index]
	var id := _find_item(source, name)
	var mesh := source.get_item_mesh(id).duplicate() as ArrayMesh
	for surface in mesh.get_surface_count():
		mesh.surface_set_material(surface, material)
	out.create_item(index)
	out.set_item_name(index, name)
	out.set_item_mesh(index, mesh)
	out.set_item_mesh_transform(index, source.get_item_mesh_transform(id))
	out.set_item_mesh_cast_shadow(index, source.get_item_mesh_cast_shadow(id))
	out.set_item_shapes(index, source.get_item_shapes(id))


func _find_item(source: MeshLibrary, name: String) -> int:
	var id := source.find_item_by_name(name + "_Color6")
	assert(id >= 0, "missing tile " + name)
	return id
