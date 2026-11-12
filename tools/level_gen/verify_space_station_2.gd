extends Node
## Test driver for world_local_space_station_2.tscn (sections 1 to 5 built so far). Run through godot.sh:
##   tools/level_gen/godot.sh test tools/level_gen/verify_space_station_2.gd res://src/world/levels/world_local_space_station_2.tscn <out_dir>
## Save tracking is disabled, so save.json stays untouched.

const BOLT_SCENE := preload("res://src/weapon/pulse_rifle/pulse_bolt.tscn")
const GROUP := "Enemies/EnemyGroup"

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0
var rifle: PulseRifleSpecifics


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(480.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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


func players() -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func enemies() -> Array:
	return world.get_node(GROUP + "/InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal)


func shielded() -> Array:
	return enemies().filter(func(e): return EnemyShield.find_on(e) != null)


func plain() -> Array:
	return enemies().filter(func(e): return EnemyShield.find_on(e) == null)


func hp_total(list: Array) -> int:
	var total := 0
	for e in list:
		total += Health.from_target(e).current_hp
	return total


func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func cp() -> String:
	return String(world.checkpoint_manager.current_checkpoint.name)


func visible_count(nodes: Array, height: float) -> int:
	var cam := get_viewport().get_camera_3d()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var seen := 0
	for n in nodes:
		var pos: Vector3 = n.global_position + Vector3(0, height, 0)
		if not cam.is_position_behind(pos) and rect.has_point(cam.unproject_position(pos)):
			seen += 1
	return seen


func fire(from: Vector3, direction: Vector3) -> PulseBolt:
	var bolt := BOLT_SCENE.instantiate() as PulseBolt
	world.add_child(bolt)
	bolt.launch(Vector3(from.x, rifle.muzzle.global_position.y, from.z), direction.normalized(), PulseRifleSpecifics.BOLT_SPEED,
		PulseRifleSpecifics.BOLT_RANGE, PulseRifleSpecifics.DAMAGE)
	return bolt


func track(bolt: PulseBolt) -> Dictionary:
	var last := {"direction": bolt._direction, "bounces": 0}
	while is_instance_valid(bolt) and not bolt._is_spent:
		last = {"direction": bolt._direction, "bounces": bolt._bounces}
		await get_tree().physics_frame
	return last


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.0)
	for p in players():
		Health.from_target(p).grant_invulnerability(9999.0)
	rifle = world.get_active_weapon().get_node("WeaponSpecifics") as PulseRifleSpecifics
	check_layout()
	await check_view_from_spawn()
	await check_real_fire()
	await check_bounces()
	await check_view_of_each_pack()
	check_vent_prompt()
	await check_vent_pops()
	await check_clear_warmup()
	check_hold_layout()
	await enter_deck2("walking over bridge 1 onto deck 2")
	await check_hold_runs()
	await check_gunner_waves()
	await check_respawn_mid_hold()
	await check_hold_cleared()
	check_island_layout()
	await enter_island_deck("walking over bridge 2 onto the split deck")
	await check_island_fight_starts()
	await check_island_shields()
	await check_respawn_mid_island()
	await check_walkway()
	await check_from_the_ledge()
	await check_island_cleared()
	await check_section_4()
	await check_section_5()
	await check_walk_to_end()
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


func check_layout() -> void:
	var all := enemies()
	check("nine warm-up robots", all.size() == 9, str(all.size()))
	check("three of them shielded, with the bubble up", shielded().size() == 3 and shielded().all(func(e): return EnemyShield.is_shielded(e)))
	check("none is offensive", all.all(func(e): return not e.is_offensive))
	for e in shielded():
		var nearest := INF
		for other in plain():
			nearest = minf(nearest, flat_distance(e.global_position, other.global_position))
		check("%s stands apart from the plain robots" % e.name, nearest >= 3.5, "nearest %.1f m" % nearest)


## The pack a robot belongs to: its name is EnemyRobot<pack><a|b|Shielded>.
func pack_of(pack: int) -> Array:
	return enemies().filter(func(e): return String(e.name).begins_with("EnemyRobot%d" % pack))


## The robots' heads, and the top of the bubble (1 m centre height plus 1.25 m radius) when it has one.
func pack_on_screen(pack: Array) -> bool:
	var bubbles := pack.filter(func(e): return EnemyShield.find_on(e) != null)
	return visible_count(pack, 1.0) == pack.size() and visible_count(bubbles, 2.25) == bubbles.size()


func check_view_from_spawn() -> void:
	await shot("ss2_spawn.png")
	var all := enemies()
	print("INFO from the spawn: %d/%d robots and %d/3 bubble tops on screen" % [visible_count(all, 1.0), all.size(), visible_count(shielded(), 2.25)])
	check("the middle pack, bubble and all, is on screen from the spawn", pack_on_screen(pack_of(2)))


## Carriers standing 6 m south of each pack see all of it. Placed by script, so this runs after the real fire.
func check_view_of_each_pack() -> void:
	var list := players()
	var home: Array = list.map(func(p): return p.global_position)
	for pack in [1, 2, 3]:
		var robots := pack_of(pack)
		var centre := Vector3.ZERO
		for e in robots:
			centre += e.global_position / robots.size()
		var offset: Vector3 = Vector3(centre.x, 0, centre.z + 6.0) - (home[0] + home[1]) / 2.0
		for i in list.size():
			list[i].velocity = Vector3.ZERO
			list[i].global_position = home[i] + Vector3(offset.x, 0, offset.z)
		await wait(1.5)
		await shot("ss2_pack%d.png" % pack)
		check("walking up to pack %d shows all of it, bubble and all" % pack, pack_on_screen(robots))
	for i in list.size():
		list[i].velocity = Vector3.ZERO
		list[i].global_position = home[i]
	await wait(1.0)


## The back carrier holds shoot: the rifle points up the middle, at the middle pack's pair.
func check_real_fire() -> void:
	var back: PlayerLocal = (world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info() as CarryInfo).main_carrier
	var before := hp_total(plain())
	Input.action_press(back.action_shoot)
	await wait(1.2)
	await shot("ss2_firing.png")
	Input.action_release(back.action_shoot)
	await wait(0.5)
	check("real fire from the spawn hits the plain robots ahead", hp_total(plain()) < before, "%d -> %d" % [before, hp_total(plain())])
	await wait_until(func(): return rifle.heat <= 0.0, 5.0)


## A bolt fired at each bubble from the south comes back, and hurts nobody.
func check_bounces() -> void:
	var before := hp_total(enemies())
	for e in shielded():
		var at: Vector3 = e.global_position
		var end: Dictionary = await track(fire(Vector3(at.x, 0, at.z + 9.0), Vector3.FORWARD))
		check("a bolt at %s bounces back south" % e.name, end.bounces == 1 and end.direction.z > 0.95, str(end))
	check("bounced bolts hurt no robot", hp_total(enemies()) == before, "%d -> %d" % [before, hp_total(enemies())])


func check_vent_prompt() -> void:
	for e in shielded():
		var forced := EnemyShield.is_vent_prompt_forced_near(e.global_position + Vector3(0, 0, 6), PulseRifleSpecifics.FORCED_PROMPT_DISTANCE)
		check("%s forces the VENT prompt nearby" % e.name, forced)


## Scripted: a hot vent from 4 m south of each bubble pops it.
func check_vent_pops() -> void:
	for e in shielded():
		var origin: Vector3 = e.global_position + Vector3(0, 1, 4)
		PulseVent.blast(world.get_world_3d(), origin, Vector3.FORWARD, 0.9)
	await wait(0.5)
	check("a hot vent 4 m away pops each bubble", shielded().is_empty(), "%d still shielded" % shielded().size())


func check_clear_warmup() -> void:
	check("still on Checkpoint before the clear", cp() == "Checkpoint", cp())
	for e in enemies():
		if e.is_alive():
			Health.apply_damage(e, 9999, e.global_position)
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check("clearing the warm-up sets Checkpoint2", cp() == "Checkpoint2", cp())
	check("clearing the warm-up projects bridge 1", bridge_up(BRIDGE1))
	await shot("ss2_bridge.png")


# ---- 2. The hold on deck 2. ----

const BRIDGE1 := [Vector2i(0, -9), Vector2i(0, -10)]
const BRIDGE2 := [Vector2i(0, -23), Vector2i(0, -24)]
## The deck 2 trigger's south edge (row -13's box is 6 m deep), in world z.
const HOLD_TRIGGER_Z := -13 * 2.999 + 1.5 + 2.0


func w(cx: float, cz: float) -> Vector3:
	return Vector3(cx * 2.999 + 1.5, 0, cz * 2.999 + 1.5)


func bridge_up(cells: Array) -> bool:
	var space := world.get_world_3d().direct_space_state
	for cell in cells:
		var at := w(cell.x, cell.y)
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 5.0, at + Vector3.DOWN * 10.0, 4)
		if space.intersect_ray(query).is_empty():
			return false
	return true


