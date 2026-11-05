extends SceneTree
## Renders a character's head to a transparent PNG for the health bar. Needs a window, so don't use --headless.
## ~/Downloads/Godot_4_5.app/Contents/MacOS/Godot --path . --script tools/characters/render_icon.gd -- \
##   res://assets/models/Kaykit/characters/Knight.glb assets/sprites/ui/icons/knight_icon.png Head,Helmet

const ICON_SIZE := Vector2i(420, 420)
const FRAMES_BEFORE_CAPTURE := 10
const FRAMING_MARGIN := 1.08


func _init() -> void:
	_render.call_deferred()


func _render() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		push_error("Expected: <model res:// path> <output png> <comma-separated head mesh words>")
		quit(1)
		return
	var viewport := _make_viewport()
	var model: Node3D = (load(args[0]) as PackedScene).instantiate()
	viewport.add_child(model)
	var bounds := _show_only_matching_meshes(model, args[2].split(","))
	viewport.add_child(_make_camera(bounds))
	_add_lighting(viewport)
	for frame in FRAMES_BEFORE_CAPTURE:
		await process_frame
	viewport.get_texture().get_image().save_png(args[1])
	print("Saved ", args[1])
	quit()


func _make_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = ICON_SIZE
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


func _show_only_matching_meshes(model: Node3D, words: PackedStringArray) -> AABB:
	var bounds := AABB()
	var found := false
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		mesh.visible = _name_has_any(mesh.name, words)
		if not mesh.visible:
			continue
		var mesh_bounds := mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(mesh_bounds) if found else mesh_bounds
		found = true
	return bounds


func _name_has_any(mesh_name: String, words: PackedStringArray) -> bool:
	for word in words:
		if mesh_name.contains(word):
			return true
	return false


func _make_camera(bounds: AABB) -> Camera3D:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(bounds.size.x, bounds.size.y) * FRAMING_MARGIN
	camera.position = bounds.get_center() + Vector3(0, 0, 5)
	return camera


func _add_lighting(viewport: SubViewport) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-25, 20, 0)
	sun.light_energy = 1.4
	viewport.add_child(sun)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.7
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	viewport.add_child(world_environment)
