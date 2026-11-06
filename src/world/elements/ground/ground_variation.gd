class_name GroundVariation
extends Node
## Swaps the materials of the tiles used by the given GridMaps for the ground
## variation shader (color patches + cloud shadows). Works on a runtime copy of the
## mesh library, so the shared tile library files and other GridMaps stay untouched.

@export var grid_maps: Array[GridMap] = []
@export var material_template: ShaderMaterial = preload("res://src/world/elements/ground/ground_variation_material.tres")

var _material_cache: Dictionary = {}


func _ready() -> void:
	for grid_map in grid_maps:
		_apply_to(grid_map)


func _apply_to(grid_map: GridMap) -> void:
	if grid_map == null or grid_map.mesh_library == null:
		return
	var library := grid_map.mesh_library.duplicate() as MeshLibrary
	for item_id in _used_item_ids(grid_map):
		var mesh := library.get_item_mesh(item_id)
		if mesh == null:
			continue
		library.set_item_mesh(item_id, _with_ground_materials(mesh))
	grid_map.mesh_library = library


func _used_item_ids(grid_map: GridMap) -> Array[int]:
	var ids: Array[int] = []
	for cell in grid_map.get_used_cells():
		var item_id := grid_map.get_cell_item(cell)
		if ids.has(item_id):
			continue
		ids.append(item_id)
	return ids


func _with_ground_materials(mesh: Mesh) -> Mesh:
	var copy := mesh.duplicate() as Mesh
	for surface in copy.get_surface_count():
		var replacement := _ground_material_for(mesh.surface_get_material(surface))
		if replacement == null:
			continue
		copy.surface_set_material(surface, replacement)
	return copy


func _ground_material_for(original: Material) -> ShaderMaterial:
	var standard := original as BaseMaterial3D
	if standard == null or standard.albedo_texture == null:
		return null
	if _material_cache.has(standard):
		return _material_cache[standard]
	var material := material_template.duplicate() as ShaderMaterial
	material.set_shader_parameter("albedo_texture", standard.albedo_texture)
	material.set_shader_parameter("albedo_color", standard.albedo_color)
	material.set_shader_parameter("roughness", standard.roughness)
	_material_cache[standard] = material
	return material