func survival() -> SurvivalEnemyGroup:
	return world.get_node("Enemies/SurvivalEnemyGroup") as SurvivalEnemyGroup


func chasers() -> Array:
	return survival().get_node("Enemies").find_children("*", "CharacterBody3D", true, false).filter(
		func(c): return c is EnemyLocal and c.is_alive())


func spawns_on_trigger(group: String) -> bool:
	return bool((world.get_node("Enemies/" + group) as NormalEnemyGroup).spawn_on_trigger)


func gunners() -> Array:
	return world.get_node("Enemies/Gunners/InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func nearest_player_distance(at: Vector3) -> float:
	var nearest := INF
	for p in players():
		nearest = minf(nearest, flat_distance(p.global_position, at))
	return nearest


func walk_north_until(cond: Callable, timeout: float) -> bool:
	var list := players()
	Input.action_press(list[0].action_up)
	Input.action_press(list[1].action_up)
	var ok: bool = await wait_until(cond, timeout)
	Input.action_release(list[0].action_up)
	Input.action_release(list[1].action_up)
	await get_tree().physics_frame
	return ok


func both_on_deck2() -> bool:
	return players().all(func(p): return p.global_position.z < HOLD_TRIGGER_Z - 1.0)


func check_hold_layout() -> void:
	check("the gunners aren't in the level until the hold starts", gunners().is_empty() and spawns_on_trigger("Gunners"), "%d present" % gunners().size())
	check("the hold lasts 60 s", is_equal_approx(survival().fight_duration, 60.0), str(survival().fight_duration))
	var first := survival()._spawn_interval_at(0.0)
	var last := survival()._spawn_interval_at(59.0)
	check("a robot every 3 s, start to end", is_equal_approx(first, 3.0) and is_equal_approx(last, 3.0), "%.2f .. %.2f" % [first, last])
	check("the survival wave waits too", not survival().is_running())


func enter_deck2(label: String) -> void:
	# In line on bridge 1's axis first: walking straight north from wherever the warm-up left them sometimes
	# missed the one-cell bridge.
	place_in_line(w(0, -6), Vector3.BACK)
	await wait(0.8)
	var ok: bool = await walk_north_until(both_on_deck2, 12.0)
	check("real input: " + label, ok and state() == "playing", "state %s" % state())
	var closed: bool = await wait_until(func(): return not bridge_up(BRIDGE1), 4.0)
	check("stepping onto deck 2 switches bridge 1 off", closed)


func check_hold_runs() -> void:
	await wait_until(func(): return not GameplayInput.is_locked(), 5.0)
	check("the survival wave starts", survival().is_running())
	var list := gunners()
	check("four gunners appear in deck 2's corners, awake", list.size() == 4 and list.all(func(e): return e.is_offensive), str(list.size()))
	check("each gunner is shielded and holds its position", list.all(func(e): return EnemyShield.is_shielded(e) and e.holds_position))
	var posts: Array = gunners().map(func(e): return e.global_position)
	var spawned := {}
	var approach := {}
	var bolts := {}
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 10500:
		for e in chasers():
			if not spawned.has(e):
				spawned[e] = nearest_player_distance(e.global_position)
			approach[e] = nearest_player_distance(e.global_position)
		for node in world.find_children("*", "Node3D", true, false):
			if node is Fireball:
				bolts[node] = true
		await get_tree().physics_frame
	await shot("ss2_hold.png")
	check("about one robot every 3 s (4 in the first 10.5 s)", spawned.size() >= 3 and spawned.size() <= 5, "%d spawned" % spawned.size())
	var closing := spawned.keys().filter(func(e): return is_instance_valid(e) and approach[e] < spawned[e] - 2.0)
	check("the robots run at the carriers", closing.size() >= 2, "%d of %d closed in by 2 m+" % [closing.size(), spawned.size()])
	check("the gunners shoot at the carriers", bolts.size() > 0, "%d laser bolts" % bolts.size())
	var moved := 0
	for i in posts.size():
		if flat_distance(gunners()[i].global_position, posts[i]) > 0.2:
			moved += 1
	check("the gunners stay in their corners", moved == 0, "%d moved" % moved)
	var before := hp_total(gunners())
	for e in gunners():
		var towards: Vector3 = (w(0, -16.5) - e.global_position)
		towards.y = 0.0
		var from: Vector3 = e.global_position + towards.normalized() * 8.0
		var end: Dictionary = await track(fire(from, -towards))
		check("a bolt at %s bounces off its bubble" % e.name, end.bounces >= 1, str(end))
	check("bounced bolts leave the gunners unhurt", hp_total(gunners()) == before, "%d -> %d" % [before, hp_total(gunners())])


## Every gunner fires waves of 2 or 3 laser bolts (`GUNNER_WAVE`), 0.45 s apart, with a random wait between waves.
## Each bolt's charge-up appears at its gunner's emitter, so the spawns are told apart by where they appear.
func check_gunner_waves() -> void:
	const WATCH_MS := 15000
	var list := gunners()
	var times := {}
	for e in list:
		times[e] = []
	var seen := {}
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < WATCH_MS:
		for node in world.get_children():
			if not node is FireballSpawn or seen.has(node):
				continue
			seen[node] = true
			for e in list:
				if is_instance_valid(e) and node.global_position.distance_to(e.get_node("FireballEmitter").global_position) < 1.0:
					times[e].append((Time.get_ticks_msec() - started) / 1000.0)
		await get_tree().physics_frame
	var sizes: Array = []
	var waits: Array = []
	for e in list:
		var waves: Array = []
		for t in times[e]:
			if waves.is_empty() or t - waves[-1][-1] > 1.0:
				waves.append([t])
				continue
			waves[-1].append(t)
		# A wave cut off by the start or end of the watch can look short.
		var whole := waves.filter(func(wave): return wave[0] > 0.6 and wave[-1] < WATCH_MS / 1000.0 - 1.2)
		sizes.append_array(whole.map(func(wave): return wave.size()))
		for i in range(1, waves.size()):
			waits.append(snappedf(waves[i][0] - waves[i - 1][-1], 0.01))
	print("INFO gunner wave sizes %s, waits between waves %s" % [sizes, waits])
	check("the gunners fire in waves of 2 or 3 bolts", sizes.size() >= 4 and sizes.all(func(n): return n == 2 or n == 3), str(sizes))
	# Too few waits fit in the watch to judge their spread, so sample a copy of a gunner's own behaviour instead.
	if list.is_empty():
		check("the wait between waves is random", false, "no gunners")
		return
	var source := list[0].get_node("MageBehavior") as MageBehavior
	var sample := MageBehavior.new()
	sample.cast_cooldown = source.cast_cooldown
	sample.cast_cooldown_jitter = source.cast_cooldown_jitter
	var cooldowns: Array = []
	for i in 40:
		sample._cast_cooldown_remaining = 0.0
		sample._apply_cast_band_intent(Vector3.FORWARD)
		cooldowns.append(sample._cast_cooldown_remaining)
	sample.free()
	check("the wait between waves is random, 3.5 s +/- 1 s", cooldowns.max() - cooldowns.min() > 1.0
		and cooldowns.min() >= 2.5 and cooldowns.max() <= 4.5, "%.2f to %.2f s" % [cooldowns.min(), cooldowns.max()])


func check_respawn_mid_hold() -> void:
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.5)
	for p in players():
		Health.from_target(p).grant_invulnerability(9999.0)
	check("a death mid-hold respawns at Checkpoint2", cp() == "Checkpoint2", cp())
	check("after the respawn bridge 1 is up", bridge_up(BRIDGE1))
	check("after the respawn the wave waits again", not survival().is_running() and chasers().is_empty(), "%d chasers" % chasers().size())
	check("after the respawn the gunners are gone until the hold starts again", gunners().is_empty(), "%d present" % gunners().size())
	await enter_deck2("crossing again after the respawn")
	await wait_until(func(): return not GameplayInput.is_locked(), 5.0)
	var list := gunners()
	check("crossing again restarts the hold with four shielded gunners", survival().is_running() and list.size() == 4 and list.all(func(e): return EnemyShield.is_shielded(e) and e.is_offensive), str(list.size()))


