extends SceneTree
## Builds src/world/elements/jungle/jungle_tiles.tres from tiles_Color1_no_shadows.tres:
## - mossy ancient temple ruin ground tiles (the shapes build_floor uses), shaded by jungle_ruin_stone.gdshader;
## - interior obstacle props on temple plates (TemplePillar, TempleObelisk, JungleTreeA, JungleTreeB, MossBoulder)
##   with box collision so bake_nav.gd bakes around them;
## - non-colliding grass tufts (for build_decoration) and tropical scenery trees, bushes, and boulders for jungle islets.
##   godot --headless --path . --script tools/level_gen/build_jungle_tiles.gd

const SOURCE := "res://assets/mesh_library/tiles_Color1_no_shadows.tres"
const OUT := "res://src/world/elements/jungle/jungle_tiles.tres"
const STONE_SHADER := "res://src/world/elements/jungle/jungle_ruin_stone.gdshader"
const COVER_SHADER := "res://src/world/elements/jungle/jungle_cover.gdshader"

const GROUND := [
	"Hill_Top_E_Center", "Hill_Top_F_Side", "Hill_Top_H_Side", "Hill_Top_G_OuterCorner", "Hill_Top_G_InnerCorner",
	"Hill_Cliff_Tall_H_Side", "Hill_Cliff_Tall_I_OuterCorner", "Hill_Cliff_Tall_I_InnerCorner",
]
const GRASS := ["Grass_1_A", "Grass_1_B", "Grass_1_C", "Grass_2_A"]
const PROPS := {
	"JungleTreeA": ["Tree_1_A", Vector3(1.1, 4.0, 1.1)],
	"JungleTreeB": ["Tree_3_A", Vector3(1.1, 4.0, 1.1)],
	"MossBoulder": ["Rock_3_A", Vector3.ZERO],
}
const SCENERY := {
	"IsleTreeA": ["Tree_1_A", 1.35],
	"IsleTreeB": ["Tree_2_A", 1.35],
	"IsleTreeC": ["Tree_3_A", 1.4],
	"IsleTreeD": ["Tree_6_A", 1.3],
	"IsleTreeE": ["Tree_7_A", 1.3],
	"IsleBushA": ["Bush_1_A", 1.4],
	"IsleBushB": ["Bush_2_A", 1.4],
	"IsleBushC": ["Bush_4_A", 1.4],
	"IsleRockA": ["Rock_3_A", 1.3],
	"IsleRockB": ["Rock_5_A", 1.3],
	"IsleRockC": ["Rock_6_A", 1.3],
}

const PROP_SCALE := 1.25
const BOULDER_SHRINK := 0.8
const PLATE_TOP := 0.01

var _source: MeshLibrary
var _out := MeshLibrary.new()
var _next_id := 0
var _stone := ShaderMaterial.new()
var _ruin_block := ShaderMaterial.new()
var _jade_rune := StandardMaterial3D.new()
var _cover_by_texture := {}


func _initialize() -> void:
	_source = load(SOURCE) as MeshLibrary
	_stone.shader = load(STONE_SHADER)
	_ruin_block.shader = load(STONE_SHADER)
	_ruin_block.set_shader_parameter("flag_color", Color(0.38, 0.42, 0.34))
	_ruin_block.set_shader_parameter("wall_color", Color(0.36, 0.4, 0.33))
	_ruin_block.set_shader_parameter("course_height", 0.45)
	_jade_rune.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_jade_rune.albedo_color = Color(0.24, 1.35, 0.82, 1.0)
	for tile_name in GROUND:
		_add_ground(tile_name)
	for grass_name in GRASS:
		_add_grass(grass_name)
	_add_temple_pillar("TemplePillar", 2.9, true)
	_add_temple_pillar("TempleObelisk", 1.55, false)
	for prop_name in PROPS:
		_add_prop(prop_name, PROPS[prop_name][0], PROPS[prop_name][1])
	for scenery_name in SCENERY:
		_add_scenery(scenery_name, SCENERY[scenery_name][0], SCENERY[scenery_name][1])
	var error := ResourceSaver.save(_out, OUT)
	print("SAVED items=", _next_id, " error=", error)
	quit(error)


func _source_id(tile_name: String) -> int:
	var id := _source.find_item_by_name(tile_name + "_Color1")
	assert(id >= 0, "missing tile " + tile_name)
	return id


func _add_ground(tile_name: String) -> void:
	var id := _source_id(tile_name)
	var mesh := _source.get_item_mesh(id).duplicate() as ArrayMesh
	for surface in mesh.get_surface_count():
		mesh.surface_set_material(surface, _stone)
	_create(tile_name, mesh, _source.get_item_mesh_transform(id), _source.get_item_shapes(id))


