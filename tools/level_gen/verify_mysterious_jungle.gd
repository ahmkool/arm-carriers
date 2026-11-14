extends Node
## End-to-end automated verification driver for world_local_mysterious_jungle.tscn.
## Exercises real-input Siege Bow draw, pierce, renocking, and shockwave, plus all 6 sections,
## triggers, camera framings, sinking split walkways, SpikeTrap plates, checkpoint respawns, and victory.
## Save tracking is disabled so save.json stays untouched.

const CELL := 2.999

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var bow: Node3D
var specifics: SiegeBowSpecifics
var shooter: PlayerLocal
var setter: PlayerLocal
var shots: Array = []
var fails := 0


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(380.0).timeout.connect(_on_watchdog)
	_run.call_deferred()


func _on_watchdog() -> void:
	print("WATCHDOG quit")
	get_tree().quit(2)


func check(label: String, ok: bool, detail: String = "") -> void:
	var suffix := "" if detail.is_empty() else "  [" + detail + "]"
	var prefix := "PASS " if ok else "FAIL "
	print(prefix + label + suffix)
	if not ok:
		fails += 1


func w(cx: float, cz: float, y: float = 0.0) -> Vector3:
	return Vector3((cx + 0.5) * CELL, y, (cz + 0.5) * CELL)


func state() -> String:
	if not is_instance_valid(gsm):
		return "levelfinished"
	if gsm.current == null:
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
	get_tree().root.get_texture().get_image().save_png(out_dir + "/" + file_name)


func overhead_shot(file_name: String, pos: Vector3, look_target: Vector3) -> void:
	var game_cam := get_viewport().get_camera_3d()
	var temp_cam := Camera3D.new()
	world.add_child(temp_cam)
	temp_cam.global_position = pos
	temp_cam.look_at(look_target, Vector3.FORWARD)
	temp_cam.fov = 62.0
	temp_cam.make_current()
	await shot(file_name)
	if is_instance_valid(game_cam):
		game_cam.make_current()
	temp_cam.queue_free()
	await get_tree().process_frame


func players() -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func refresh_carriers() -> void:
	bow = world.get_active_weapon()
	specifics = bow.get_node("WeaponSpecifics") as SiegeBowSpecifics
	var carry: CarryInfo = (bow.get_node("PickAndDropHandler") as PickAndDropHandler).get_carry_info()
	shooter = carry.main_carrier
	setter = carry.secondary_carrier


func protect_players() -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)


func place_pair(front_pos: Vector3, back_pos: Vector3) -> void:
	refresh_carriers()
	setter.velocity = Vector3.ZERO
	shooter.velocity = Vector3.ZERO
	setter.global_position = front_pos
	shooter.global_position = back_pos


func gap() -> float:
	var list := players()
	var d: Vector3 = list[0].global_position - list[1].global_position
	return Vector2(d.x, d.z).length()


func action(player: PlayerLocal, suffix: String) -> String:
	return "p%s_%s" % [player.device_id, suffix]


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame


func press_action(act: String) -> void:
	Input.action_press(act)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(act)
	await get_tree().physics_frame


func on_fired(_arrow: SiegeArrow, draw: float, damage: int, pierce_hits: int, flight_range: float) -> void:
	shots.append({"draw": draw, "damage": damage, "pierce": pierce_hits, "range": flight_range})


func group_enemies(path: String) -> Array:
	var holder := world.get_node(path).get_node_or_null("InstancedEnemies")
	if holder == null:
		holder = world.get_node(path).get_node_or_null("Enemies")
	if holder == null:
		return []
	return holder.get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func kill_group(path: String) -> void:
	for enemy in group_enemies(path):
		Health.apply_damage(enemy, 9999, enemy.global_position)


func focal_count() -> int:
	return (world.get_node("CameraFollowRig") as CameraFollowRig)._extra_focal_nodes.size()


func visible_count(nodes: Array) -> int:
	var cam := get_viewport().get_camera_3d()
	var vp_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var seen := 0
	for node in nodes:
		if _is_node_on_screen(cam, vp_rect, node):
			seen += 1
	return seen


func _is_node_on_screen(cam: Camera3D, vp_rect: Rect2, node: Node3D) -> bool:
	if not is_instance_valid(node):
		return false
	var pos := node.global_position + Vector3(0, 1.0, 0)
	if cam.is_position_behind(pos):
		return false
	return vp_rect.has_point(cam.unproject_position(pos))


func _player_distance(enemy: EnemyLocal) -> float:
	var nearest := INF
	for p in players():
		var d: Vector3 = p.global_position - enemy.global_position
		nearest = minf(nearest, Vector2(d.x, d.z).length())
	return nearest