## Scripted kills, with the wave shortened in the driver (its real 60 s is checked above).
func check_hold_cleared() -> void:
	for e in gunners():
		EnemyShield.find_on(e).shatter()
	await wait(0.4)
	for e in gunners():
		Health.apply_damage(e, 9999, e.global_position)
	await wait(1.0)
	check("the gunners alone don't open the way on", not bridge_up(BRIDGE2) and cp() == "Checkpoint2", cp())
	survival().fight_duration = survival()._fight_elapsed + 1.0
	var deadline := Time.get_ticks_msec() + 15000
	while not survival().signal_emitted and Time.get_ticks_msec() < deadline:
		for e in chasers():
			Health.apply_damage(e, 9999, e.global_position)
		await wait(0.3)
	check("the wave ends once its robots are dead", survival().signal_emitted)
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check("wave and gunners down set Checkpoint3", cp() == "Checkpoint3", cp())
	check("wave and gunners down project bridge 2", bridge_up(BRIDGE2))
	await shot("ss2_hold_cleared.png")


# ---- 3. The gunner island. ----

const BRIDGE3 := [Vector2i(4, -39), Vector2i(5, -39)]
const WALKWAY := [Vector2i(-4, -30), Vector2i(-4, -31), Vector2i(-5, -31), Vector2i(-6, -31), Vector2i(-7, -31),
	Vector2i(-7, -32), Vector2i(-7, -33), Vector2i(-7, -34), Vector2i(-6, -34), Vector2i(-5, -34), Vector2i(-5, -35),
	Vector2i(-5, -36), Vector2i(-5, -37)]
