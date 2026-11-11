extends Node
## Test driver for world_local_rotor_decks_2.tscn (beginning of Rotor Decks II).
## Run through godot.sh, see docs/level-creation-for-agents.md.

const CELL := 2.999
var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(120.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  [" + detail + "]"))
	if not ok:
		fails += 1


func w(cx: float, cz: float, y: float = 0.0) -> Vector3:
	return Vector3((cx + 0.5) * CELL, y, (cz + 0.5) * CELL)


func state() -> String:
	return "" if gsm.current == null else String(gsm.current.name).to_lower()


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
	get_tree().root.get_texture().get_image().save_png(out_dir + "/" + file_name)


func players() -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func place(a: Vector3, b: Vector3) -> void:
	var list := players()
	list[0].velocity = Vector3.ZERO
	list[1].velocity = Vector3.ZERO
	list[0].global_position = a
	list[1].global_position = b


func group_enemies(path: String) -> Array:
	return world.get_node(path).get_node("InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func visible_count(nodes: Array) -> int:
	var cam := get_viewport().get_camera_3d()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var seen := 0
	for n in nodes:
		var pos: Vector3 = n.global_position + Vector3(0, 1, 0)
		if not cam.is_position_behind(pos) and rect.has_point(cam.unproject_position(pos)):
			seen += 1
	return seen


func focal_count() -> int:
	return (world.get_node("CameraFollowRig") as CameraFollowRig)._extra_focal_nodes.size()


func cp() -> String:
	return String(world.checkpoint_manager.current_checkpoint.name)


func path_ok(from: Vector3, to: Vector3, should: bool, label: String) -> void:
	var map := world.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	var reached := path.size() > 0 and path[path.size() - 1].distance_to(NavigationServer3D.map_get_closest_point(map, to)) < 0.6
	check(label, reached == should, "points=%d" % path.size())


func overhead() -> void:
	var follow_cam := get_viewport().get_camera_3d()
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 65.0
	top.far = 300.0
	top.position = Vector3(1.5, 100, 1.5)
	top.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(top)
	top.make_current()
	var ui := world.get_node("UI") as CanvasLayer
	ui.visible = false
	await shot("rotor_decks_2_overhead.png")
	ui.visible = true
	follow_cam.make_current()
	top.queue_free()


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.5)
	await shot("rotor_decks_2_start.png")
	await overhead()

	var list := players()
	var carry: CarryInfo = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info()
	check("both players carry the bazooka", is_instance_valid(carry.main_carrier) and is_instance_valid(carry.secondary_carrier) and world.get_active_weapon().name == "Bazooka")
	check("players stand on grass sky island", FootstepSurface.of_node(world.get_node("Level/NavigationRegion3D/GridMapFloor")) == FootstepSurface.GRASS and list.all(func(p): return p.is_on_floor()))
	check("rotor decks have wood surface", FootstepSurface.of_node(world.get_node("Level/NavigationRegion3D/GridMapDecks")) == FootstepSurface.WOOD)

	path_ok(w(-2, -2), w(2, 2), true, "nav: grass sky island is navigable")
	path_ok(w(-7, -1), w(-6, 1), true, "nav: left rotor deck is navigable")
	path_ok(w(6, -1), w(7, 1), true, "nav: right rotor deck is navigable")
	path_ok(w(0, 0), w(-7, 0), false, "nav: left rotor deck is separate from grass island")
	path_ok(w(0, 0), w(7, 0), false, "nav: right rotor deck is separate from grass island")

	var aviators := group_enemies("Enemies/EnemyGroup")
	var left_aviators := aviators.filter(func(e): return e.global_position.x < -12.0)
	var right_aviators := aviators.filter(func(e): return e.global_position.x > 15.0)
	check("6 aviator enemies alive (3 left, 3 right)", aviators.size() == 6 and left_aviators.size() == 3 and right_aviators.size() == 3, "total=%d left=%d right=%d" % [aviators.size(), left_aviators.size(), right_aviators.size()])
	check("all 6 aviator enemies are inoffensive", aviators.all(func(e): return not e.is_offensive))
	check("all 6 aviator enemies stand on rotor decks", aviators.all(func(e): return e.is_on_floor() and e.global_position.y > -1.3))
	check("all 6 aviator enemies have AvianSwordsman mesh and Sword", aviators.all(func(e): return e.has_node("AvianSwordsman/Rig_Medium/Skeleton3D/SwordHand/Sword")))

	check("camera frames both players and all 6 aviators at start", visible_count(list) == 2 and visible_count(aviators) == 6, "players=%d/2 aviators=%d/6 focal=%d" % [visible_count(list), visible_count(aviators), focal_count()])

	# Fire real bazooka rocket at left rotor deck trio, then right rotor deck trio.
	var specifics := world.get_active_weapon().get_node("WeaponSpecifics")
	place(w(-1, 0), w(1, 0))
	await wait(0.6)
	if specifics.muzzle.global_transform.basis.z.x > 0.0:
		place(w(1, 0), w(-1, 0))
		await wait(0.6)
	specifics._request_fire_bullet()
	var hit_left: bool = await wait_until(func(): return group_enemies("Enemies/EnemyGroup").size() < 6, 8.0)
	await shot("rotor_decks_2_left_shot.png")
	check("real bazooka rocket hits left rotor deck aviators", hit_left, "remaining=%d" % group_enemies("Enemies/EnemyGroup").size())

	for e in group_enemies("Enemies/EnemyGroup"):
		Health.apply_damage(e, 9999, e.global_position)
	await wait(1.0)
	await shot("rotor_decks_2_cleared.png")
	check("clearing all 6 aviators triggers Checkpoint2", cp() == "Checkpoint2", cp())
	check("clearing all 6 aviators clears camera focal points", focal_count() == 0, str(focal_count()))

	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