func _add_grass(grass_name: String) -> void:
	var id := _source_id(grass_name)
	var mesh := ArrayMesh.new()
	_append(mesh, _source.get_item_mesh(id), _source.get_item_mesh_transform(id), null)
	_create(grass_name, mesh, Transform3D(), [])


func _add_temple_pillar(out_name: String, height: float, with_cap: bool) -> void:
	var plate_id := _source_id("Hill_Top_E_Center")
	var mesh := ArrayMesh.new()
	_append(mesh, _source.get_item_mesh(plate_id), _source.get_item_mesh_transform(plate_id), _stone)
	_append_box(mesh, Vector3(1.55, 0.36, 1.55), Vector3(0, PLATE_TOP + 0.18, 0), _ruin_block)
	_append_box(mesh, Vector3(1.18, height, 1.18), Vector3(0, PLATE_TOP + 0.36 + height * 0.5, 0), _ruin_block)
	_append_box(mesh, Vector3(1.24, 0.14, 1.24), Vector3(0, PLATE_TOP + 0.36 + height * 0.62, 0), _jade_rune)
	if with_cap:
		_append_box(mesh, Vector3(1.48, 0.3, 1.48), Vector3(0, PLATE_TOP + 0.36 + height + 0.15, 0), _ruin_block)
	var shapes := _source.get_item_shapes(plate_id).duplicate()
	var total_h := 0.36 + height + (0.3 if with_cap else 0.0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, total_h, 1.5)
	shapes.append(shape)
	shapes.append(Transform3D(Basis(), Vector3(0, PLATE_TOP + total_h * 0.5, 0)))
	_create(out_name, mesh, Transform3D(), shapes)


func _append_box(target: ArrayMesh, size: Vector3, centre: Vector3, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	_append(target, box, Transform3D(Basis(), centre), material)


func _add_prop(out_name: String, source_name: String, box: Vector3) -> void:
	var plate_id := _source_id("Hill_Top_E_Center")
	var prop_id := _source_id(source_name)
	var placed := Transform3D(Basis.from_scale(Vector3.ONE * PROP_SCALE), Vector3(0, PLATE_TOP, 0))
	var mesh := ArrayMesh.new()
	_append(mesh, _source.get_item_mesh(plate_id), _source.get_item_mesh_transform(plate_id), _stone)
	_append(mesh, _source.get_item_mesh(prop_id), placed * _source.get_item_mesh_transform(prop_id), null)
	var shapes := _source.get_item_shapes(plate_id).duplicate()
	var bounds := placed * (_source.get_item_mesh_transform(prop_id) * _source.get_item_mesh(prop_id).get_aabb())
	var size := box if box != Vector3.ZERO else bounds.size * BOULDER_SHRINK
	var shape := BoxShape3D.new()
	shape.size = size
	shapes.append(shape)
	shapes.append(Transform3D(Basis(), Vector3(bounds.get_center().x, PLATE_TOP + size.y * 0.5, bounds.get_center().z)))
	_create(out_name, mesh, Transform3D(), shapes)


func _add_scenery(out_name: String, source_name: String, scale_factor: float) -> void:
	var id := _source_id(source_name)
	var mesh := ArrayMesh.new()
	var xf := Transform3D(Basis.from_scale(Vector3.ONE * scale_factor)) * _source.get_item_mesh_transform(id)
	_append(mesh, _source.get_item_mesh(id), xf, null)
	_create(out_name, mesh, Transform3D(), [])


func _append(target: ArrayMesh, source: Mesh, xf: Transform3D, material: Material) -> void:
	for surface in source.get_surface_count():
		var tool := SurfaceTool.new()
		tool.append_from(source, surface, xf)
		tool.commit(target)
		var chosen := material if material != null else _jungle_cover(source.surface_get_material(surface))
		target.surface_set_material(target.get_surface_count() - 1, chosen)


func _jungle_cover(original: Material) -> Material:
	var base_mat := original as BaseMaterial3D
	var texture: Texture2D = base_mat.albedo_texture if base_mat != null else null
	if _cover_by_texture.has(texture):
		return _cover_by_texture[texture]
	var cover := ShaderMaterial.new()
	cover.shader = load(COVER_SHADER)
	cover.set_shader_parameter("base_texture", texture)
	_cover_by_texture[texture] = cover
	return cover


func _create(item_name: String, mesh: Mesh, mesh_transform: Transform3D, shapes: Array) -> void:
	_out.create_item(_next_id)
	_out.set_item_name(_next_id, item_name)
	_out.set_item_mesh(_next_id, mesh)
	_out.set_item_mesh_transform(_next_id, mesh_transform)
	_out.set_item_mesh_cast_shadow(_next_id, RenderingServer.SHADOW_CASTING_SETTING_ON)
	_out.set_item_shapes(_next_id, shapes)
	_next_id += 1