const CELL := 2.999
## The deck 3 trigger (row -26, 6 m deep): both carriers are past its south edge.
const ISLAND_TRIGGER_Z := -26 * CELL + 1.5 + 2.0
## The ledge's south edge (row -38).
const LEDGE_SOUTH_Z := -38 * CELL + 1.5 + CELL / 2.0
const ISLAND_SOUTH_Z := -32 * CELL + 1.5 + CELL / 2.0
const ISLAND_NORTH_Z := -36 * CELL + 1.5 - CELL / 2.0


func survival2() -> SurvivalEnemyGroup:
	return world.get_node("Enemies/SurvivalEnemyGroup2") as SurvivalEnemyGroup


func chasers2() -> Array:
	return survival2().get_node("Enemies").find_children("*", "CharacterBody3D", true, false).filter(
		func(c): return c is EnemyLocal and c.is_alive())


func island_gunners() -> Array:
	return world.get_node("Enemies/IslandGunners/InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func focal_count() -> int:
	return (world.get_node("CameraFollowRig") as CameraFollowRig)._extra_focal_nodes.size()


func floor_at(cell: Vector2i) -> bool:
	var at := w(cell.x, cell.y)
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 5.0, at + Vector3.DOWN * 10.0, 4)
	return not world.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func path_reaches(from: Vector3, to: Vector3) -> bool:
	var map := world.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	if path.is_empty():
		return false
	return flat_distance(path[path.size() - 1], to) < 1.0


func lowest_player_y() -> float:
	var lowest := INF
	for p in players():
		lowest = minf(lowest, p.global_position.y)
	return lowest


func both_on_landing() -> bool:
	return players().all(func(p): return p.global_position.z < ISLAND_TRIGGER_Z - 1.0)


func check_island_layout() -> void:
	check("the gunner island stands alone: no floor in the gap or beside the walkway",
		not floor_at(Vector2i(0, -30)) and not floor_at(Vector2i(0, -31)) and not floor_at(Vector2i(-3, -33)) and not floor_at(Vector2i(-6, -32)) and not floor_at(Vector2i(0, -37)))
	check("the walkway is floor all along", WALKWAY.all(func(c): return floor_at(c)))
	check("no walking route from the carriers' half to the island", not path_reaches(w(0, -27), w(0, -34)))
	check("a walking route over the walkway to the ledge", path_reaches(w(0, -27), w(0, -39)))
	check("three flat shields round the island", ["WestShield", "EastShield", "SouthShield"].all(func(n): return world.get_node_or_null("Level/Shields/" + n) is FlatShield))
	check("the island gunners aren't in the level until the fight starts", island_gunners().is_empty() and spawns_on_trigger("IslandGunners"), "%d present" % island_gunners().size())
	check("the island wave lasts 40 s at one robot every 3 s", is_equal_approx(survival2().fight_duration, 40.0) and is_equal_approx(survival2()._spawn_interval_at(0.0), 3.0) and is_equal_approx(survival2()._spawn_interval_at(39.0), 3.0), "%.1f s" % survival2().fight_duration)


