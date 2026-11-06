extends SceneTree
## Builds src/world/elements/snow/snow_tiles.tres from the hill tiles of tiles_Color1:
## - snow ground (the shapes build_floor uses), and an "Ice_" copy of each, which IceFloor makes slippery;
## - props: a snowy tree or boulder standing on a snow plate, with box collision, so the navmesh bakes around them;
## - scenery: the same trees and rocks with no plate and no collision.
##   godot --headless --path . --script tools/level_gen/build_snow_tiles.gd
## assets/mesh_library/ is git-ignored, so the result lives next to the rest of the snow art.

const SOURCE := "res://assets/mesh_library/tiles_Color1_no_shadows.tres"
const OUT := "res://src/world/elements/snow/snow_tiles.tres"
const GROUND := [
	"Hill_Top_E_Center", "Hill_Top_F_Side", "Hill_Top_H_Side", "Hill_Top_G_OuterCorner", "Hill_Top_G_InnerCorner",
	"Hill_Cliff_Tall_H_Side", "Hill_Cliff_Tall_I_OuterCorner", "Hill_Cliff_Tall_I_InnerCorner",
]
## Prop name: [source item, collision box size (x, y, z), or Vector3.ZERO for the item's own bounds, shrunk].
const PROPS := {
	"PineA": ["Tree_4_A", Vector3(1.0, 4.0, 1.0)],
	"PineB": ["Tree_5_A", Vector3(1.0, 4.0, 1.0)],
	"BareTree": ["Tree_Bare_1_A", Vector3(0.9, 4.0, 0.9)],
	"Boulder": ["Rock_3_A", Vector3.ZERO],
	"BoulderB": ["Rock_5_A", Vector3.ZERO],
}
const SCENERY := {"IslePine": "Tree_4_A", "IslePineB": "Tree_5_A", "IsleBareTree": "Tree_Bare_1_A", "IsleRock": "Rock_3_A"}
const PROP_SCALE := 1.2
const BOULDER_SHRINK := 0.8
## A cell at GridMap layer -1 is centred 1 m below the deck, so the plate's top is at local +0.01.
const PLATE_TOP := 0.01

var _source: MeshLibrary
var _out := MeshLibrary.new()
var _next_id := 0
var _snow := ShaderMaterial.new()
var _ice := ShaderMaterial.new()
var _cover_by_texture := {}


func _initialize() -> void:
	_source = load(SOURCE) as MeshLibrary
	_snow.shader = load("res://src/world/elements/snow/snow_ground.gdshader")
	_ice.shader = load("res://src/world/elements/snow/ice_ground.gdshader")
	for name in GROUND:
		_add_ground(name, name, _snow)
	for name in GROUND:
		_add_ground("Ice_" + name, name, _ice)
	for prop in PROPS:
		_add_prop(prop, PROPS[prop][0], PROPS[prop][1])
	for scenery in SCENERY:
		_add_scenery(scenery, SCENERY[scenery])
	var error := ResourceSaver.save(_out, OUT)
	print("SAVED items=", _next_id, " error=", error)
	quit(error)


func _source_id(name: String) -> int:
	var id := _source.find_item_by_name(name + "_Color1")
	assert(id >= 0, "missing tile " + name)
	return id


func _add_ground(out_name: String, source_name: String, material: Material) -> void:
	var id := _source_id(source_name)
	var mesh := _source.get_item_mesh(id).duplicate() as ArrayMesh
	for surface in mesh.get_surface_count():
		mesh.surface_set_material(surface, material)
	_create(out_name, mesh, _source.get_item_mesh_transform(id), _source.get_item_shapes(id))


func _add_prop(out_name: String, source_name: String, box: Vector3) -> void:
	var plate_id := _source_id("Hill_Top_E_Center")
	var prop_id := _source_id(source_name)
	var placed := Transform3D(Basis.from_scale(Vector3.ONE * PROP_SCALE), Vector3(0, PLATE_TOP, 0))
	var mesh := ArrayMesh.new()
	_append(mesh, _source.get_item_mesh(plate_id), _source.get_item_mesh_transform(plate_id), _snow)
	_append(mesh, _source.get_item_mesh(prop_id), placed * _source.get_item_mesh_transform(prop_id), null)
	var shapes := _source.get_item_shapes(plate_id).duplicate()
	var bounds := placed * (_source.get_item_mesh_transform(prop_id) * _source.get_item_mesh(prop_id).get_aabb())
	var size := box if box != Vector3.ZERO else bounds.size * BOULDER_SHRINK
	var shape := BoxShape3D.new()
	shape.size = size
	shapes.append(shape)
	shapes.append(Transform3D(Basis(), Vector3(bounds.get_center().x, PLATE_TOP + size.y * 0.5, bounds.get_center().z)))
	_create(out_name, mesh, Transform3D(), shapes)


func _add_scenery(out_name: String, source_name: String) -> void:
	var id := _source_id(source_name)
	var mesh := ArrayMesh.new()
	_append(mesh, _source.get_item_mesh(id), Transform3D(Basis.from_scale(Vector3.ONE * PROP_SCALE)) * _source.get_item_mesh_transform(id), null)
	_create(out_name, mesh, Transform3D(), [])


## Copies every surface of `source` into `target`, moved by `xf`. A null material means snow over the original texture.
func _append(target: ArrayMesh, source: Mesh, xf: Transform3D, material: Material) -> void:
	for surface in source.get_surface_count():
		var tool := SurfaceTool.new()
		tool.append_from(source, surface, xf)
		tool.commit(target)
		var chosen := material if material != null else _snow_cover(source.surface_get_material(surface))
		target.surface_set_material(target.get_surface_count() - 1, chosen)


func _snow_cover(original: Material) -> Material:
	var texture: Texture2D = original.albedo_texture if original is BaseMaterial3D else null
	if _cover_by_texture.has(texture):
		return _cover_by_texture[texture]
	var cover := ShaderMaterial.new()
	cover.shader = load("res://src/world/elements/snow/snow_cover.gdshader")
	cover.set_shader_parameter("base_texture", texture)
	_cover_by_texture[texture] = cover
	return cover


func _create(name: String, mesh: Mesh, mesh_transform: Transform3D, shapes: Array) -> void:
	_out.create_item(_next_id)
	_out.set_item_name(_next_id, name)
	_out.set_item_mesh(_next_id, mesh)
	_out.set_item_mesh_transform(_next_id, mesh_transform)
	_out.set_item_mesh_cast_shadow(_next_id, RenderingServer.SHADOW_CASTING_SETTING_ON)
	_out.set_item_shapes(_next_id, shapes)
	_next_id += 1
