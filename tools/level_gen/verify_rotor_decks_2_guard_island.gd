extends Node
## Test driver for the guard island of world_local_rotor_decks_2.tscn (add_rotor_decks_2_guard_island.py).
## Run through godot.sh, see docs/level-creation-for-agents.md:
##   tools/level_gen/godot.sh test tools/level_gen/verify_rotor_decks_2_guard_island.gd res://src/world/levels/world_local_rotor_decks_2.tscn /tmp/rd2_island 300
## Starts at Checkpoint3 (the hold won). The carriers walk to the gunner deck with real input, which wakes the
## shielded aviator on the island; a death there is tested; then real rockets: one into his shield, which must do
## nothing, and one detonated beside him, which kills him and raises the bridge to the island. The guard is pinned
## in line with the bazooka for the rocket shots, since aiming isn't what's under test.
## Save tracking is disabled, so save.json stays untouched.

const CELL := 2.999
const GUARD := "Enemies/IslandGuard/InstancedEnemies"
const TO_ISLAND_DECK := ["BridgePlatform5", "BridgePlatform6"]
const TO_ISLAND := ["BridgePlatform7", "BridgePlatform8"]
const DECKS := {
	"hold": [10, 13, 3, 4],
	"gunner": [10, 13, 7, 8],
	"island": [9, 14, 11, 14],
}

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0
var bazooka: BazookaSpecifics
var fired: Array = []


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(200.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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
	get_tree().root.get_texture().get_image().save_png(out_dir + "/" + file_name)


func tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func w(cx: int, cz: int, y: float = -1.0) -> Vector3:
	return Vector3((cx + 0.5) * CELL, y, (cz + 0.5) * CELL)


func players() -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func protect_players() -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)


func cp() -> String:
	return String(world.checkpoint_manager.current_checkpoint.name)


## Looked up each time: a checkpoint reset re-creates him under a generated name.
func guard() -> EnemyLocal:
	for child in world.get_node(GUARD).get_children():
		if child is EnemyLocal and not child.is_queued_for_deletion():
			return child
	return null


func guard_alive() -> bool:
	var g := guard()
	return g != null and g.is_alive()


func deck_of(pos: Vector3) -> String:
	var cx := floori(pos.x / CELL)
	var cz := floori(pos.z / CELL)
	for name in DECKS:
		var r: Array = DECKS[name]
		if cx >= r[0] and cx <= r[1] and cz >= r[2] and cz <= r[3]:
			return name
	return ""


func all_on(deck: String) -> bool:
	return players().all(func(p): return deck_of(p.global_position) == deck)


func bridge_up(name: String) -> bool:
	var shape := world.get_node("Level/Bridges/%s/AnimatableBody3D/CollisionShape3D" % name) as CollisionShape3D
	return not shape.disabled


func focal_count() -> int:
	return (world.get_node("CameraFollowRig") as CameraFollowRig)._extra_focal_nodes.size()


func visible_count(nodes: Array, lift: float = 1.0) -> int:
	var cam := get_viewport().get_camera_3d()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow(-6.0)
	var seen := 0
	for n in nodes:
		var pos: Vector3 = n.global_position + Vector3(0, lift, 0)
		if not cam.is_position_behind(pos) and rect.has_point(cam.unproject_position(pos)):
			seen += 1
	return seen


func nav_reaches(from: Vector3, to: Vector3) -> bool:
	var map := world.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	return path.size() > 0 and Vector2(path[-1].x - to.x, path[-1].z - to.z).length() < 1.0


func respawn_at(checkpoint: String) -> void:
	world.checkpoint_manager.set_current_checkpoint(world.get_node("CheckpointManager/" + checkpoint))
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(2.5)
	protect_players()


func clear_bolts() -> void:
	for c in world.get_children():
		if c is FireballSpawn or c is Fireball:
			c.queue_free()
	await get_tree().physics_frame


func forward() -> Vector3:
	var f := bazooka.muzzle.global_basis.z
	f.y = 0.0
	return f.normalized()


# ---------------------------------------------------------------- walking with real input
func expand(corners: Array) -> Array:
	var points: Array = [w(corners[0].x, corners[0].y)]
	for i in range(1, corners.size()):
		var a: Vector2i = corners[i - 1]
		var b: Vector2i = corners[i]
		var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		var c := a
		while c != b:
			c += step
			points.append(w(c.x, c.y))
	return points


func steer(p: PlayerLocal, to: Vector3) -> void:
	var n := Vector2(to.x - p.global_position.x, to.z - p.global_position.z).normalized()
	var keys := {p.action_right: n.x > 0.38, p.action_left: n.x < -0.38, p.action_down: n.y > 0.38, p.action_up: n.y < -0.38}
	for a in keys:
		if keys[a]:
			Input.action_press(a)
		else:
			Input.action_release(a)


