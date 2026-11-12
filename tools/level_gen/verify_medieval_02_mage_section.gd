extends Node
## Test driver for the mage-turret arena at the start of world_local_02_medieval.tscn
## (built by add_medieval_02_mage_section.py). Run through godot.sh, see docs/level-creation-for-agents.md.
## Checks the spawn, that the nine mages stand on their turrets and everything shows on screen, that the sword
## really reaches each side's mages from the island's edge (real input and a real dash), what clearing them
## does (checkpoint, bridge, camera), and that deaths respawn the right way. Save tracking is disabled.

const CELL := 2.999
const ARENA_X := Vector2i(-6, -1)
const ARENA_Z := Vector2i(10, 14)
const GROUP := "Enemies/MageTurretGroup"

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
	get_tree().create_timer(280.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  [" + detail + "]"))
	if not ok:
		fails += 1


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


func protect_players() -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)


## `front` is where the setter stands (the end the blade points past), `back` the shooter.
func place(front: Vector3, back: Vector3) -> void:
	# The blade points from the shooter (player 0) through the direction setter (player 1), so the setter leads.
	var list := players()
	list[0].velocity = Vector3.ZERO
	list[1].velocity = Vector3.ZERO
	list[0].global_position = back
	list[1].global_position = front


func mages() -> Array:
	return world.get_node(GROUP).get_node("InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal)


## Enemies are re-created with generated names after a reset, so sort them by where they stand.
func side_of(mage: Node3D) -> String:
	var e := arena_edges()
	if mage.global_position.z < e.north:
		return "North"
	if mage.global_position.x < e.west:
		return "West"
	if mage.global_position.x > e.east:
		return "East"
	return "North"


func living_mages() -> Array:
	return mages().filter(func(m): return m.is_alive())


func cp() -> String:
	return String(world.checkpoint_manager.current_checkpoint.name)


func focal_count() -> int:
	return (world.get_node("CameraFollowRig") as CameraFollowRig)._extra_focal_nodes.size()


func bridge_y(index: int) -> float:
	return (world.get_node("Level/Bridges/MageBridgePlatform%d/AnimatableBody3D" % index) as Node3D).global_position.y


func arena_edges() -> Dictionary:
	return {
		"west": ARENA_X.x * CELL, "east": (ARENA_X.y + 1) * CELL,
		"north": ARENA_Z.x * CELL, "south": (ARENA_Z.y + 1) * CELL,
	}


## Floor top under (x, z), from a ray on the level layer, or NAN.
func floor_y(x: float, z: float, from_y: float = 6.0) -> float:
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, from_y, z), Vector3(x, -12.0, z), 4)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	return NAN if hit.is_empty() else hit.position.y


func visible_count(nodes: Array, lift: float = 1.0) -> int:
	var cam := get_viewport().get_camera_3d()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow(-6.0)
	var seen := 0
	for n in nodes:
		var pos: Vector3 = n.global_position + Vector3(0, lift, 0)
		if not cam.is_position_behind(pos) and rect.has_point(cam.unproject_position(pos)):
			seen += 1
	return seen


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame


func is_dead(mage: Node) -> bool:
	return not is_instance_valid(mage) or not (mage as EnemyLocal).is_alive()


## One real swing: both carriers press `action_name`, then dash. The blade only hurts what it sweeps across,
## so this is a sideways dash across the line the blade points along.
func strike(action_name: String) -> void:
	var list := players()
	var acts: Array = [list[0].get(action_name), list[1].get(action_name)]
	for a in acts:
		Input.action_press(a)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_press(list[0].action_dash)
	Input.action_press(list[1].action_dash)
	await wait(0.2)
	Input.action_release(list[0].action_dash)
	Input.action_release(list[1].action_dash)
	for a in acts:
		Input.action_release(a)
	await wait(0.5)


