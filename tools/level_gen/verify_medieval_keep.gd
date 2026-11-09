extends Node
## Test driver for the medieval reskins (world_local_02_medieval.tscn, world_local_level_2_medieval.tscn).
## Run through godot.sh, see docs/level-creation-for-agents.md. It also runs on the originals, for before/after shots.
## Checks that a reskin left gameplay alone: every node of the original is still there with the same transform,
## collision shapes, layers and script; floor and decoration cells, tile collision and the navmesh match. Only the
## weapon may differ. Then checks that the new decoration has no collision and doesn't hide the carriers, and
## photographs each area from the follow camera and from above.
## Save tracking is disabled, so save.json stays untouched.

const SUFFIX := "_medieval"
const DECORATION := "Level/Medieval"
## Nodes a reskin may change: the weapon can be swapped, and the sun moves.
const MAY_DIFFER: Array[String] = ["Weapon", "DirectionalLight3D"]
const GRIDMAPS: Array[String] = ["Level/NavigationRegion3D/FloorGridMap", "Level/NavigationRegion3D/GridMapFloor", "Level/GridMap", "Level/Decoration"]
## Per level: carrier spots (shooter, setter) to photograph from the follow camera.
const VIEWS := {
	"world_local_02": {
		"spawn": [Vector3(-2.0, 0.0, 8.0), Vector3(2.0, 0.0, 8.0)],
		"courtyard_north": [Vector3(-2.0, 0.0, -4.0), Vector3(2.0, 0.0, -4.0)],
		"causeway": [Vector3(-24.0, 0.0, 7.5), Vector3(-20.0, 0.0, 7.5)],
		"bailey": [Vector3(-39.0, 0.0, -6.0), Vector3(-35.0, 0.0, -6.0)],
		"bailey_corner": [Vector3(-45.0, 0.0, -11.0), Vector3(-41.0, 0.0, -11.0)],
		"courtyard_south": [Vector3(-2.0, 0.0, 15.5), Vector3(2.0, 0.0, 15.5)],
	},
	"world_local_level_2": {
		"start": [Vector3(0.0, 0.0, 5.0), Vector3(0.0, 0.0, 1.0)],
		"walkway_pair": [Vector3(-1.5, 0.0, -16.5), Vector3(-7.5, 0.0, -16.5)],
		"island_2": [Vector3(-8.0, 0.0, -36.0), Vector3(-8.0, 0.0, -40.0)],
		"long_walkway": [Vector3(-10.5, 0.0, -82.5), Vector3(-14.5, 0.0, -82.5)],
		"pillars_west": [Vector3(4.0, 0.0, -96.0), Vector3(4.0, 0.0, -100.0)],
		"parallel_planks": [Vector3(70.0, 0.0, -127.5), Vector3(70.0, 0.0, -133.5)],
		"lanes_pillars": [Vector3(97.5, 0.0, -152.0), Vector3(91.5, 0.0, -152.0)],
		"lanes_2": [Vector3(97.5, 0.0, -200.0), Vector3(91.5, 0.0, -200.0)],
		# The finish island is inside the end area, which completes the level, so stop at the checkpoint before it.
		"checkpoint_7": [Vector3(95.0, 0.0, -176.0), Vector3(95.0, 0.0, -180.0)],
	},
}
## Per level: where to stand while the first bridge rises.
const BRIDGE_VIEWS := {
	"world_local_level_2": [Vector3(-8.0, 0.0, -38.0), Vector3(-8.0, 0.0, -42.0)],
}
## Per level: overhead camera (centre, ortho size, yaw) and a perspective vista (position, target).
const OVERHEAD := {
	"world_local_02": [Vector3(-18, 150, -2), 95.0, 0.0, Vector3(-18, 40, 55), Vector3(-18, 0, -5)],
	"world_local_level_2": [Vector3(36, 200, -118), 150.0, 90.0, Vector3(150, 70, -60), Vector3(40, 0, -130)],
}

