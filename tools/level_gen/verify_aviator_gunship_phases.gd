extends "res://tools/level_gen/verify_aviator_gunship_boss.gd"
## Test driver for the gunship's phases 2 and 3, in world_local_aviator_gunship_boss.tscn. Run through godot.sh.
## Phase 2: rockets knock plates out of the deck and they come back; a strafing run marks a lane, crosses to the
## opposite edge and hits carriers in it. Phase 3: the arena crumbles, the carriers walk the twin fragile tracks
## with real input to two platforms, the gunship escorts them, platforms crumble, a death respawns at the phase
## three checkpoint and the gunship wakes at 30%.


func deck() -> BreakableDeck:
	return BreakableDeck.find(get_tree())


func course() -> GunshipCourse:
	return GunshipCourse.find(get_tree())


func hp_to(ratio: float) -> void:
	var target := int(floor(BOSS_HP * ratio))
	Health.apply_damage(boss(), boss_hp() - target, boss().global_position)


func machine_state(state_name: String) -> bool:
	return boss() != null and boss().enemy_state_machine.is_in_state(state_name)


# ---- Phase 2. ----

func check_phase_two() -> void:
	hp_to(0.64)
	await wait(0.3)
	check("below 65% it enters phase 2", brain().phase() == 2, "phase %d" % brain().phase())
	# Rockets: the carriers stand still, so the rockets beyond one each land on open deck and break it.
	place_pair(brain().arena_center + Vector3(0, 0, 4), Vector3.BACK)
	# A rocket that lands on a carrier's plate spares it, so give it up to two salvos.
	var fallen := [0]
	var count_fall := func(_cell: Vector2i): fallen[0] += 1
	deck().cell_fell.connect(count_fall)
	var saw_rockets := await wait_for_move(AviatorGunshipBehavior.MOVE_ROCKETS, 15.0)
	await wait(2.6)
	await shot("phase2_rocket_holes.png")
	if fallen[0] == 0:
		await wait_for_move(AviatorGunshipBehavior.MOVE_ROCKETS, 12.0)
		await wait(2.6)
	deck().cell_fell.disconnect(count_fall)
	check("phase 2 rockets knock plates out of the deck", saw_rockets and fallen[0] >= 1, "%d plates fell" % fallen[0])
	var refilled := await wait_until(func(): return deck().hole_count() == 0, 12.0)
	check("the holes fill back in", refilled, "%d left" % deck().hole_count())

	# Strafing run: always strafe, switch sides soon.
	var b := brain()
	b.strafe_chance = 1.0
	b.side_seconds_min = 2.0
	b.side_seconds_max = 2.5
	b.finish_relocation()
	var side_before := b.side
	var strafing := await wait_until(func(): return machine_state("strafing"), 20.0)
	check("phase 2 switches sides with a strafing run", strafing)
	if not strafing:
		return
	var state := boss().enemy_state_machine.get_node("Strafing")
	var lane := boss().get_node("StrafeLane") as Node3D
	check("the lane shows before the run", lane.visible)
	var from: Vector3 = state.get("_from")
	var to: Vector3 = state.get("_to")
	var middle := (from + to) * 0.5
	var across := (to - from).normalized().cross(Vector3.UP)
	place_pair(Vector3(middle.x, brain().arena_center.y, middle.z), across.normalized())
	await wait(0.4)
	await shot("phase2_strafe_lane.png")
	var hp_before := total_player_hp()
	await wait_until(func(): return state.call("is_dashing"), 2.0)
	protect(false)
	await wait_until(func(): return not machine_state("strafing"), 4.0)
	protect(true)
	check("the run hits carriers in the lane", total_player_hp() <= hp_before - 3, "hp %d -> %d" % [hp_before, total_player_hp()])
	check("it ends on the opposite edge", b.side == (side_before + 2) % 4 and flat_distance(boss().global_position, b.station_point(b.current_lateral())) < 2.0,
		"side %d -> %d" % [side_before, b.side])
	b.side_seconds_min = 999.0
	b.side_seconds_max = 999.0
	b.finish_relocation()


# ---- Phase 3. ----