func enter_island_deck(label: String) -> void:
	var ok: bool = await walk_north_until(both_on_landing, 14.0)
	check("real input: " + label, ok and state() == "playing", "state %s" % state())
	var closed: bool = await wait_until(func(): return not bridge_up(BRIDGE2), 4.0)
	check("stepping onto the deck switches bridge 2 off", closed)


func check_island_fight_starts() -> void:
	await wait_until(func(): return not GameplayInput.is_locked(), 5.0)
	check("the island wave starts", survival2().is_running())
	var list := island_gunners()
	check("four island gunners appear, unshielded, holding position, awake", list.size() == 4 and list.all(func(e): return EnemyShield.find_on(e) == null and e.holds_position and e.is_offensive), str(list.size()))
	check("the island is framed", focal_count() == 4, str(focal_count()))
	var bolts := {}
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 6000:
		for node in world.find_children("*", "Node3D", true, false):
			if node is Fireball:
				bolts[node] = true
		await get_tree().physics_frame
	await shot("ss2_island.png")
	check("all four island gunners are on screen from the landing", visible_count(island_gunners(), 1.0) == 4, "%d/4" % visible_count(island_gunners(), 1.0))
	check("both carriers are on screen on the landing", visible_count(players(), 1.6) == 2, "%d/2" % visible_count(players(), 1.6))
	check("the island gunners shoot through their shields", bolts.size() > 0, "%d laser bolts" % bolts.size())


## Bolts from the west, east and south bounce off the shields; a hot vent from the south is stopped too.
func check_island_shields() -> void:
	var before := hp_total(island_gunners())
	for e in island_gunners():
		var at: Vector3 = e.global_position
		for from in [Vector3(at.x, 0, ISLAND_SOUTH_Z + 8.0), Vector3(w(-7, 0).x, 0, at.z), Vector3(w(4, 0).x, 0, at.z)]:
			var direction: Vector3 = at - from
			direction.y = 0.0
			var end: Dictionary = await track(fire(from, direction))
			check("a bolt at %s from %s bounces off a shield" % [e.name, from], end.bounces >= 1, str(end))
	check("bounced bolts leave the island gunners unhurt", hp_total(island_gunners()) == before, "%d -> %d" % [before, hp_total(island_gunners())])
	var origin := Vector3(w(0, 0).x, 1.0, ISLAND_SOUTH_Z + 2.0)
	PulseVent.blast(world.get_world_3d(), origin, Vector3.FORWARD, 1.0)
	await wait(0.3)
	check("a full vent 2 m south of the south shield doesn't reach the gunners", hp_total(island_gunners()) == before, "%d -> %d" % [before, hp_total(island_gunners())])


func check_respawn_mid_island() -> void:
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.5)
	for p in players():
		Health.from_target(p).grant_invulnerability(9999.0)
	check("a death at the island respawns at Checkpoint3", cp() == "Checkpoint3", cp())
	check("after the respawn bridge 2 is up", bridge_up(BRIDGE2))
	check("after the respawn the island wave waits and the framing is gone", not survival2().is_running() and chasers2().is_empty() and focal_count() == 0, "focal %d" % focal_count())
	check("after the respawn the island gunners are gone until the fight starts again", island_gunners().is_empty(), "%d present" % island_gunners().size())
	await enter_island_deck("crossing bridge 2 again after the respawn")
	await wait_until(func(): return not GameplayInput.is_locked(), 5.0)
	check("crossing again restarts the island fight", survival2().is_running() and island_gunners().size() == 4 and island_gunners().all(func(e): return e.is_offensive), str(island_gunners().size()))


## Real input along the walkway: each carrier steers cell by cell with its own directional actions, the front one
## waiting whenever the back one lags. Chasers are killed by script on the way, so only the steering is tested.
func check_walkway() -> void:
	var carry: CarryInfo = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info()
	var front: PlayerLocal = carry.secondary_carrier
	var back: PlayerLocal = carry.main_carrier
	var points: Array = [w(-4, -28)]
	for c in WALKWAY:
		points.append(w(c.x, c.y))
	points.append(w(-5, -38.6))
	var progress := {front: 0, back: 0}
	var lowest := [INF]
	var deadline := Time.get_ticks_msec() + 40000
	var reached := false
	var frames := [0, 0]
	while Time.get_ticks_msec() < deadline and state() == "playing":
		frames[0] += 1
		if visible_count(players(), 1.6) == 2 and visible_count(players(), 0.0) == 2:
			frames[1] += 1
		for e in chasers2():
			Health.apply_damage(e, 9999, e.global_position)
		lowest[0] = minf(lowest[0], lowest_player_y())
		reached = players().all(func(p): return p.global_position.z < LEDGE_SOUTH_Z - 1.0)
		if reached:
			break
		var gap := flat_distance(front.global_position, back.global_position)
		_steer(back, points, progress)
		if gap > 3.4:
			_release(front)
		else:
			_steer(front, points, progress)
		await get_tree().physics_frame
	_release(front)
	_release(back)
	await wait(0.3)
	await shot("ss2_ledge.png")
	check("real input: the carriers walk the S walkway to the ledge without falling", reached and state() == "playing" and lowest[0] > -1.5,
		"reached %s, state %s, lowest y %.2f, front at %s, back at %s" % [reached, state(), lowest[0], front.global_position, back.global_position])
	check("both carriers stay on screen all along the walkway", frames[1] == frames[0], "%d of %d frames" % [frames[1], frames[0]])
	check("both carriers are on screen on the ledge", visible_count(players(), 1.6) == 2, "%d/2" % visible_count(players(), 1.6))


