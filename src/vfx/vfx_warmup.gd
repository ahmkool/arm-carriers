extends Node

const SHARED_WARMUP_SCENES: Array[PackedScene] = [
	preload("res://src/vfx/small_explosion.tscn"),
	preload("res://src/vfx/explosion.tscn"),
	preload("res://src/vfx/enemy_damage.tscn"),
	preload("res://src/vfx/puff_disappear.tscn"),
	preload("res://src/vfx/dash_particles.tscn"),
	preload("res://src/vfx/ghost.tscn"),
	preload("res://src/vfx/dash.tscn"),
	preload("res://src/vfx/fireball_spawn.tscn"),
	preload("res://src/vfx/fireball.tscn"),
	preload("res://src/weapon/bazooka_bullet_local.tscn"),
]

const WARMUP_FRAME_COUNT := 2
const WARMUP_SPAWN_OFFSET := Vector3(0.0, -80.0, 0.0)

var _warmed_level_ids: Dictionary = {}


func needs_warmup(world: WorldLocal) -> bool:
	if world == null:
		return false
	return not _warmed_level_ids.has(world.get_level_id())


func warm_for_world(world: WorldLocal) -> void:
	if world == null:
		return
	var level_id := world.get_level_id()
	if _warmed_level_ids.has(level_id):
		return
	var scenes := _collect_scenes(world)
	for scene in scenes:
		await _warm_scene(world, scene)
	await _warm_hit_flashes(world)
	_mark_level_warmed(level_id)


func _mark_level_warmed(level_id: String) -> void:
	if level_id.is_empty():
		return
	_warmed_level_ids[level_id] = true


func _collect_scenes(world: WorldLocal) -> Array[PackedScene]:
	var result: Array[PackedScene] = []
	var seen: Dictionary = {}
	for scene in SHARED_WARMUP_SCENES:
		_add_unique_scene(result, seen, scene)
	for scene in world.vfx_warmup_scenes:
		_add_unique_scene(result, seen, scene)
	return result


func _add_unique_scene(
	target: Array[PackedScene],
	seen: Dictionary,
	scene: PackedScene,
) -> void:
	if scene == null:
		return
	var path := scene.resource_path
	if path.is_empty():
		return
	if seen.has(path):
		return
	seen[path] = true
	target.append(scene)


func _warm_scene(world: WorldLocal, scene: PackedScene) -> void:
	if scene == null:
		return
	var instance := scene.instantiate()
	if not instance is Node3D:
		instance.free()
		return
	var node := instance as Node3D
	_prepare_warmup_instance(node)
	world.add_child(node)
	node.global_position = _warm_spawn_position(world)
	_start_all_particles(node)
	await _wait_warmup_frames(world)
	if not is_instance_valid(node):
		return
	node.queue_free()


func _prepare_warmup_instance(node: Node3D) -> void:
	node.set_script(null)
	node.set_process_mode(Node.PROCESS_MODE_DISABLED)
	_pause_animations(node)
	_silence_audio(node)
	_disable_hitboxes(node)


func _pause_animations(root: Node) -> void:
	for child in root.find_children("*", "AnimationPlayer", true, false):
		var player := child as AnimationPlayer
		player.stop()
		player.set_process_mode(Node.PROCESS_MODE_DISABLED)


func _silence_audio(root: Node) -> void:
	for child in root.find_children("*", "AudioStreamPlayer3D", true, false):
		var player := child as AudioStreamPlayer3D
		player.stream = null
	for child in root.find_children("*", "AudioStreamPlayer", true, false):
		var player := child as AudioStreamPlayer
		player.stream = null


func _disable_hitboxes(root: Node) -> void:
	for child in root.find_children("*", "Area3D", true, false):
		var area := child as Area3D
		area.monitoring = false
		area.monitorable = false


func _warm_spawn_position(world: WorldLocal) -> Vector3:
	var camera := world.get_viewport().get_camera_3d()
	if camera == null:
		return world.global_position + WARMUP_SPAWN_OFFSET
	var behind := -camera.global_basis.z.normalized()
	return camera.global_position + behind * 3.0 + WARMUP_SPAWN_OFFSET


func _start_all_particles(root: Node) -> void:
	for child in root.find_children("*", "GPUParticles3D", true, false):
		var particles := child as GPUParticles3D
		particles.emitting = true
		particles.restart()
	for child in root.find_children("*", "CPUParticles3D", true, false):
		var particles := child as CPUParticles3D
		particles.emitting = true


func _wait_warmup_frames(world: WorldLocal) -> void:
	var tree := world.get_tree()
	if tree == null:
		return
	for _unused in WARMUP_FRAME_COUNT:
		await tree.process_frame


func _warm_hit_flashes(world: WorldLocal) -> void:
	await _warm_hit_flashes_for_type(world, "EnemyLocal")
	await _warm_hit_flashes_for_type(world, "PlayerLocal")


func _warm_hit_flashes_for_type(world: WorldLocal, type_name: String) -> void:
	for node in world.find_children("*", type_name, true, false):
		await _warm_actor_hit_flash(node)


func _warm_actor_hit_flash(actor: Node) -> void:
	if actor == null:
		return
	var flash := actor.get_node_or_null("HitFlash3D") as HitFlash3D
	if flash == null:
		flash = HitFlash3D.new()
		flash.name = "HitFlash3D"
		actor.add_child(flash)
	await flash.warm_render()