func check_phase_three_start() -> void:
	# The arena crumbles west to east: wait by its east edge, where the tracks leave and the last columns fall.
	place_pair(brain().arena_center + Vector3(7.5, 0, 0), Vector3.BACK)
	hp_to(0.29)
	await wait(0.5)
	var c := course()
	check("below 30% it enters phase 3 and the course starts", brain().phase() == 3 and c.is_active())
	var manager := world.checkpoint_manager as CheckpointManager
	check("phase 3 sets its checkpoint", manager.current_checkpoint.name == "PhaseThreeCheckpoint", manager.current_checkpoint.name)
	await wait(1.0)
	check("the first track and platform appear", c.section_count() == 2, "%d sections" % c.section_count())
	var tiles := c.get_children().filter(func(n): return n is FragileTile)
	check("the tracks are made of fragile tiles", tiles.size() > 40, "%d tiles" % tiles.size())
	var crumbling := await wait_until(func(): return deck().hole_count() >= 7, 8.0)
	await shot("phase3_arena_crumbling.png")
	check("the arena crumbles", crumbling, "%d holes" % deck().hole_count())


## Walks the carriers along section `index`'s tracks with real input, one per track, until both stand on its platform.
func walk_section(index: int) -> Dictionary:
	var lines := course().track_lines(index)
	var north: PackedVector3Array = lines["north"]
	var south: PackedVector3Array = lines["south"]
	var list := players()
	var start_n := north[0] + Vector3(-1.0, 0.0, 0.0)
	var start_s := south[0] + Vector3(-1.0, 0.0, 0.0)
	list[0].global_position = start_n + Vector3.UP * 0.2
	list[1].global_position = start_s + Vector3.UP * 0.2
	list[0].velocity = Vector3.ZERO
	list[1].velocity = Vector3.ZERO
	await wait(0.3)
	var escort_seen := [false]
	var on_screen_count := [0, 0]
	var watch_escort := func():
		if boss() == null:
			return
		if brain().escorting:
			escort_seen[0] = true
			on_screen_count[1] += 1
			if on_screen(boss().global_position):
				on_screen_count[0] += 1
	get_tree().physics_frame.connect(watch_escort)
	var stats := await drive_tracks(north, south, lines["centre"], func(): return course().platforms_reached() >= index, 40.0)
	get_tree().physics_frame.disconnect(watch_escort)
	stats["escort"] = escort_seen[0]
	stats["escort_on_screen"] = "%d of %d frames" % on_screen_count
	return stats


func check_tracks() -> void:
	get_tree().create_timer(4.0).timeout.connect(func(): shot("phase3_on_tracks.png"))
	var stats := await walk_section(1)
	check("real input walks the twin tracks to platform 1", stats["done"] and state() == "playing", str(stats))
	check("the gunship escorts the carriers on the tracks", stats["escort"], stats["escort_on_screen"])
	var lit := course().get_children().filter(func(n): return n is FragileTile and n.is_lit()).size()
	check("tiles they walked on fall away", lit > 10, "%d lit or falling" % lit)
	check("landing builds the next track and platform", course().section_count() == 3, "%d sections" % course().section_count())
	await wait(1.5)
	check("over the platform it holds the platform's sides", not brain().escorting)
	await shot("phase3_platform_1.png")
	var stats2 := await walk_section(2)
	check("and on to platform 2", stats2["done"] and state() == "playing", str(stats2))


func check_platform_crumbles_and_respawn() -> void:
	var c := course()
	var lost := await wait_until(func(): return state() == "gameoverlost", 25.0)
	check("standing on a platform 15 s drops the carriers when it crumbles", lost, state())
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	var manager := world.checkpoint_manager as CheckpointManager
	check("respawn at the phase three checkpoint", manager.current_checkpoint.name == "PhaseThreeCheckpoint")
	check("the deck is whole again and the course cleared", deck().hole_count() == 0 and not c.is_active() and c.section_count() == 0,
		"holes %d, sections %d" % [deck().hole_count(), c.section_count()])
	toughen_players(TOUGH_HP)
	protect(true)
	await enter_arena()
	await wait_until(func(): return boss().is_offensive, 3.0)
	await wait(0.5)
	check("the gunship wakes straight into phase 3 at 30%", brain().phase() == 3 and boss_hp() <= int(ceil(BOSS_HP * 0.3)) and c.is_active(),
		"phase %d hp %d" % [brain().phase(), boss_hp()])