func _steer(player: PlayerLocal, points: Array, progress: Dictionary) -> void:
	var index: int = progress[player]
	while index < points.size() - 1 and flat_distance(player.global_position, points[index]) < 0.6:
		index += 1
	progress[player] = index
	var to: Vector3 = points[index] - player.global_position
	_set_action(player.action_right, to.x > 0.25)
	_set_action(player.action_left, to.x < -0.25)
	_set_action(player.action_down, to.z > 0.25)
	_set_action(player.action_up, to.z < -0.25)


func _release(player: PlayerLocal) -> void:
	for action in [player.action_right, player.action_left, player.action_down, player.action_up]:
		_set_action(action, false)


func _set_action(action: String, pressed: bool) -> void:
	if pressed and not Input.is_action_pressed(action):
		Input.action_press(action)
	if not pressed and Input.is_action_pressed(action):
		Input.action_release(action)


func check_from_the_ledge() -> void:
	var at: Vector3 = island_gunners()[0].global_position
	var before := hp_total(island_gunners())
	var end: Dictionary = await track(fire(Vector3(at.x, 0, LEDGE_SOUTH_Z - 1.0), Vector3.BACK))
	check("from the ledge a bolt hits a gunner from behind", end.bounces == 0 and hp_total(island_gunners()) < before, "%s hp %d -> %d" % [end, before, hp_total(island_gunners())])
	var origin := Vector3(at.x, 1.0, ISLAND_NORTH_Z - 1.0)
	var hp_before := hp_total(island_gunners())
	PulseVent.blast(world.get_world_3d(), origin, Vector3.BACK, 1.0)
	await wait(0.3)
	check("a vent from the open north side reaches the gunners", hp_total(island_gunners()) < hp_before, "%d -> %d" % [hp_before, hp_total(island_gunners())])


func check_island_cleared() -> void:
	for e in island_gunners():
		Health.apply_damage(e, 9999, e.global_position)
	await wait(1.0)
	check("the island gunners alone don't open the way on", not bridge_up(BRIDGE3) and cp() == "Checkpoint3", cp())
	survival2().fight_duration = survival2()._fight_elapsed + 1.0
	var deadline := Time.get_ticks_msec() + 15000
	while not survival2().signal_emitted and Time.get_ticks_msec() < deadline:
		for e in chasers2():
			Health.apply_damage(e, 9999, e.global_position)
		await wait(0.3)
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check("wave and island gunners down set Checkpoint4", cp() == "Checkpoint4", cp())
	check("wave and island gunners down project bridge 3 east of the ledge", bridge_up(BRIDGE3))
	check("the island framing is cleared", focal_count() == 0, str(focal_count()))
	await shot("ss2_bridge3.png")


# ---- 4 and 5. The bank shots. ----

const BRIDGE4 := [Vector2i(12, -40), Vector2i(13, -40), Vector2i(14, -40)]
const BRIDGE5 := [Vector2i(21, -40), Vector2i(22, -40)]
## The decks: deck 4 is cells x 6..11, rows -38 (south edge) to -42 (north edge); deck 5 x 15..20, rows -39 to -41.
const DECK4_ROWS := Vector2i(-42, -38)
const DECK5_ROWS := Vector2i(-41, -39)


func group_alive(group: String) -> Array:
	return world.get_node("Enemies/%s/InstancedEnemies" % group).get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func groups_alive(groups: Array) -> Array:
	var out: Array = []
	for g in groups:
		out.append_array(group_alive(g))
	return out


func bank_survival(survival_name: String) -> SurvivalEnemyGroup:
	return world.get_node("Enemies/" + survival_name) as SurvivalEnemyGroup