func stop(p: PlayerLocal) -> void:
	for a in [p.action_up, p.action_down, p.action_left, p.action_right]:
		Input.action_release(a)


## The leader walks the cell centres in turn; the other carrier follows the same cells, waiting while closer than
## 2.2 m, as two players crossing one-cell bridges in single file would.
func walk_route(label: String, corners: Array) -> void:
	var list := players()
	var leader: PlayerLocal = list[1]
	var follower: PlayerLocal = list[0]
	var points := expand(corners)
	var lead_i := 0
	var follow_i := 0
	var lowest := INF
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and state() == "playing":
		await get_tree().physics_frame
		lowest = minf(lowest, minf(leader.global_position.y, follower.global_position.y))
		if lead_i < points.size() and Vector2(leader.global_position.x - points[lead_i].x, leader.global_position.z - points[lead_i].z).length() < 0.6:
			lead_i += 1
		if follow_i < points.size() and Vector2(follower.global_position.x - points[follow_i].x, follower.global_position.z - points[follow_i].z).length() < 0.6:
			follow_i += 1
		if lead_i < points.size():
			steer(leader, points[lead_i])
		else:
			stop(leader)
		var gap := leader.global_position.distance_to(follower.global_position)
		if follow_i < points.size() and (gap > 2.2 or lead_i >= points.size()) and follow_i < lead_i:
			steer(follower, points[follow_i])
		else:
			stop(follower)
		if lead_i >= points.size() and follow_i >= points.size() - 1:
			break
	stop(leader)
	stop(follower)
	await wait(0.5)
	var target := deck_of(points[-1])
	check("real input: the carriers walk " + label, all_on(target) and lowest > -1.6 and state() == "playing",
		"leader %s, follower %s, lowest y %.2f, state %s" % [deck_of(leader.global_position), deck_of(follower.global_position), lowest, state()])


# ---------------------------------------------------------------- the run
func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.0)
	var weapon := world.get_node("Weapon/Bazooka")
	bazooka = weapon.get_node("WeaponSpecifics") as BazookaSpecifics
	bazooka.fired.connect(func(r): fired.append(r))
	check_layout()
	await respawn_at("Checkpoint3")
	await check_at_checkpoint3("starting at Checkpoint3")
	await walk_route("over the new bridge to the gunner deck", [Vector2i(11, 3), Vector2i(11, 8)])
	await check_guard_wakes()
	await check_death_while_guard_lives()
	await check_front_rocket_blocked()
	await check_side_rocket_kills()
	await walk_route("over the island bridge onto the grass island", [Vector2i(11, 7), Vector2i(11, 12)])
	await shot("island_reached.png")
	await respawn_at("Checkpoint4")
	check("respawning at Checkpoint4 lands on the island", all_on("island"), str(players().map(func(p): return p.global_position)))
	check("... with both bridges up and the guard gone", TO_ISLAND_DECK.all(bridge_up) and TO_ISLAND.all(bridge_up) and not guard_alive())
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


func check_layout() -> void:
	check("the island has a navmesh", nav_reaches(w(10, 12), w(13, 13)))
	check("the guard can't walk off the island", not nav_reaches(w(11, 11), w(11, 8)))
	check("the guard isn't in the level until the carriers reach the gunner deck", guard() == null and (world.get_node("Enemies/IslandGuard") as NormalEnemyGroup).spawn_on_trigger)
	check("the bridges to the island start lowered", not TO_ISLAND.any(bridge_up))


func check_at_checkpoint3(label: String) -> void:
	check(label + ": the carriers stand on the hold deck", all_on("hold"), cp())
	check("... the bridge to the gunner deck is up and the island bridge down", TO_ISLAND_DECK.all(bridge_up) and not TO_ISLAND.any(bridge_up))
	check("... the guard isn't there yet and nothing is framed", guard() == null and focal_count() == 0)
	await shot("checkpoint3.png")


func check_guard_wakes() -> void:
	var woke := await wait_until(func(): return guard_alive() and guard().is_offensive, 3.0)
	check("both carriers on the gunner deck bring in the guard, awake", woke)
	var shielded := guard()
	check("one shielded aviator guards the island", shielded != null and FrontalGuard.find_on(shielded) != null and deck_of(shielded.global_position) == "island")
	check("the camera frames the gunner deck and the island", focal_count() == 4, str(focal_count()))
	var bolts := [0]
	var watch := func(n: Node): if n is FireballSpawn: bolts[0] += 1
	get_tree().node_added.connect(watch)
	protect_players()
	await wait(6.0)
	get_tree().node_added.disconnect(watch)
	await shot("guard_shooting.png")
	var g := guard()
	var nearest := INF
	for p in players():
		nearest = minf(nearest, Vector2(p.global_position.x - g.global_position.x, p.global_position.z - g.global_position.z).length())
	print("INFO guard to nearest carrier: %.1f m" % nearest)
	check("he shoots at the carriers across the gap", bolts[0] >= 3, "%d bolts" % bolts[0])
	check("he and both carriers are on screen", visible_count([g]) == 1 and visible_count(players()) == 2)
	check("he stays on the island", deck_of(g.global_position) == "island")


