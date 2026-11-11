extends Node
## Test driver for the Siege Bow in world_local_siege_bow.tscn.
## Run through godot.sh, see docs/level-creation-for-agents.md.
## Uses real input where it matters. Save tracking is disabled, so save.json stays untouched.

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
	get_tree().create_timer(240.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  [" + detail + "]"))
	if not ok:
		fails += 1


func w(cx: int, cz: int, y: float = 0.0) -> Vector3:
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


func protect_players() -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)


func place(a: Vector3, b: Vector3) -> void:
	var list := players()
	list[0].velocity = Vector3.ZERO
	list[1].velocity = Vector3.ZERO
	list[0].global_position = a
	list[1].global_position = b


func move_players(pos: Vector3) -> void:
	place(pos + Vector3(3, 0, 0), pos + Vector3(-3, 0, 0))


func gap() -> float:
	var l := players()
	return Vector2(l[0].global_position.x - l[1].global_position.x, l[0].global_position.z - l[1].global_position.z).length()


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame


func group_enemies(path: String) -> Array:
	return world.get_node(path).get_node("InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func kill_group(path: String) -> void:
	for e in group_enemies(path):
		Health.apply_damage(e, 9999, e.global_position)


func visible_count(enemies: Array) -> int:
	var cam := get_viewport().get_camera_3d()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var seen := 0
	for e in enemies:
		var pos: Vector3 = e.global_position + Vector3(0, 1, 0)
		if not cam.is_position_behind(pos) and rect.has_point(cam.unproject_position(pos)):
			seen += 1
	return seen


func check_all_visible(label: String, enemies: Array) -> void:
	var seen := visible_count(enemies)
	check(label, enemies.size() > 0 and seen == enemies.size(), "%d/%d, camera y=%.1f" % [seen, enemies.size(), get_viewport().get_camera_3d().global_position.y])


func _player_distance(enemy: EnemyLocal) -> float:
	var nearest := INF
	for p in players():
		var d: Vector3 = p.global_position - enemy.global_position
		nearest = minf(nearest, Vector2(d.x, d.z).length())
	return nearest


func _can_cast_at_a_player(enemy: EnemyLocal) -> bool:
	if not enemy.has_node("MageBehavior"):
		return false
	return _player_distance(enemy) <= enemy.get_node("MageBehavior").cast_max_distance


## Both players on screen, and every living enemy within reach of them too.
func check_view(label: String, enemies: Array, reach: float = 14.0) -> void:
	var players_seen := visible_count(players())
	var near := enemies.filter(func(e): return is_instance_valid(e) and e.is_alive() and _player_distance(e) <= reach)
	var near_seen := visible_count(near)
	check(label, players_seen == 2 and near_seen == near.size(), "players %d/2, enemies within %.0f m %d/%d, camera y=%.1f" % [players_seen, reach, near_seen, near.size(), get_viewport().get_camera_3d().global_position.y])


func check_mages_in_range(label: String) -> void:
	var in_range := group_enemies("Enemies/EnemyGroup4").filter(_can_cast_at_a_player)
	check(label, in_range.size() > 0 and visible_count(in_range) == in_range.size(), "%d/%d in range on screen" % [visible_count(in_range), in_range.size()])


var shots: Array = []
var finished: Array = []
var launch_tails: Array = []
var bow: Node3D
var specifics: SiegeBowSpecifics
var shooter: PlayerLocal
var setter: PlayerLocal


func action(player: PlayerLocal, suffix: String) -> String:
	return "p%s_%s" % [player.device_id, suffix]


func press_shoot() -> void:
	Input.action_press(shooter.action_shoot)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(shooter.action_shoot)
	await get_tree().physics_frame


func on_fired(arrow: SiegeArrow, draw: float, damage: int, pierce_hits: int, flight_range: float) -> void:
	launch_tails.append(arrow.global_position)
	shots.append({"draw": draw, "damage": damage, "pierce": pierce_hits, "range": flight_range})
	arrow.spent.connect(func(distance: float, hits: int): finished.append({"distance": distance, "hits": hits}))


func spawn_ahead(metres_from_grip: float) -> EnemyLocal:
	var enemy := (load("res://src/enemy/enemy_local.tscn") as PackedScene).instantiate() as EnemyLocal
	world.get_node("Enemies").add_child(enemy)
	var at: Vector3 = (specifics.get_node("Grip") as Node3D).global_position + specifics.global_basis.z.normalized() * metres_from_grip
	at.y = shooter.global_position.y
	enemy.global_position = at
	return enemy


func nocked_arrow() -> Node3D:
	return specifics.get_node("Grip/NockedArrow") as Node3D


## How far apart the arrow's tail and the back carrier are, along the flight line.
func tail_to_back_hand() -> float:
	var axis: Vector3 = specifics.global_basis.z.normalized()
	return absf((nocked_arrow().global_position - shooter.global_position).dot(axis))


func head_past_grip() -> float:
	var axis: Vector3 = specifics.global_basis.z.normalized()
	var head: Vector3 = nocked_arrow().to_global(Vector3(0, 0, -SiegeArrow.LENGTH))
	return (head - (specifics.get_node("Grip") as Node3D).global_position).dot(axis)


## Sideways distance from the front carrier to the arrow's flight line.
func arrow_clearance() -> float:
	var axis: Vector3 = specifics.global_basis.z.normalized()
	var offset: Vector3 = setter.global_position - (specifics.get_node("Grip") as Node3D).global_position
	offset.y = 0.0
	return (offset - axis * offset.dot(axis)).length()


## Angle between the carriers' line and the direction the arrow would fly.
func aim_error_degrees() -> float:
	var between: Vector3 = setter.global_position - shooter.global_position
	between.y = 0.0
	return rad_to_deg(between.angle_to(specifics.global_basis.z))


func hp(enemy: EnemyLocal) -> int:
	return (enemy.get_node("Health") as Health).current_hp if is_instance_valid(enemy) else 0


func draw_bow(seconds: float) -> void:
	await hold([action(shooter, "down"), action(setter, "up")], seconds)
	await wait(0.2)


func close_bow() -> void:
	await hold([action(shooter, "up"), action(setter, "down")], 1.0)
	await wait(0.2)


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	bow = world.get_node("Weapon/SiegeBow") as Node3D
	specifics = bow.get_node("WeaponSpecifics") as SiegeBowSpecifics
	specifics.fired.connect(on_fired)
	await wait(1.0)
	var carry: CarryInfo = (bow.get_node("PickAndDropHandler") as PickAndDropHandler).get_carry_info()
	check("both players carry the bow", is_instance_valid(carry.main_carrier) and is_instance_valid(carry.secondary_carrier))
	shooter = carry.main_carrier
	setter = carry.secondary_carrier
	var forward: Vector3 = specifics.global_basis.z
	print("INFO start gap=%.2f forward=%s shooter=%s setter=%s" % [gap(), forward, shooter.global_position, setter.global_position])
	check("the bow points at the arena ahead", forward.z < -0.9, str(forward))
	check("arrow clears the front carrier at rest", arrow_clearance() >= 0.8, "%.2f m" % arrow_clearance())
	check("aim follows the carriers' line at rest", aim_error_degrees() < 1.0, "%.2f deg" % aim_error_degrees())
	check("loaded arrow's tail is on the string at rest", tail_to_back_hand() < 0.2, "%.2f m" % tail_to_back_hand())
	check("loaded arrow sticks out past the grip at rest", head_past_grip() > 5.0, "%.2f m" % head_past_grip())
	await shot("bow_rest.png")

	await press_shoot()
	check("an undrawn bow doesn't fire", shots.is_empty(), str(shots))

	await draw_bow(1.0)
	var full_gap := gap()
	check("drawing reaches a near-full draw", specifics.get_draw(full_gap) >= 0.9, "gap=%.2f draw=%.2f" % [full_gap, specifics.get_draw(full_gap)])
	check("front carrier stays ahead of the back carrier", specifics.global_basis.z.dot(forward) > 0.98)
	check("arrow clears the front carrier at full draw", arrow_clearance() >= 0.8, "%.2f m" % arrow_clearance())
	check("drawing doesn't swing the aim", aim_error_degrees() < 1.0, "%.2f deg" % aim_error_degrees())
	await wait(0.3)
	check("loaded arrow keeps its length at full draw", nocked_arrow().scale.is_equal_approx(Vector3.ONE), str(nocked_arrow().scale))
	check("loaded arrow's tail follows the string at full draw", tail_to_back_hand() < 0.2, "%.2f m" % tail_to_back_hand())
	check("head has slid back near the grip at full draw", head_past_grip() < 1.5 and head_past_grip() > -0.5, "%.2f m" % head_past_grip())
	await wait(0.5)
	await shot("bow_drawn.png")
	var cam := get_viewport().get_camera_3d()
	check("both carriers on screen at full draw", visible_count(players()) == 2, "%d/2" % visible_count(players()))
	var ahead := (specifics.get_node("Grip") as Node3D).global_position + specifics.global_basis.z.normalized() * 6.0
	var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	check("6 m past the grip is on screen", view.has_point(cam.unproject_position(ahead)))

	var line: Array = []
	for i in 5:
		line.append(spawn_ahead(2.5 + i * 1.2))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var tail_before: Vector3 = nocked_arrow().global_position
	await press_shoot()
	check("full draw fires one arrow", shots.size() == 1, str(shots))
	check("the arrow launches from where it sat on the string", launch_tails.size() == 1 and launch_tails[0].distance_to(tail_before) < 0.3, "%s vs %s" % [launch_tails, tail_before])
	check("the string leaves the back carrier's hand on release", not specifics.get_node("Grip/HandleBack").visible)
	check("the loaded arrow is gone on release", not nocked_arrow().visible)
	await wait(0.1)
	await shot("bow_flight.png")
	await wait(0.4)
	var tip_z: float = specifics._limb_tip(specifics._get_limb_angle(), 1.0).z
	check("the string has snapped forward to the bow tips", absf(specifics._string_z - tip_z) < 0.2, "string %.2f tip %.2f" % [specifics._string_z, tip_z])
	check("the limbs have sprung back", absf(specifics._limb_flex) < 0.15, "flex %.2f" % specifics._limb_flex)
	await shot("bow_released.png")
	await wait(1.0)
	print("INFO full-draw shot=%s finished=%s" % [shots, finished])
	var alive_hp := line.map(func(e): return hp(e))
	print("INFO line hp=%s" % [alive_hp])
	check("full draw deals max damage", shots.size() > 0 and shots[0].damage == 3, str(shots))
	check("arrow pierces four enemies in a line", finished.size() == 1 and finished[0].hits == 4, str(finished))
	check("the fifth enemy in line is untouched", alive_hp.count(3) == 1 and alive_hp.count(0) == 4, str(alive_hp))
	for e in line:
		if is_instance_valid(e):
			Health.apply_damage(e, 999, e.global_position)

	shots.clear()
	await press_shoot()
	check("no second arrow before renocking", shots.is_empty(), str(shots))
	check("bow is empty after firing", not specifics.is_nocked())

	var max_gap: float = (bow.get_node("WeaponMovement") as WeaponMovement).max_carrier_distance
	await draw_bow(2.0)
	check("an empty bow lets the carriers walk past the distance limit", gap() > max_gap + 2.0, "gap=%.2f max=%.2f" % [gap(), max_gap])
	await shot("bow_empty_apart.png")
	for i in 6:
		if specifics.is_nocked():
			break
		await close_bow()
	check("coming back together nocks a new arrow", specifics.is_nocked(), "gap=%.2f" % gap())
	check("the string is back in the carrier's hand after reloading", tail_to_back_hand() < 0.2 and specifics.get_node("Grip/HandleBack").visible, "%.2f m" % tail_to_back_hand())
	await draw_bow(2.0)
	check("a loaded bow holds the distance limit again", gap() <= max_gap + 0.1, "gap=%.2f max=%.2f" % [gap(), max_gap])
	await close_bow()
	await close_bow()

	await draw_bow(0.3)
	var mid_draw := specifics.get_draw(gap())
	finished.clear()
	var on_carrier_line := spawn_ahead(3.0)
	on_carrier_line.global_position -= specifics.global_basis.x.normalized() * SiegeBowSpecifics.SIDE_OFFSET
	var close_ahead := spawn_ahead(1.5)
	var between_carriers := spawn_ahead(-1.5)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await press_shoot()
	print("INFO partial shot draw=%.2f %s" % [mid_draw, shots])
	check("a partial draw fires", shots.size() == 1, "draw=%.2f" % mid_draw)
	check("a partial draw is weaker than a full draw", shots.size() > 0 and shots[0].damage < 3 and shots[0].pierce < 4 and shots[0].range < 20.0, str(shots))
	await wait(1.6)
	print("INFO partial flight %s" % [finished])
	print("INFO enemy straight ahead of the carriers ends with hp=%d" % hp(on_carrier_line))
	check("a close enemy ahead of the bow is hit despite the long arrow", hp(close_ahead) < 3, "hp %d" % hp(close_ahead))
	check("an enemy behind the bow isn't hit by the shaft", hp(between_carriers) == 3, "hp %d" % hp(between_carriers))
	for leftover in [on_carrier_line, close_ahead, between_carriers]:
		if is_instance_valid(leftover):
			Health.apply_damage(leftover, 999, leftover.global_position)
	check("arrow stops at its range", finished.size() == 1 and absf(finished[0].distance - shots[0].range) < 1.0, "%s vs %s" % [finished, shots])

	await close_bow()
	await draw_bow(0.6)
	shots.clear()
	setter.carrying_weapon_data.can_carry_status = CarryingWeaponData.CanCarryStatus.NO_WEAPON_AVAILABLE
	await wait(0.2)
	await press_shoot()
	check("no firing with a single carrier", shots.is_empty(), str(shots))
	await shot("bow_solo.png")

	print("RESULT fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