func bank_chasers(survival_name: String) -> Array:
	return bank_survival(survival_name).get_node("Enemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


## The shielded chasers crowd the carriers, so they are cleared before the driver lines the pair up to shoot.
func kill_bank_chasers() -> void:
	for survival_name in ["BankSurvival", "CrossfireSurvival"]:
		for e in bank_chasers(survival_name):
			e.queue_free()
	await get_tree().physics_frame


func check_bank_survival_layout() -> void:
	for survival_name in ["BankSurvival", "CrossfireSurvival"]:
		var group := bank_survival(survival_name)
		check(survival_name + " lasts 40 s at one robot every 6 s", is_equal_approx(group.fight_duration, 40.0)
			and is_equal_approx(group._spawn_interval_at(0.0), 6.0) and is_equal_approx(group._spawn_interval_at(39.0), 6.0),
			"%.1f s, %.1f s" % [group.fight_duration, group._spawn_interval_at(0.0)])
		check(survival_name + " spawns shielded robots", group.enemy_scene.resource_path.ends_with("enemy_robot_shielded.tscn"), group.enemy_scene.resource_path)


func carry() -> CarryInfo:
	return world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info()


## Puts the pair in single file, the front carrier at `front`, the back one 2.6 m behind it along `back_dir`.
func place_in_line(front: Vector3, back_dir: Vector3) -> void:
	var info := carry()
	front.y = lowest_player_y()
	for p in players():
		p.velocity = Vector3.ZERO
	info.secondary_carrier.global_position = front
	info.main_carrier.global_position = front + back_dir.normalized() * 2.6


## Walks the pair along `action` with real input until `cond` holds.
func walk_until(action: String, cond: Callable, timeout: float) -> bool:
	var list := players()
	for p in list:
		Input.action_press(p.get(action))
	var ok: bool = await wait_until(cond, timeout)
	for p in list:
		Input.action_release(p.get(action))
	await get_tree().physics_frame
	return ok


func enter_bank_deck(label: String, start: Vector3, trigger_x: float, bridge: Array) -> void:
	place_in_line(start, Vector3.LEFT)
	await wait(0.8)
	var ok: bool = await walk_until("action_right", func(): return players().all(func(p): return p.global_position.x > trigger_x), 15.0)
	check("real input: " + label, ok and state() == "playing", "state %s, lowest y %.2f" % [state(), lowest_player_y()])
	var closed: bool = await wait_until(func(): return not bridge_up(bridge), 4.0)
	check("landing switches the bridge behind them off", closed)
	await wait_until(func(): return not GameplayInput.is_locked(), 5.0)


func check_bank_fight_starts(groups: Array, survival_name: String, label: String) -> void:
	# They appear, awake, once the bridge behind has finished switching off, which takes longer with more platforms.
	await wait_until(func(): return groups_alive(groups).size() == 4 * groups.size(), 4.0)
	var gunners := groups_alive(groups)
	var asleep := gunners.filter(func(e): return not e.is_offensive).map(func(e): return "%s/%s" % [e.get_parent().get_parent().name, e.name])
	check(label + ": its gunners wake", gunners.size() == 4 * groups.size() and asleep.is_empty(), "%d, asleep %s" % [gunners.size(), asleep])
	check(label + ": the islands are framed", focal_count() == 4, str(focal_count()))
	var spawned: bool = await wait_until(func(): return not bank_chasers(survival_name).is_empty(), 2.0)
	var chasers := bank_chasers(survival_name)
	check(label + ": the shielded robots' wave starts", bank_survival(survival_name).is_running() and spawned
		and chasers.all(func(e): return EnemyShield.is_shielded(e) and e.is_offensive), "%d chasers" % chasers.size())
	var first: EnemyLocal = null if chasers.is_empty() else chasers[0]
	var from_carriers := INF if first == null else nearest_player_distance(first.global_position)
	var bolts := {}
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 5000:
		for node in world.find_children("*", "Node3D", true, false):
			if node is Fireball:
				bolts[node] = true
		await get_tree().physics_frame
	await shot("ss2_%s.png" % label.to_lower().replace(" ", "_"))
	if first != null and is_instance_valid(first) and first.is_alive():
		check(label + ": the shielded robots run at the carriers", nearest_player_distance(first.global_position) < from_carriers - 1.5,
			"%.1f m -> %.1f m" % [from_carriers, nearest_player_distance(first.global_position)])
	check(label + ": every gunner is on screen", visible_count(gunners, 1.0) == gunners.size(), "%d/%d" % [visible_count(gunners, 1.0), gunners.size()])
	check(label + ": both carriers are on screen", visible_count(players(), 1.6) == 2, "%d/2" % visible_count(players(), 1.6))
	check(label + ": the gunners shoot through their cover", bolts.size() > 0, "%d laser bolts" % bolts.size())


## Bolts fired straight at each gunner from every cell of the deck, all at once: none may land.
func check_no_straight_shots(group: String, deck_x: Vector2i, deck_rows: Vector2i) -> void:
	await kill_bank_chasers()
	var gunners := group_alive(group)
	var before := hp_total(gunners)
	var fired := 0
	for cx in range(deck_x.x, deck_x.y + 1):
		for cz in range(deck_rows.x, deck_rows.y + 1):
			var from := w(cx, cz)
			for e in gunners:
				var to: Vector3 = e.global_position - from
				to.y = 0.0
				fire(from, to)
				fired += 1
	await wait(1.5)
	check("%s: %d straight shots from all over the deck all miss" % [group, fired], hp_total(gunners) == before, "%d -> %d" % [before, hp_total(gunners)])


## Real fire: the pair lines up on the bank's lane for one gunner row, facing the island, and the back carrier
## holds shoot. The lane is where a bolt fired straight across the gap meets the 45 degree bank at that row's depth.
func check_bank_lane(group: String, row: int, toward_south: bool, deck_rows: Vector2i) -> void:
	var bank := world.get_node("Level/Shields/%sBank" % group) as Node3D
	var row_z := row * CELL + 1.5
	var lane_x := bank.global_position.x - (row_z - bank.global_position.z)
	var south_z := deck_rows.y * CELL + 1.5 + CELL / 2.0
	var north_z := deck_rows.x * CELL + 1.5 - CELL / 2.0
	var front_z := south_z - 1.0 if toward_south else north_z + 1.0
	var back_dir := Vector3.FORWARD if toward_south else Vector3.BACK
	await kill_bank_chasers()
	place_in_line(Vector3(lane_x, 0, front_z), back_dir)
	await wait(1.0)
	var shift := lane_x - rifle.muzzle.global_position.x
	place_in_line(Vector3(lane_x + shift, 0, front_z), back_dir)
	await wait(1.0)
	var aim := rifle.muzzle.global_basis.z
	var row_gunners := group_alive(group).filter(func(e): return absf(e.global_position.z - row_z) < 1.0)
	var before := hp_total(row_gunners)
	var shooter := carry().main_carrier
	Input.action_press(shooter.action_shoot)
	await wait(1.2)
	await shot("ss2_bank_%s_%d.png" % [group.to_lower(), absi(row)])
	Input.action_release(shooter.action_shoot)
	await wait(0.6)
	check("real fire: %s's bank reaches its row %d gunners" % [group, row], hp_total(row_gunners) < before,
		"muzzle x %.2f vs lane %.2f, aim %s, hp %d -> %d" % [rifle.muzzle.global_position.x, lane_x, aim, before, hp_total(row_gunners)])
	await wait_until(func(): return rifle.heat <= 0.0 and not rifle.is_overheated(), 6.0)


func check_respawn_mid_bank() -> void:
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.5)
	for p in players():
		Health.from_target(p).grant_invulnerability(9999.0)
	check("a death at the bank island respawns at Checkpoint4 on the ledge", cp() == "Checkpoint4", cp())
	check("after the respawn bridge 3 is up and the framing gone", bridge_up(BRIDGE3) and focal_count() == 0)
	check("after the respawn the bank gunners are gone until the fight starts again", group_alive("BankGunners").is_empty(), "%d present" % group_alive("BankGunners").size())
	check("after the respawn the shielded wave waits again", not bank_survival("BankSurvival").is_running() and bank_chasers("BankSurvival").is_empty(),
		"%d chasers" % bank_chasers("BankSurvival").size())


