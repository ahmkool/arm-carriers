extends SceneTree
## Renders every WeaponCatalog weapon to a transparent PNG icon for the level select.
## Needs a window, so don't use --headless:
##   ~/Downloads/Godot_4_5.app/Contents/MacOS/Godot --path . --script tools/weapons/render_weapon_icons.gd
## Writes assets/sprites/ui/icons/weapons/<weapon id>.png. Gameplay scripts are stripped before the
## weapon enters the tree, because autoloads are missing in --script mode.

const CATALOG := preload("res://src/autoload/weapon_catalog.gd")
const OUT_DIR := "res://assets/sprites/ui/icons/weapons"
const ICON_SIZE := Vector2i(256, 256)
const FRAMES_BEFORE_CAPTURE := 10
## Of the weapon's bounding-box diagonal: the view is diagonal, so less than 1 still fits it.
const FRAMING_MARGIN := 0.8
## Seen mostly from above, like the game camera, and turned so the carry axis (Z) runs diagonally.
const VIEW_DIRECTION := Vector3(0.55, 1.0, 0.25)
## Helper meshes that are not part of the weapon's look.
const HIDDEN_WORDS: PackedStringArray = ["Aim", "Guide", "Ring", "Debug", "Hit", "Collision", "Marker"]


func _init() -> void:
	_render_all.call_deferred()


func _render_all() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for weapon in CATALOG.WEAPONS:
		await _render(weapon)
	quit()


func _render(weapon: Dictionary) -> void:
	var viewport := _make_viewport()
	var model: Node3D = (load(weapon["scene"]) as PackedScene).instantiate()
	_strip_scripts(model)
	_freeze(model)
	viewport.add_child(model)
	var bounds := _visible_mesh_bounds(model)
	viewport.add_child(_make_camera(bounds))
	_add_lighting(viewport)
	for frame in FRAMES_BEFORE_CAPTURE:
		await process_frame
	var path := "%s/%s.png" % [OUT_DIR, weapon["id"]]
	viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	print("Saved ", path)
	viewport.queue_free()
	await process_frame


func _make_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = ICON_SIZE
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


func _strip_scripts(node: Node) -> void:
	node.set_script(null)
	for child in node.get_children():
		_strip_scripts(child)


func _freeze(model: Node3D) -> void:
	var body := model as RigidBody3D
	if body == null:
		return
	body.freeze = true


func _visible_mesh_bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if _is_helper(mesh):
			mesh.visible = false
			continue
		if not mesh.is_visible_in_tree():
			continue
		var mesh_bounds := mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(mesh_bounds) if found else mesh_bounds
		found = true
	return bounds


func _is_helper(mesh: MeshInstance3D) -> bool:
	for word in HIDDEN_WORDS:
		if mesh.name.contains(word):
			return true
	return false


func _make_camera(bounds: AABB) -> Camera3D:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = bounds.size.length() * FRAMING_MARGIN
	var center := bounds.get_center()
	camera.position = center + VIEW_DIRECTION.normalized() * (bounds.size.length() + 5.0)
	camera.far = (bounds.size.length() + 5.0) * 3.0
	camera.look_at_from_position(camera.position, center, Vector3.UP)
	return camera


func _add_lighting(viewport: SubViewport) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 50, 0)
	sun.light_energy = 1.3
	viewport.add_child(sun)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.75
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