var out_dir: String
var prefix: String
var original_key: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	prefix = world.scene_file_path.get_file().get_basename()
	original_key = prefix.trim_suffix(SUFFIX)
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(300.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  [" + detail + "]"))
	if not ok:
		fails += 1


func state() -> String:
	if not is_instance_valid(gsm) or gsm.current == null:
		return ""
	return String(gsm.current.name).to_lower()


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func wait_until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func shot(file_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png(out_dir + "/" + prefix + "_" + file_name)


func players() -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func protect_players() -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)


func place(a: Vector3, b: Vector3) -> void:
	var list := players()
	list[0].velocity = Vector3.ZERO
	list[1].velocity = Vector3.ZERO
	list[0].global_position = a
	list[1].global_position = b


## Teleporting into a live fight can end in a game over, which reloads the whole scene. Rebind to the new
## scene, then place the carriers again. Bridge events can also hold the game in a camera cutscene state.
func place_and_settle(a: Vector3, b: Vector3) -> void:
	for attempt in 3:
		await _rebind()
		await wait_until(func(): return state() == "playing", 15.0)
		protect_players()
		place(a + Vector3.UP, b + Vector3.UP)
		await wait(1.8)
		if is_instance_valid(world) and _carriers_near(a, b):
			return
		print("INFO settle attempt ", attempt, " at ", a, " state=", state() if is_instance_valid(gsm) else "reloaded")
	print("INFO could not settle at ", a)


func _carriers_near(a: Vector3, b: Vector3) -> bool:
	var list := players()
	return list[0].global_position.distance_to(a) < 3.0 and list[1].global_position.distance_to(b) < 3.0


func _rebind() -> void:
	await wait_until(func(): return get_tree().current_scene is WorldLocal and get_tree().current_scene.is_node_ready(), 15.0)
	if get_tree().current_scene == world:
		return
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	await wait(0.5)


# ---------------------------------------------------------------- gameplay parity

func check_gameplay_matches_original() -> void:
	if original_key == prefix:
		return
	# Compare freshly loaded copies: in the running level, the weapon and players have already moved.
	var dir := world.scene_file_path.get_base_dir()
	var original := (load(dir + "/" + original_key + ".tscn") as PackedScene).instantiate()
	var current := (load(world.scene_file_path) as PackedScene).instantiate()
	var differences: Array = []
	_compare_tree(original, original, current, differences)
	check("every original node unchanged (%d nodes)" % _count(original), differences.is_empty(), str(differences.slice(0, 8)))
	for path in GRIDMAPS:
		_check_gridmap(original, current, path)
	var nav_a := (original.get_node("Level/NavigationRegion3D") as NavigationRegion3D).navigation_mesh
	var nav_b := (current.get_node("Level/NavigationRegion3D") as NavigationRegion3D).navigation_mesh
	check("navmesh matches", nav_a.get_vertices() == nav_b.get_vertices() and nav_a.get_polygon_count() == nav_b.get_polygon_count())
	original.free()
	current.free()


func _count(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count(child)
	return total


func _compare_tree(root: Node, node: Node, current: Node, differences: Array) -> void:
	var path := String(root.get_path_to(node))
	if _may_differ(path):
		return
	var other := current.get_node_or_null(path)
	if other == null:
		differences.append("missing " + path)
		return
	var problem := _node_difference(node, other)
	if not problem.is_empty():
		differences.append(path + ": " + problem)
	for child in node.get_children():
		_compare_tree(root, child, current, differences)


func _may_differ(path: String) -> bool:
	for prefix_path in MAY_DIFFER:
		if path == prefix_path or path.begins_with(prefix_path + "/"):
			return true
	return false


func _node_difference(a: Node, b: Node) -> String:
	if a.get_class() != b.get_class():
		return "class"
	if a.get_script() != b.get_script():
		return "script"
	if a is Node3D and not (a as Node3D).transform.is_equal_approx((b as Node3D).transform):
		return "transform"
	if a is CollisionObject3D and _layers(a) != _layers(b):
		return "collision layers"
	if a is CollisionShape3D and not _same_shape((a as CollisionShape3D).shape, (b as CollisionShape3D).shape):
		return "shape"
	if a is CollisionShape3D and (a as CollisionShape3D).disabled != (b as CollisionShape3D).disabled:
		return "shape disabled"
	return ""


func _layers(node: CollisionObject3D) -> Vector2i:
	return Vector2i(node.collision_layer, node.collision_mask)


func _same_shape(a: Shape3D, b: Shape3D) -> bool:
	if a == null or b == null:
		return a == b
	if a.get_class() != b.get_class():
		return false
	if a is ConcavePolygonShape3D:
		return (a as ConcavePolygonShape3D).get_faces() == (b as ConcavePolygonShape3D).get_faces()
	if a is BoxShape3D:
		return (a as BoxShape3D).size == (b as BoxShape3D).size
	return a.get_debug_mesh().get_faces() == b.get_debug_mesh().get_faces()


func _cells(grid: GridMap) -> Dictionary:
	var cells := {}
	for cell in grid.get_used_cells():
		cells[cell] = [grid.get_cell_item(cell), grid.get_cell_item_orientation(cell)]
	return cells


func _check_gridmap(original: Node, current: Node, path: String) -> void:
	var grid_a := original.get_node_or_null(path) as GridMap
	if grid_a == null:
		return
	var grid_b := current.get_node(path) as GridMap
	check(path + ": cells match", _cells(grid_a) == _cells(grid_b))
	check(path + ": cell size and layers match", grid_a.cell_size == grid_b.cell_size and grid_a.collision_layer == grid_b.collision_layer and grid_a.collision_mask == grid_b.collision_mask)
	var mismatched: Array = []
	var items := {}
	for cell in grid_a.get_used_cells():
		items[grid_a.get_cell_item(cell)] = true
	for item in items:
		if _item_shapes_differ(grid_a.mesh_library, grid_b.mesh_library, item):
			mismatched.append(item)
	check(path + ": every used tile has the same collision and presence", mismatched.is_empty(), str(mismatched))


func _item_shapes_differ(lib_a: MeshLibrary, lib_b: MeshLibrary, item: int) -> bool:
	var in_a := item in lib_a.get_item_list()
	var in_b := item in lib_b.get_item_list()
	if in_a != in_b:
		return true
	if not in_a:
		return false
	var shapes_a := lib_a.get_item_shapes(item)
	var shapes_b := lib_b.get_item_shapes(item)
	if shapes_a.size() != shapes_b.size():
		return true
	for index in range(0, shapes_a.size(), 2):
		if not _same_shape(shapes_a[index], shapes_b[index]):
			return true
		if shapes_a[index + 1] != shapes_b[index + 1]:
			return true
	return false


# ---------------------------------------------------------------- decoration

func check_decoration_has_no_collision() -> void:
	var decoration := world.get_node_or_null(DECORATION)
	if decoration == null:
		return
	var solids: Array = []
	_collect_solids(decoration, solids)
	check("decoration has no collision", solids.is_empty(), str(solids.slice(0, 8)))


func _collect_solids(node: Node, solids: Array) -> void:
	if node is CollisionObject3D or node is CSGShape3D:
		solids.append(node.name)
	if node is GridMap and (node as GridMap).collision_layer != 0:
		solids.append(node.name)
	for child in node.get_children():
		_collect_solids(child, solids)


func check_players_on_screen(label: String) -> void:
	var camera := get_viewport().get_camera_3d()
	var rect := get_viewport().get_visible_rect()
	var seen := 0
	for p in players():
		var head: Vector3 = p.global_position + Vector3(0, 1.2, 0)
		if camera.is_position_behind(head):
			continue
		if rect.has_point(camera.unproject_position(head)):
			seen += 1
	check(label + ": both carriers on screen", seen == 2, str(seen))


func check_players_not_hidden(label: String) -> void:
	var camera := get_viewport().get_camera_3d()
	var blocked: Array = []
	for p in players():
		var head: Vector3 = p.global_position + Vector3(0, 1.2, 0)
		var blocker := _decoration_between(camera.global_position, head)
		if not blocker.is_empty():
			blocked.append(blocker)
	check(label + ": no decoration between camera and carriers", blocked.is_empty(), str(blocked))


## Decoration has no collision, so test its meshes' bounding boxes against the camera ray instead.
## Those are loose around round or rotated meshes, so this can report a blocker that isn't really in the way.
func _decoration_between(from: Vector3, to: Vector3) -> String:
	var decoration := world.get_node_or_null(DECORATION)
	if decoration == null:
		return ""
	for mesh in decoration.find_children("*", "MeshInstance3D", true, false):
		if _mesh_blocks_ray(mesh, from, to):
			return String(decoration.get_path_to(mesh))
	return ""


func _mesh_blocks_ray(mesh: MeshInstance3D, from: Vector3, to: Vector3) -> bool:
	if not mesh.is_visible_in_tree():
		return false
	var box := mesh.global_transform * mesh.get_aabb()
	return box.intersects_segment(from, to) != null


## Raises the first bridge through its own event and photographs it, to see a reskinned bridge in place.
func check_bridge_raised() -> void:
	var event := world.get_node_or_null("Level/Events/OpenBridge1")
	if event == null or not BRIDGE_VIEWS.has(original_key):
		return
	var spots: Array = BRIDGE_VIEWS[original_key]
	await place_and_settle(spots[0], spots[1])
	event.trigger()
	await wait(4.5)
	var bridge := world.get_node("Level/Bridges/BridgePlatform").get_node("AnimatableBody3D") as Node3D
	check("first bridge raised", bridge.global_position.y > -1.5, str(bridge.global_position.y))
	await shot("bridge_raised.png")


func overhead() -> void:
	if not OVERHEAD.has(original_key):
		return
	var setup: Array = OVERHEAD[original_key]
	var follow_cam := get_viewport().get_camera_3d()
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = setup[1]
	top.far = 600.0
	world.add_child(top)
	top.global_position = setup[0]
	top.rotation_degrees = Vector3(-90, setup[2], 0)
	top.make_current()
	var ui := world.get_node("UI") as CanvasLayer
	ui.visible = false
	await shot("overhead.png")
	top.projection = Camera3D.PROJECTION_PERSPECTIVE
	top.fov = 60.0
	top.look_at_from_position(setup[3], setup[4])
	await shot("vista.png")
	ui.visible = true
	follow_cam.make_current()
	top.queue_free()


func _run() -> void:
	print("INFO scene ", world.scene_file_path)
	await wait_until(func(): return state() == "playing", 20.0)
	check("level reaches playing", state() == "playing", state())
	check_gameplay_matches_original()
	check_decoration_has_no_collision()
	protect_players()
	await wait(1.5)
	var views: Dictionary = VIEWS.get(original_key, {})
	for view in views:
		var spots: Array = views[view]
		await place_and_settle(spots[0], spots[1])
		check_players_on_screen(view)
		check_players_not_hidden(view)
		await shot(view + ".png")
	await check_bridge_raised()
	await _rebind()
	await wait_until(func(): return state() == "playing", 15.0)
	await overhead()
	check("still playing", state() == "playing", state())
	print("RESULT ", "OK" if fails == 0 else "FAILED", " fails=", fails)
	get_tree().quit(0 if fails == 0 else 1)