## Scripted kills, with the shielded wave shortened in the driver (its real 40 s is checked in the layout).
func clear_groups(groups: Array, survival_name: String, expected_cp: String, bridge: Array, label: String) -> void:
	for g in groups:
		for e in group_alive(g):
			Health.apply_damage(e, 9999, e.global_position)
	await wait(1.5)
	check(label + ": the gunners alone don't open the way on", not bridge_up(bridge) and cp() != expected_cp, cp())
	var wave := bank_survival(survival_name)
	wave.fight_duration = wave._fight_elapsed + 1.0
	var deadline := Time.get_ticks_msec() + 15000
	while not wave.signal_emitted and Time.get_ticks_msec() < deadline:
		for e in bank_chasers(survival_name):
			EnemyShield.find_on(e).shatter()
			Health.apply_damage(e, 9999, e.global_position)
		await wait(0.3)
	check(label + ": the shielded wave ends once its robots are dead", wave.signal_emitted)
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check(label + " sets " + expected_cp, cp() == expected_cp, cp())
	check(label + " projects the next bridge east", bridge_up(bridge))
	check(label + " clears the framing", focal_count() == 0, str(focal_count()))


func check_section_4() -> void:
	check_bank_survival_layout()
	await enter_bank_deck("over bridge 3 onto deck 4", w(2, -39), w(7, 0).x, BRIDGE3)
	await check_bank_fight_starts(["BankGunners"], "BankSurvival", "Bank island")
	await check_no_straight_shots("BankGunners", Vector2i(6, 11), DECK4_ROWS)
	await check_respawn_mid_bank()
	await enter_bank_deck("over bridge 3 again after the respawn", w(2, -39), w(7, 0).x, BRIDGE3)
	await wait_until(func(): return group_alive("BankGunners").size() == 4, 4.0)
	check("crossing again brings back the bank gunners, awake", group_alive("BankGunners").size() == 4 and group_alive("BankGunners").all(func(e): return e.is_offensive), str(group_alive("BankGunners").size()))
	check("crossing again restarts the shielded wave", bank_survival("BankSurvival").is_running())
	await check_bank_lane("BankGunners", -34, true, DECK4_ROWS)
	await check_bank_lane("BankGunners", -33, true, DECK4_ROWS)
	await clear_groups(["BankGunners"], "BankSurvival", "Checkpoint5", BRIDGE4, "Clearing the bank island")


func check_section_5() -> void:
	await enter_bank_deck("over bridge 4 onto deck 5", w(10, -40), w(16, 0).x, BRIDGE4)
	await check_bank_fight_starts(["CrossfireSouth", "CrossfireNorth"], "CrossfireSurvival", "Crossfire")
	await check_no_straight_shots("CrossfireSouth", Vector2i(15, 20), DECK5_ROWS)
	await check_no_straight_shots("CrossfireNorth", Vector2i(15, 20), DECK5_ROWS)
	await check_bank_lane("CrossfireSouth", -35, true, DECK5_ROWS)
	await check_bank_lane("CrossfireSouth", -34, true, DECK5_ROWS)
	await check_bank_lane("CrossfireNorth", -45, false, DECK5_ROWS)
	await check_bank_lane("CrossfireNorth", -46, false, DECK5_ROWS)
	for e in group_alive("CrossfireSouth"):
		Health.apply_damage(e, 9999, e.global_position)
	await wait(2.0)
	check("clearing only the south island doesn't open the way on", cp() == "Checkpoint5" and not bridge_up(BRIDGE5) and focal_count() == 4, cp())
	await clear_groups(["CrossfireNorth"], "CrossfireSurvival", "Checkpoint6", BRIDGE5, "Clearing both islands")


func check_walk_to_end() -> void:
	place_in_line(w(19, -40), Vector3.LEFT)
	await wait(0.8)
	var finished: bool = await walk_until("action_right", func(): return state() == "levelfinished", 15.0)
	check("real input: over bridge 5 to the end area on deck 6", finished, "state %s, x %.1f" % [state(), players()[0].global_position.x])
