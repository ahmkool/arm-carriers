extends SceneTree
## Builds src/world/elements/lava/lava_tiles.tres: the hill tiles' shapes and collision, with a basalt material.
## assets/mesh_library/ is git-ignored, so the result lives next to the rest of the lava art.
## Only needs re-running to change which tiles are included: the look is in lava_rock.gdshader.
##   godot --headless --path . --script tools/level_gen/build_lava_tiles.gd

const SOURCE := "res://assets/mesh_library/tiles_Color6_no_shadows.tres"
const OUT := "res://src/world/elements/lava/lava_tiles.tres"
const ROCK_SHADER := "res://src/world/elements/lava/lava_rock.gdshader"
const ITEMS: Array[String] = [
	"Hill_Top_E_Center", "Hill_Top_F_Side", "Hill_Top_H_Side", "Hill_Top_G_OuterCorner", "Hill_Top_G_InnerCorner",
	"Hill_Cliff_Tall_H_Side", "Hill_Cliff_Tall_I_OuterCorner", "Hill_Cliff_Tall_I_InnerCorner",
	"Rock_3_A", "Rock_3_C", "Rock_3_F", "Rock_5_A", "Rock_5_C", "Rock_6_A",
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
	quit(error)


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