func check_view(label: String, enemies: Array, reach: float = 20.0) -> void:
	var players_seen := visible_count(players())
	var near := enemies.filter(func(e): return is_instance_valid(e) and e.is_alive() and _player_distance(e) <= reach)
	var near_seen := visible_count(near)
	var detail := "players %d/2, near %d/%d, focals=%d, cam_y=%.1f" % [
		players_seen, near_seen, near.size(), focal_count(), get_viewport().get_camera_3d().global_position.y
	]
	if focal_count() == 0:
		check(label + " (normal zoom)", players_seen == 2, detail)
		return
	check(label, players_seen == 2 and near_seen == near.size(), detail)


func bridge_body_y(platform_name: String) -> float:
	var body := world.get_node("Level/Bridges/" + platform_name + "/AnimatableBody3D") as Node3D
	return body.position.y


func current_cp() -> String:
	var cp := world.checkpoint_manager.get("current_checkpoint") as Node
	if cp == null:
		return ""
	return cp.name


func nav_connected(from_pos: Vector3, to_pos: Vector3) -> bool:
	var nav_map := world.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(nav_map, from_pos, to_pos, true)
	if path.is_empty():
		return false
	var end_pt := path[path.size() - 1]
	return Vector2(end_pt.x - to_pos.x, end_pt.z - to_pos.z).length() < 1.8


func do_respawn() -> void:
	world.restart_game()
	await wait_until(func(): return state() == "resettingcheckpoint", 5.0)
	var ok := await wait_until(func(): return state() == "playing", 20.0)
	check("respawn returns to Playing", ok, "cp=" + current_cp())
	await wait(0.5)
	protect_players()
	refresh_carriers()