## Puts the pair `inset` metres inside the island's edge with the blade pointing at the mage's side of the moat, but
## `lateral` metres to one side of it, then dashes sideways so the blade sweeps across the mage. Returns true if the
## mage dies. The direction setter leads and the blade points past it. A dash straight at the moat would drop
## the carriers in, so this is the swing the level is built for.
func reach_test(mage: EnemyLocal, side: String, inset: float, lateral: float = 2.4) -> bool:
	var e := arena_edges()
	var m: Vector3 = mage.global_position
	var front: Vector3
	var back: Vector3
	var action_name := "action_up"
	match side:
		"West":
			front = Vector3(e.west + inset, 0.0, m.z + lateral)
			back = front + Vector3(2.6, 0, 0)
		"East":
			front = Vector3(e.east - inset, 0.0, m.z + lateral)
			back = front - Vector3(2.6, 0, 0)
		_:
			front = Vector3(m.x + lateral, 0.0, e.north + inset)
			back = front + Vector3(0, 0, 2.6)
			action_name = "action_left"
	place(front + Vector3.UP, back + Vector3.UP)
	await wait(0.8)
	await strike(action_name)
	return is_dead(mage)


## Walks both carriers north over the exit bridge until the turret mages appear, then waits out their spawn-in.
## True when all nine appeared, the arena is framed, and both carriers stand on it.
func walk_into_arena() -> bool:
	var e := arena_edges()
	for p in players():
		Input.action_press(p.action_up)
	var woke := await wait_until(func(): return living_mages().size() == 9 and focal_count() == 4, 10.0)
	for p in players():
		Input.action_release(p.action_up)
	await wait(2.5)
	return woke and players().all(func(p): return p.global_position.z > e.north and p.global_position.z < e.south and absf(p.global_position.y + 1.0) < 0.5)


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	# The level now opens with the labyrinth (verify_medieval_02_labyrinth.gd): respawn at the arena instead.
	if cp() != "CheckpointStart":
		world.checkpoint_manager.set_current_checkpoint(world.get_node("CheckpointManager/CheckpointStart"))
		gsm.transition_to("resettingcheckpoint")
		await wait_until(func(): return state() == "playing", 20.0)
	await wait(2.0)
	protect_players()
	var e := arena_edges()

	# ---- Spawn: on the labyrinth's exit island, with no turret mages until both carriers walk onto the arena. ----
	check("the arena section starts at CheckpointStart", cp() == "CheckpointStart", cp())
	check("CheckpointStart is on the exit island, before the bridge", players().all(func(p): return p.global_position.z > e.south), str(players().map(func(p): return p.global_position)))
	check("no turret mage before the carriers arrive", living_mages().is_empty() and focal_count() == 0, "%d alive, %d focal" % [living_mages().size(), focal_count()])
	check("real input: over the bridge onto the arena wakes the mages", await walk_into_arena())
	var list := players()
	var on_floor := list.all(func(p): return p.global_position.x > e.west and p.global_position.x < e.east and p.global_position.z > e.north and p.global_position.z < e.south and absf(p.global_position.y - -1.0) < 0.5)
	check("both carriers stand on the arena", on_floor, "%s %s" % [list[0].global_position, list[1].global_position])
	check("the bridge is down", bridge_y(1) < -4.0 and bridge_y(4) < -4.0, "y=%.2f" % bridge_y(1))
	check("the camera is framed on the arena", focal_count() == 4, str(focal_count()))
	var all := mages()
	check("nine mages", all.size() == 9 and living_mages().size() == 9, str(all.size()))
	var by_side := {"West": [], "North": [], "East": []}
	for m in all:
		by_side[side_of(m)].append(m)
	var sides := {"West": by_side.West.size(), "North": by_side.North.size(), "East": by_side.East.size()}
	check("three on each side", sides.West == 3 and sides.North == 3 and sides.East == 3, str(sides))
	var stand_heights := all.map(func(m): return snappedf(m.global_position.y, 0.01))
	check("mages stand on their turrets", all.all(func(m): return m.is_on_floor() and m.global_position.y > -1.0 and m.global_position.y < -0.5), str(stand_heights))
	var cast_ok := all.all(func(m): return m.get_node("MageBehavior").mobility == 1)
	check("mages are stationary", cast_ok)
	var fall := world.get_node("Level/FallArea/CollisionShape3D") as CollisionShape3D
	var half_z: float = (fall.shape as BoxShape3D).size.z * 0.5
	check("the fall area covers the arena", fall.global_position.z - half_z < e.north - 8.0 and fall.global_position.z + half_z > e.south + 8.0)
	await shot("01_spawn.png")
	check("camera: both carriers and all nine mages on screen at spawn", visible_count(list, 0.0) == 2 and visible_count(all) == 9,
		"players %d/2, mages %d/9, camera y=%.1f" % [visible_count(list, 0.0), visible_count(all), get_viewport().get_camera_3d().global_position.y])

	# ---- The sword reaches from the edge. ----
	for side in ["West", "East", "North"]:
		var group: Array = by_side[side]
		for i in group.size():
			var mage: EnemyLocal = group[i]
			if is_dead(mage):
				continue
			await wait_until(func(): return not mage.enemy_state_machine.is_in_state("spawning"), 5.0)
			var hit := false
			var scan: Array = [3.0, 2.0, 1.0] if i == 0 else [1.0]
			var reached_from := -1.0
			for inset in scan:
				hit = await reach_test(mage, side, inset)
				if hit:
					reached_from = inset
					break
			if i == 0:
				print("INFO %s: the first mage dies to a dash from %.1f m inside the edge (tried 3, 2, 1)" % [side, reached_from])
			check("a real sideways dash from at most %.0f m inside the edge kills the %s mage %d" % [scan[0], side.to_lower(), i + 1], hit)
			if i == 0:
				await shot("02_strike_%s.png" % side.to_lower())
	check("all nine fell to the sword", living_mages().size() == 0, "%d alive" % living_mages().size())
	for m in living_mages():
		Health.apply_damage(m, 9999, m.global_position)
	await wait(3.5)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.5)

	# ---- Clearing the mages. ----
	check("clearing the mages sets Checkpoint (the courtyard)", cp() == "Checkpoint", cp())
	check("clearing the mages raises the bridge", [1, 2, 3, 4].all(func(i): return bridge_y(i) > -2.0), "y=%.2f/%.2f/%.2f/%.2f" % [bridge_y(1), bridge_y(2), bridge_y(3), bridge_y(4)])
	check("clearing the mages lets the camera go", focal_count() == 0, str(focal_count()))
	await shot("03_cleared.png")

	# ---- Over the bridge, with real input. ----
	var bridge_x := (-2 + 0.5) * CELL
	place(Vector3(bridge_x, 0.0, e.north + 1.5) + Vector3.UP, Vector3(bridge_x, 0.0, e.north + 4.1) + Vector3.UP)
	await wait(1.0)
	var lowest := [INF]
	var watch := func():
		for p in players():
			lowest[0] = minf(lowest[0], p.global_position.y)
	get_tree().physics_frame.connect(watch)
	await hold([list[0].action_up, list[1].action_up], 5.0)
	get_tree().physics_frame.disconnect(watch)
	var courtyard_z := 5 * CELL + CELL
	check("real input: both walk over the bridge into the courtyard", list.all(func(p): return p.global_position.z < courtyard_z) and lowest[0] > -1.6 and state() == "playing",
		"z %.1f / %.1f, lowest y %.2f, state %s" % [list[0].global_position.z, list[1].global_position.z, lowest[0], state()])
	await shot("04_courtyard.png")

	# ---- Deaths. ----
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.5)
	protect_players()
	var after := players()
	check("a death after the fight respawns on the arena, before the bridge", cp() == "Checkpoint" and after.all(func(p): return p.global_position.z > e.north and p.global_position.z < e.south), "%s, z %.1f" % [cp(), after[0].global_position.z])
	check("... with the bridge still up and the mages gone", bridge_y(2) > -2.0 and mages().all(func(m): return not m.is_alive()), "%d alive" % living_mages().size())
	check("... and the survival hold waiting", world.get_node("Enemies/SurvivalEnemyGroup/Enemies").get_child_count() == 0)

	# A death during the fight puts everything back.
	world.checkpoint_manager.set_current_checkpoint(world.get_node("CheckpointManager/CheckpointStart"))
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(2.0)
	protect_players()
	var back := players()
	check("a death in the arena respawns on the exit island", cp() == "CheckpointStart" and back.all(func(p): return p.global_position.z > e.south), cp())
	check("... with no mages until they walk in", living_mages().is_empty() and focal_count() == 0, "%d alive, %d focal" % [living_mages().size(), focal_count()])
	check("... then nine mages again and the camera framed", await walk_into_arena() and focal_count() == 4, "%d alive, %d focal" % [living_mages().size(), focal_count()])
	await shot("05_after_respawn.png")

	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
