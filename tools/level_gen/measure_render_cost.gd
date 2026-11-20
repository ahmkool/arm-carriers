extends Node
## Prints what the renderer draws in a level, so a change to its meshes can be compared before and after:
## draw calls, objects and primitives per frame, and the number of MeshInstance3D nodes, at the spawn and,
## if CAMERA_SPOTS is set, at each listed point (world x,z pairs separated by ";").
## Run: tools/level_gen/godot.sh test tools/level_gen/measure_render_cost.gd <res://level.tscn> <out_dir> 90

const SETTLE_SEC := 2.0
## Frames averaged per spot, since the numbers jitter with particles and animated props.
const SAMPLE_FRAMES := 30

var out_dir: String
var world: WorldLocal


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	get_tree().create_timer(80.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(4.0).timeout
	print("RESULT mesh_instances=%d" % _count_mesh_instances(world))
	await _measure("spawn")
	var spots := OS.get_environment("CAMERA_SPOTS")
	var index := 0
	for spot in spots.split(";", false):
		index += 1
		var xz := spot.split(",")
		_move_players(Vector3(float(xz[0]), 0.0, float(xz[1])))
		await _measure("spot%d" % index)
	get_tree().quit(0)


func _measure(label: String) -> void:
	await get_tree().create_timer(SETTLE_SEC).timeout
	var draws := 0
	var objects := 0
	var primitives := 0
	for frame in SAMPLE_FRAMES:
		await get_tree().process_frame
		draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		objects += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		primitives += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("RESULT %s draw_calls=%d objects=%d primitives=%d" % [label, draws / SAMPLE_FRAMES, objects / SAMPLE_FRAMES, primitives / SAMPLE_FRAMES])
	get_tree().root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, label])


func _move_players(at: Vector3) -> void:
	var offset := -2.0
	for child in world.players.get_children():
		var player := child as PlayerLocal
		if player == null:
			continue
		player.velocity = Vector3.ZERO
		player.global_position = Vector3(at.x + offset, player.global_position.y, at.z)
		offset += 4.0


func _count_mesh_instances(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _count_mesh_instances(child)
	return count