func check_death_while_guard_lives() -> void:
	await respawn_at("Checkpoint3")
	await check_at_checkpoint3("a death while he lives")
	await walk_route("back to the gunner deck after a respawn", [Vector2i(11, 3), Vector2i(11, 8)])
	var woke := await wait_until(func(): return guard_alive() and guard().is_offensive, 3.0)
	check("the trigger wakes him again", woke and focal_count() == 4)


## Holds the guard on the island in line with the muzzle, shield turned to the carriers, and stops him acting so his
## own bolts can't set the rocket off early.
func pin_guard(offset_side: float, ahead := 9.0) -> EnemyLocal:
	var g := guard()
	g.is_offensive = false
	g.speed = 0.0
	var origin := bazooka.muzzle.global_position
	var side := forward().cross(Vector3.UP)
	var spot := origin + forward() * ahead + side * offset_side
	var on_island := NavigationServer3D.map_get_closest_point(g.navigation_agent.get_navigation_map(), Vector3(spot.x, -1.0, spot.z))
	g.global_position = Vector3(on_island.x, g.global_position.y, on_island.z)
	var to := origin - g.global_position
	g.global_basis = Basis.looking_at(Vector3(to.x, 0.0, to.z).normalized(), Vector3.UP)
	# A burst already under way still finishes, and one of its bolts would set the rocket off over the gap.
	await wait_until(func(): return not g.enemy_state_machine.is_in_state("shieldfiring"), 3.0)
	await wait(0.6)
	await clear_bolts()
	return g


func check_front_rocket_blocked() -> void:
	print("INFO bazooka faces %s" % forward())
	var g: EnemyLocal = await pin_guard(0.0, 11.0)
	await wait(0.3)
	check("the bazooka points at the island", deck_of(bazooka.muzzle.global_position + forward() * 9.0) == "island" and deck_of(g.global_position) == "island", str(forward()))
	await clear_bolts()
	var blocks := [0]
	FrontalGuard.find_on(g).blocked.connect(func(_p): blocks[0] += 1)
	fired.clear()
	var carry: CarryInfo = world.get_node("Weapon/Bazooka/PickAndDropHandler").get_carry_info()
	await tap(carry.main_carrier.action_shoot)
	check("the back carrier fires a rocket", fired.size() == 1, str(fired.size()))
	if fired.is_empty():
		return
	var rocket: BazookaBulletLocal = fired[0]
	await wait_until(func(): return rocket.is_spent(), 4.0)
	print("INFO rocket went off %.1f m from the guard; guard at %s" % [rocket.global_position.distance_to(g.global_position + Vector3.UP), g.global_position])
	await shot("rocket_on_shield.png")
	await wait(0.3)
	check("a rocket into his shield is blocked", blocks[0] >= 1 and guard_alive(), "%d blocks" % blocks[0])
	check("so the island bridge stays down", not TO_ISLAND.any(bridge_up))


func check_side_rocket_kills() -> void:
	await wait(1.0)
	var g: EnemyLocal = await pin_guard(2.4)
	await wait(0.3)
	await clear_bolts()
	fired.clear()
	var carry: CarryInfo = world.get_node("Weapon/Bazooka/PickAndDropHandler").get_carry_info()
	await tap(carry.main_carrier.action_shoot)
	if fired.is_empty():
		check("a second rocket fires", false)
		return
	var rocket: BazookaBulletLocal = fired[0]
	var origin := bazooka.muzzle.global_position
	var along := (g.global_position - origin).dot(forward())
	await wait_until(func(): return (rocket.global_position - origin).dot(forward()) >= along or rocket.is_spent(), 5.0)
	check("the rocket draws level with him without touching him", not rocket.is_spent())
	await tap(carry.secondary_carrier.action_shoot)
	await wait(0.05)
	await shot("rocket_beside_guard.png")
	await wait(0.4)
	check("a rocket detonated beside him kills him", not guard_alive())
	var raised := await wait_until(func(): return TO_ISLAND.all(bridge_up), 8.0)
	check("his death raises the bridge to the island", raised)
	await wait_until(func(): return state() == "playing" and focal_count() == 0, 8.0)
	check("and saves Checkpoint4 and clears the framing", cp() == "Checkpoint4" and focal_count() == 0, "%s, %d" % [cp(), focal_count()])
	await wait(1.0)