func _run() -> void:
	var started := await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing state", started, state())
	protect_players()
	await wait(0.8)
	refresh_carriers()
	specifics.fired.connect(on_fired)

	_verify_theme_and_setup()
	_verify_navmesh()
	await overhead_shot("00_overview_south.png", Vector3(24.0, 95.0, -35.0), Vector3(24.0, -1.0, -42.0))
	await overhead_shot("00_overview_north.png", Vector3(8.0, 95.0, -125.0), Vector3(8.0, -1.0, -132.0))

	await _test_section_1_causeway()
	await _test_section_2_courtyard()
	await _test_section_3_river_walkways()
	await _test_section_4_lattice_shrine()
	await _test_section_5_trap_chamber()
	await _test_section_6_ziggurat_finale()

	print("VERIFY_DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _verify_theme_and_setup() -> void:
	check("active weapon is siege_bow", world.get_active_weapon_id() == "siege_bow", world.get_active_weapon_id())
	check("both carriers hold the bow", is_instance_valid(shooter) and is_instance_valid(setter))
	check("bow faces north along causeway", specifics.global_basis.z.z < -0.9, str(specifics.global_basis.z))
	check("custom golden aim guide color set", world.aim_guide_color.a > 0.5, str(world.aim_guide_color))
	check("jungle fireflies node active", world.has_node("Level/JungleFireflies"))
	check("grand ziggurat monument present", world.has_node("Level/Monuments/GrandZiggurat"))
	var grid := world.get_node("Level/NavigationRegion3D/GridMapFloor") as GridMap
	check("jungle tiles footstep surface is STONE", FootstepSurface.of_node(grid) == FootstepSurface.STONE)
	var north_walk := world.get_node("Level/RiverWalkways/NorthWalkway")
	check("river walkway footstep surface is WOOD", FootstepSurface.of_node(north_walk) == FootstepSurface.WOOD)


func _verify_navmesh() -> void:
	check("nav connected within Causeway", nav_connected(w(0, 4, -1), w(0, -6, -1)))
	check("nav disconnected across Bridge 1 gap", not nav_connected(w(0, -6, -1), w(0, -11, -1)))
	check("nav connected within Courtyard", nav_connected(w(0, -11, -1), w(0, -22, -1)))
	check("nav disconnected across Archer moat", not nav_connected(w(0, -23, -1), w(0, -25, -1)))
	check("nav connected around Lattice wells", nav_connected(w(26, -24, -1), w(26, -37, -1)))
	check("nav connected within Ziggurat Arena", nav_connected(w(0, -40, -1), w(0, -50, -1)))
	check("nav disconnected across West Shrine moat", not nav_connected(w(-5, -45, -1), w(-7, -45, -1)))


func _test_section_1_causeway() -> void:
	await shot("01_causeway_start.png")
	var guards := group_enemies("Enemies/CausewayGuard")
	check("Section 1 starts with 9 idle skeletons", guards.size() == 9, str(guards.size()))
	check("Bridge 1 starts submerged", bridge_body_y("BridgePlatform1") < -1.5)

	# Align carriers so the left-offset bow (+0.9 m) shoots straight down the centre skeleton column at world(0, cz).x.
	var col_x := w(0, 0).x + SiegeBowSpecifics.SIDE_OFFSET
	place_pair(Vector3(col_x, 0.0, w(0, 0).z), Vector3(col_x, 0.0, w(0, 0).z + 2.7))
	await wait(0.35)
	await hold([action(shooter, "down"), action(setter, "up")], 1.05)
	await wait(0.2)
	var full_draw := specifics.get_draw(gap())
	check("real-input draw reaches full power", full_draw >= 0.88, "gap=%.2f draw=%.2f" % [gap(), full_draw])
	await shot("01_causeway_drawn.png")

	await press_action(shooter.action_shoot)
	await wait(0.9)
	var after_pierce := group_enemies("Enemies/CausewayGuard").size()
	check("single full-draw arrow pierces and kills entire 3-skeleton column", after_pierce == 6, "remaining=%d shots=%s" % [after_pierce, str(shots)])
	check("hitting enemies charged SHOCKWAVE", bool(specifics.get("_is_shockwave_ready")))

	# Step back together with real input to verify renocking.
	await hold([action(shooter, "up"), action(setter, "down")], 1.1)
	await wait(0.25)
	check("stepping together renocks next arrow", bool(specifics.get("_is_nocked")), "gap=%.2f" % gap())

	kill_group("Enemies/CausewayGuard")
	var opened := await wait_until(func(): return bridge_body_y("BridgePlatform1") > 2.8 and state() == "playing" and not GameplayInput.is_locked(), 12.0)
	check("clearing CausewayGuard sets Checkpoint2 and raises Bridge 1", opened and current_cp() == "Checkpoint2", current_cp())
	await shot("01_bridge1_open.png")


func _test_section_2_courtyard() -> void:
	place_pair(w(0, -14), w(0, -13))
	var triggered := await wait_until(func(): return focal_count() == 4 and group_enemies("Enemies/CourtyardArchers").size() == 4, 6.0)
	check("CourtyardTrigger wakes 4 crossbowmen + 6 orc raiders & frames camera", triggered and group_enemies("Enemies/CourtyardRaiders").size() == 6)
	await wait(1.7)
	var all_sec2 := group_enemies("Enemies/CourtyardArchers") + group_enemies("Enemies/CourtyardRaiders")
	check_view("Section 2 Courtyard framing (crossbow wall + raiders)", all_sec2, 40.0)
	await shot("02_courtyard_fight.png")

	# Test real-input SHOCKWAVE on a nearby orc raider once its spawn-in finishes.
	refresh_carriers()
	var raider := group_enemies("Enemies/CourtyardRaiders")[0] as EnemyLocal
	raider.global_position = setter.global_position + Vector3(1.5, 0.0, -0.5)
	await get_tree().physics_frame
	var hp_before := (raider.get_node("Health") as Health).current_hp
	await press_action(setter.action_shoot)
	await wait(0.3)
	var hp_after := (raider.get_node("Health") as Health).current_hp if is_instance_valid(raider) else 0
	check("front carrier SHOCKWAVE damages chaser", hp_after < hp_before, "%d -> %d" % [hp_before, hp_after])

	# Mid-fight checkpoint respawn test.
	await do_respawn()
	check("respawn restores Checkpoint2 & clears courtyard focus", current_cp() == "Checkpoint2" and focal_count() == 0)
	check("respawn keeps Bridge 1 raised", bridge_body_y("BridgePlatform1") > 2.8)

	# Re-enter Courtyard and clear both groups.
	place_pair(w(0, -14), w(0, -13))
	await wait_until(func(): return group_enemies("Enemies/CourtyardArchers").size() == 4, 6.0)
	kill_group("Enemies/CourtyardArchers")
	kill_group("Enemies/CourtyardRaiders")
	var opened := await wait_until(func(): return bridge_body_y("BridgePlatform7") > 2.8 and not GameplayInput.is_locked(), 12.0)
	check("CourtyardCleared unfocuses camera, sets Checkpoint3, raises Bridge 2", opened and current_cp() == "Checkpoint3" and focal_count() == 0)
	await shot("02_bridge2_open.png")


func _test_section_3_river_walkways() -> void:
	check("SplitBridgeNorth starts raised", bridge_body_y("SplitBridgeNorth") > 2.8)
	check("SplitBridgeSouth starts raised", bridge_body_y("SplitBridgeSouth") > 2.8)

	place_pair(w(10.5, -17), w(9.5, -17))
	var woke := await wait_until(func(): return focal_count() == 4 and group_enemies("Enemies/RiverIdolMages").size() == 4, 6.0)
	check("RiverWestTrigger wakes 4 Idol Shamans and frames river", woke)
	await wait(1.2)
	check_view("Section 3 River framing", group_enemies("Enemies/RiverIdolMages"), 20.0)
	await shot("03_river_start.png")

	# Split the carriers onto the parallel walkways so each SinglePlayerAreaTrigger sinks its entry platform.
	var center_z := w(15, -17).z
	var walk_x := w(15, -17).x
	place_pair(Vector3(walk_x, 0.0, center_z - 1.65), Vector3(walk_x, 0.0, center_z + 1.65))
	var sank := await wait_until(func(): return bridge_body_y("SplitBridgeNorth") < -1.5 and bridge_body_y("SplitBridgeSouth") < -1.5, 6.0)
	check("stepping onto parallel walkways sinks both entry platforms", sank)
	await shot("03_river_split_walkways.png")

	# Verify respawning at Checkpoint3 restores both start-up split platforms AND spawns bow facing East!
	await do_respawn()
	check("Checkpoint3 respawn restores SplitBridgeNorth & South up", bridge_body_y("SplitBridgeNorth") > 2.8 and bridge_body_y("SplitBridgeSouth") > 2.8)
	check("Checkpoint3 spawns Siege Bow facing East (+x)", specifics.global_basis.z.x > 0.9, str(specifics.global_basis.z))

	# Re-enter River section, move onto East River pad, and clear Idol Shamans.
	place_pair(w(10.5, -17), w(9.5, -17))
	await wait_until(func(): return group_enemies("Enemies/RiverIdolMages").size() == 4, 6.0)
	place_pair(w(25, -17), w(24, -17))
	await wait(0.4)
	kill_group("Enemies/RiverIdolMages")
	var opened := await wait_until(func(): return bridge_body_y("BridgePlatform13") > 2.8 and not GameplayInput.is_locked(), 12.0)
	check("RiverCleared unfocuses camera, sets Checkpoint4, raises Bridge 3", opened and current_cp() == "Checkpoint4" and focal_count() == 0)


func _test_section_4_lattice_shrine() -> void:
	place_pair(w(26, -27), w(26, -26))
	var woke := await wait_until(func(): return group_enemies("Enemies/LatticeMages").size() == 5 and group_enemies("Enemies/LatticeSkulls").size() == 5, 6.0)
	check("LatticeTrigger spawns 5 shamans + 5 flying skulls at normal zoom", woke and focal_count() == 0)
	await wait(1.0)
	check_view("Section 4 Lattice Shrine", group_enemies("Enemies/LatticeMages") + group_enemies("Enemies/LatticeSkulls"), 16.0)
	await shot("04_lattice_shrine.png")

	kill_group("Enemies/LatticeMages")
	kill_group("Enemies/LatticeSkulls")
	var opened := await wait_until(func(): return bridge_body_y("BridgePlatform19") > 2.8 and not GameplayInput.is_locked(), 12.0)
	check("LatticeCleared sets Checkpoint5 and raises Bridge 4", opened and current_cp() == "Checkpoint5")


func _test_section_5_trap_chamber() -> void:
	var trap := world.get_node("Level/SpikeTrap") as SpikeTrap
	check("SpikeTrap starts WAITING", trap.state == SpikeTrap.State.WAITING)

	# Enter TrapTrigger without standing on the plates first.
	place_pair(w(14.6, -33), w(15.5, -33))
	var started := await wait_until(func(): return trap.state == SpikeTrap.State.CLOSING, 6.0)
	check("TrapTrigger starts closing SpikeTrap", started)
	await wait(0.3)
	check("0 plates held -> full close_speed", is_equal_approx(trap.current_speed(), trap.close_speed), "%.2f" % trap.current_speed())

	# Hold 1 plate, then both plates (3.0 m apart along x).
	var tx := w(13, -33).x
	var tz := w(13, -33).z
	place_pair(Vector3(tx - 1.5, 0.0, tz), Vector3(tx + 3.2, 0.0, tz))
	await wait(0.25)
	check("1 plate held -> slowed_speed", is_equal_approx(trap.current_speed(), trap.slowed_speed), "%.2f" % trap.current_speed())

	place_pair(Vector3(tx - 1.5, 0.0, tz), Vector3(tx + 1.5, 0.0, tz))
	await wait(0.6)
	check("both plates held -> walls stop (speed 0)", is_equal_approx(trap.current_speed(), 0.0), "%.2f" % trap.current_speed())
	await wait_until(func(): return group_enemies("Enemies/SurvivalEnemyGroup").size() > 0, 6.0)
	await shot("05_trap_chamber.png")

	# Fast-forward the timed survival group cleanly and defeat remaining orcs.
	var surv := world.get_node("Enemies/SurvivalEnemyGroup") as SurvivalEnemyGroup
	surv.set("_fight_elapsed", surv.fight_duration)
	kill_group("Enemies/SurvivalEnemyGroup")
	var opened := await wait_until(func(): return bridge_body_y("BridgePlatform25") > 2.8 and not GameplayInput.is_locked(), 12.0)
	check("TrapCleared retracts SpikeTrap and raises Bridge 5", opened and trap.state != SpikeTrap.State.CLOSING)


func _test_section_6_ziggurat_finale() -> void:
	# Cross Bridge 5 onto Ziggurat Approach to set Checkpoint6 while ArenaGate (Bridge 6) stands raised ahead.
	check("ArenaGate (Bridge 6) starts raised", bridge_body_y("BridgePlatform31") > 2.8)
	place_pair(w(1, -33), w(2, -33))
	var cp6_set := await wait_until(func(): return current_cp() == "Checkpoint6", 5.0)
	check("ApproachTrigger sets Checkpoint6 and closes Bridge 5", cp6_set)
	await shot("06_ziggurat_approach.png")

	# Cross ArenaGate into the Grand Ziggurat Arena.
	place_pair(w(0, -43), w(0, -42))
	var finale_on := await wait_until(func(): return focal_count() == 4 and group_enemies("Enemies/ZigguratShrineArchers").size() == 6, 6.0)
	var gate_sunk := await wait_until(func(): return bridge_body_y("BridgePlatform31") < -1.0, 6.0)
	check("ZigguratArenaTrigger sinks ArenaGate, frames arena, spawns 6 shrine defenders", finale_on and gate_sunk)
	await wait_until(func(): return group_enemies("Enemies/ZigguratHorde").size() >= 2, 6.0)
	await wait(1.2)
	check_view("Section 6 Grand Ziggurat Finale", group_enemies("Enemies/ZigguratShrineArchers") + group_enemies("Enemies/ZigguratHorde"), 22.0)
	await shot("06_ziggurat_finale.png")

	# Test finale checkpoint respawn -> restores Checkpoint6 & raises ArenaGate back up!
	await do_respawn()
	check("finale respawn returns to Checkpoint6 with ArenaGate raised", current_cp() == "Checkpoint6" and bridge_body_y("BridgePlatform31") > 2.8)

	# Re-enter Ziggurat Arena and win the finale!
	place_pair(w(0, -43), w(0, -42))
	await wait_until(func(): return group_enemies("Enemies/ZigguratShrineArchers").size() == 6, 6.0)
	await wait_until(func(): return group_enemies("Enemies/ZigguratHorde").size() >= 1, 6.0)
	kill_group("Enemies/ZigguratShrineArchers")
	await wait(0.3)
	kill_group("Enemies/ZigguratHorde")
	var opened := await wait_until(func(): return bridge_body_y("BridgePlatform37") > 2.8 and not GameplayInput.is_locked(), 12.0)
	check("ZigguratCleared stops horde, unfocuses camera, sets Checkpoint7, raises Bridge 7", opened and current_cp() == "Checkpoint7" and focal_count() == 0)

	# Cross Bridge 7 through SanctuaryRevealTrigger onto Sanctuary so the camera reveals the full Grand Ziggurat.
	place_pair(w(0, -53.4), w(0, -52.6))
	var revealed := await wait_until(func(): return focal_count() == 4, 4.0)
	check("SanctuaryRevealTrigger frames the Grand Ziggurat monument", revealed)
	place_pair(w(0, -54.2), w(0, -53.3))
	await wait(1.6)
	var portal := world.get_node("Level/Monuments/GrandZiggurat/PortalGlow") as Node3D
	check("Grand Ziggurat upper portal is visible on screen", visible_count([portal]) == 1)
	await shot("07_sanctuary_victory.png")

	place_pair(w(0, -55.8), w(0, -55.1))
	var won := await wait_until(func(): return not is_instance_valid(world) or get_tree().current_scene != world or state() == "levelfinished", 8.0)
	check("stepping into EndLevelArea wins the level (LevelFinished)", won, state())
