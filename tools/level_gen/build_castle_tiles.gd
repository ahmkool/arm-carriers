extends SceneTree
## Builds src/world/elements/medieval/castle_tiles.tres: the hill tiles' shapes and collision, with a castle stone material,
## plank decks on the wooden walkway tiles, and green grass tufts to grow between the stones.
## Unlike the lava and snow tiles, each item keeps its id from tiles_Color7_no_shadows.tres, so a level painted with that
## palette can switch libraries without touching its cells (the medieval reskins do this).
## Re-run only to change which tiles are included: the look is in castle_stone.gdshader.
##   godot --headless --path . --script tools/level_gen/build_castle_tiles.gd

const ID_SOURCE := "res://assets/mesh_library/tiles_Color7_no_shadows.tres"
const GRASS_SOURCE := "res://assets/mesh_library/tiles_Color1_no_shadows.tres"
const OUT := "res://src/world/elements/medieval/castle_tiles.tres"
const STONE_SHADER := "res://src/world/elements/medieval/castle_stone.gdshader"
const STONE_ITEMS: Array[String] = [
	"Hill_Top_E_Center", "Hill_Top_F_Side", "Hill_Top_H_Side", "Hill_Top_G_OuterCorner", "Hill_Top_G_InnerCorner",
	"Hill_Top_C_OuterCorner", "Hill_Top_C_InnerCorner", "Hill_Top_I_InnerCorner", "Hill_Top_I_OuterCorner",
	"Hill_Cliff_Tall_H_Side", "Hill_Cliff_Tall_G_OuterCorner", "Hill_Cliff_Tall_G_InnerCorner",
	"Hill_Cliff_Tall_I_OuterCorner", "Hill_Cliff_Tall_I_InnerCorner", "Hill_12x6x8",
]
## Single-cell wooden walkways: a stone pier with a plank deck. These names carry no palette suffix.
const TIMBER_ITEMS: Array[String] = ["Wooden_Platform_Top"]
## Taken from the green palette but stored under the pink palette's ids.
const GRASS_ITEMS: Array[String] = [
	"Grass_1_A", "Grass_1_B", "Grass_1_B_Singlesided", "Grass_1_C", "Grass_1_D_Singlesided", "Grass_2_A",
	"Bush_4_D", "Bush_1_A",
]


func _initialize() -> void:
	var id_source := load(ID_SOURCE) as MeshLibrary
	var grass_source := load(GRASS_SOURCE) as MeshLibrary
	var material := ShaderMaterial.new()
	material.shader = load(STONE_SHADER)
	var timber := ShaderMaterial.new()
	timber.shader = material.shader
	timber.set_shader_parameter("timber_top", true)
	var out := MeshLibrary.new()
	for name in STONE_ITEMS:
		var id := _find_item(id_source, name + "_Color7")
		_copy_item(id_source, id, out, id, material)
	for name in TIMBER_ITEMS:
		var id := _find_item(id_source, name)
		_copy_item(id_source, id, out, id, timber)
	for name in GRASS_ITEMS:
		var id := _find_item(id_source, name + "_Color7")
		_copy_item(grass_source, _find_item(grass_source, name + "_Color1"), out, id, null)
	var error := ResourceSaver.save(out, OUT)
	print("SAVED items=", out.get_item_list().size(), " error=", error)
	quit(error)


func _copy_item(source: MeshLibrary, source_id: int, out: MeshLibrary, id: int, material: Material) -> void:
	var mesh := source.get_item_mesh(source_id).duplicate() as ArrayMesh
	if material != null:
		for surface in mesh.get_surface_count():
			mesh.surface_set_material(surface, material)
	out.create_item(id)
	out.set_item_name(id, source.get_item_name(source_id))
	out.set_item_mesh(id, mesh)
	out.set_item_mesh_transform(id, source.get_item_mesh_transform(source_id))
	out.set_item_mesh_cast_shadow(id, source.get_item_mesh_cast_shadow(source_id))
	out.set_item_shapes(id, source.get_item_shapes(source_id))


func _find_item(source: MeshLibrary, name: String) -> int:
	var id := source.find_item_by_name(name)
	assert(id >= 0, "missing tile " + name)
	return id