func _run() -> void:
	var ok := await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	toughen_players(TOUGH_HP)
	protect(true)
	brain().side_seconds_min = 999.0
	brain().side_seconds_max = 999.0
	await enter_arena()
	await wait_until(func(): return boss().is_offensive, 3.0)
	await check_phase_two()
	await check_phase_three_start()
	await check_tracks()
	await check_platform_crumbles_and_respawn()
	Health.apply_damage(boss(), 999, boss().global_position)
	var won := await wait_until(func(): return state() == "levelfinished", 10.0)
	check("downing the gunship in phase 3 finishes the level", won, state())
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


# ---- Track driving, from verify_storm_isles.gd. ----

func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func closest_on_line(p: Vector2, line: PackedVector3Array) -> Array:
	var best := INF
	var best_s := 0.0
	var best_point := Vector2.ZERO
	var walked := 0.0
	for i in line.size() - 1:
		var a := flat(line[i])
		var b := flat(line[i + 1])
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, INF if i == line.size() - 2 else 1.0)
		var q := a.lerp(b, t)
		if p.distance_to(q) < best:
			best = p.distance_to(q)
			best_s = walked + a.distance_to(b) * t
			best_point = q
		walked += a.distance_to(b)
	return [best_s, best_point]


func point_along(line: PackedVector3Array, distance: float) -> Vector2:
	for i in line.size() - 1:
		var a := flat(line[i])
		var b := flat(line[i + 1])
		if distance <= a.distance_to(b) or i == line.size() - 2:
			return a + (b - a).normalized() * distance
		distance -= a.distance_to(b)
	return flat(line[line.size() - 1])


func line_length(line: PackedVector3Array) -> float:
	var total := 0.0
	for i in line.size() - 1:
		total += flat(line[i]).distance_to(flat(line[i + 1]))
	return total


## Steers each carrier along its own track with real input: aims 1.8 m ahead on its line and presses the nearest of
## the eight directions. A carrier more than a metre ahead of the other, along the centre line, waits.
func drive_tracks(north_line: PackedVector3Array, south_line: PackedVector3Array, centre_line: PackedVector3Array, done: Callable, timeout: float) -> Dictionary:
	var list := players()
	var north: PlayerLocal = list[0] if list[0].global_position.z < list[1].global_position.z else list[1]
	var south: PlayerLocal = list[1] if north == list[0] else list[0]
	var lines := {north: north_line, south: south_line}
	var finish := line_length(centre_line) + 2.5
	var stats := {"done": false, "seconds": 0.0, "min_gap": INF, "max_gap": 0.0}
	var started := Time.get_ticks_msec()
	var deadline := started + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if state() != "playing":
			break
		if done.call():
			stats["done"] = true
			break
		var progress := {}
		for p in [north, south]:
			progress[p] = closest_on_line(flat(p.global_position), centre_line)[0]
		var gap := flat(north.global_position).distance_to(flat(south.global_position))
		stats["min_gap"] = minf(stats["min_gap"], gap)
		stats["max_gap"] = maxf(stats["max_gap"], gap)
		for p in [north, south]:
			var other: PlayerLocal = south if p == north else north
			var on_line: Array = closest_on_line(flat(p.global_position), lines[p])
			var waiting: bool = progress[p] - progress[other] > 1.0
			var aim := point_along(lines[p], minf(on_line[0] + 1.8, finish)) - flat(p.global_position)
			_steer(p, Vector2.ZERO if waiting else aim.normalized())
	for p in [north, south]:
		_steer(p, Vector2.ZERO)
	stats["seconds"] = (Time.get_ticks_msec() - started) / 1000.0
	return stats


## Presses the directions nearest to `dir` (x east, y south): one or two of the four, or none.
func _steer(p: PlayerLocal, dir: Vector2) -> void:
	for pair in [[p.action_right, dir.x > 0.38], [p.action_left, dir.x < -0.38], [p.action_down, dir.y > 0.38], [p.action_up, dir.y < -0.38]]:
		if pair[1]:
			Input.action_press(pair[0])
			continue
		Input.action_release(pair[0])
