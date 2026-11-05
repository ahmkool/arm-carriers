extends Node
## Test driver for the shears in world_local_shears.tscn.
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


## Enemies stay in their Spawning state this long before they start chasing.
const SPAWN_APPEAR_SEC := 2.3
var snaps: Array = []
var shears: Node3D
var specifics: Node3D
var handler: PickAndDropHandler


func action(player: PlayerLocal, suffix: String) -> String:
	return "p%s_%s" % [player.device_id, suffix]


func spawn_enemy(local_to_hinge: Vector3) -> EnemyLocal:
	var enemy := (load("res://src/enemy/enemy_local.tscn") as PackedScene).instantiate() as EnemyLocal
	world.get_node("Enemies").add_child(enemy)
	var rig := specifics.get_node("Rig") as Node3D
	var at := rig.to_global(local_to_hinge)
	at.y = players()[0].global_position.y
	enemy.global_position = at
	return enemy


func hp(enemy: EnemyLocal) -> int:
	return (enemy.get_node("Health") as Health).current_hp if is_instance_valid(enemy) else 0


func open_fully(shooter: PlayerLocal, setter: PlayerLocal) -> void:
	await hold([action(shooter, "left"), action(setter, "right")], 1.2)
	await wait(0.2)


func _in_reach_between_blades(enemy: EnemyLocal) -> bool:
	var local := (specifics.get_node("Rig") as Node3D).to_local(enemy.global_position)
	return local.x > 0.0 and Vector2(local.x, local.z).length() <= 5.5 and past_blade(enemy) < 0.3


func _print_horde(horde: Array, label: String) -> void:
	for enemy in horde:
		var local := (specifics.get_node("Rig") as Node3D).to_local(enemy.global_position)
		print("INFO horde %s: hinge x=%.1f z=%.1f past=%.2f nearest player=%.2f state=%s" % [label, local.x, local.z, past_blade(enemy), _player_distance(enemy), enemy.get_node("EnemyStateMachine").current_state.name])


func spawn_chaser(local_to_hinge: Vector3) -> EnemyLocal:
	var enemy := spawn_enemy(local_to_hinge)
	enemy.is_offensive = true
	return enemy


## Positive when the enemy's centre is outside the blade line at its distance from the hinge.
func past_blade(enemy: EnemyLocal) -> float:
	var rig := specifics.get_node("Rig") as Node3D
	var local := rig.to_local(enemy.global_position)
	return absf(local.z) - maxf(local.x, 0.0) * tan(specifics._half_angle)


func kill_all(enemies: Array) -> void:
	for enemy in enemies:
		if is_instance_valid(enemy):
			Health.apply_damage(enemy, 999, enemy.global_position)


func _test_blade_collision(shooter: PlayerLocal, setter: PlayerLocal) -> void:
	await open_fully(shooter, setter)
	var trapped := spawn_chaser(Vector3(3.5, 0, 1.2))
	await wait(SPAWN_APPEAR_SEC)
	var worst := -INF
	var moved := 0.0
	var start := trapped.global_position
	for _i in 240:
		await get_tree().physics_frame
		worst = maxf(worst, past_blade(trapped))
		moved = maxf(moved, trapped.global_position.distance_to(start))
	print("INFO trapped enemy: worst past blade=%.2f moved=%.2f speed=%.2f" % [worst, moved, trapped.velocity.length()])
	check("the test enemy really chases", moved > 0.3, "moved %.2f" % moved)
	check("enemy chasing a carrier can't walk through a blade", worst < 0.75, "worst %.2f" % worst)
	await shot("shears_trapped.png")
	kill_all([trapped])

	await hold([action(shooter, "right"), action(setter, "left")], 0.7)
	await wait(0.2)
	var outside := spawn_chaser(Vector3(3.0, 0, 1.3))
	await get_tree().physics_frame
	await wait(SPAWN_APPEAR_SEC)
	var side_before := signf((specifics.get_node("Rig") as Node3D).to_local(outside.global_position).z)
	await hold([action(shooter, "left"), action(setter, "right")], 1.0)
	var excess: float = past_blade(outside)
	var side_after := signf((specifics.get_node("Rig") as Node3D).to_local(outside.global_position).z)
	print("INFO swept enemy: past blade=%.2f side %d -> %d" % [excess, side_before, side_after])
	check("an opening blade pushes an enemy instead of passing through it", excess > 0.0 and side_before == side_after, "past %.2f" % excess)
	kill_all([outside])

	await wait(0.2)
	await open_fully(shooter, setter)
	var dashed := spawn_chaser(Vector3(4.0, 0, 1.0))
	await wait(SPAWN_APPEAR_SEC)
	snaps.clear()
	var furthest := [-INF]
	var watch := func():
		if is_instance_valid(dashed) and hp(dashed) > 0:
			furthest[0] = maxf(furthest[0], past_blade(dashed))
	get_tree().physics_frame.connect(watch)
	Input.action_press(action(shooter, "right"))
	Input.action_press(action(setter, "left"))
	await wait(0.05)
	Input.action_press(action(shooter, "dash"))
	Input.action_press(action(setter, "dash"))
	await wait(0.1)
	Input.action_release(action(shooter, "dash"))
	Input.action_release(action(setter, "dash"))
	await wait(0.5)
	Input.action_release(action(shooter, "right"))
	Input.action_release(action(setter, "left"))
	get_tree().physics_frame.disconnect(watch)
	print("INFO dash close: snaps=%s furthest past blade=%.2f gap=%.2f" % [snaps, furthest[0], gap()])
	check("a dash close cuts without the blade passing the enemy", snaps.size() == 1 and snaps[0][1] == 1 and furthest[0] < 0.75, "%s furthest %.2f" % [snaps, furthest[0]])
	kill_all([dashed])

	await open_fully(shooter, setter)
	var survivor := spawn_chaser(Vector3(3.0, 0, 0.0))
	await wait(SPAWN_APPEAR_SEC)
	snaps.clear()
	await hold([action(setter, "left")], 1.1)
	check("a survivor of a weak cut stays alive", hp(survivor) > 0, "hp %d %s" % [hp(survivor), snaps])
	var after_cut := survivor.global_position
	await wait(2.5)
	var walked := survivor.global_position.distance_to(after_cut)
	print("INFO survivor squeezed by shut blades walked %.2f m" % walked)
	check("a survivor squeezed by shut blades isn't stuck", hp(survivor) <= 0 or walked > 0.3, "walked %.2f" % walked)
	await shot("shears_survivor.png")
	kill_all([survivor])

	await open_fully(shooter, setter)
	var horde: Array = []
	for i in 6:
		horde.append(spawn_chaser(Vector3(6.3, 0, -2.5 + i)))
	await wait(SPAWN_APPEAR_SEC + 3.0)
	var inside := horde.filter(func(e): return _in_reach_between_blades(e))
	_print_horde(horde, "after 3 s")
	await wait(7.0)
	_print_horde(horde, "after 10 s")
	inside = horde.filter(func(e): return _in_reach_between_blades(e))
	print("INFO horde: %d of %d between the blades after 3 s" % [inside.size(), horde.size()])
	await shot("shears_funnel.png")
	snaps.clear()
	await hold([action(shooter, "right"), action(setter, "left")], 0.7)
	print("INFO horde snap: %s" % [snaps])
	check("a snap on the funnelled horde hits at least one enemy", snaps.size() == 1 and snaps[0][1] >= 1, str(snaps))
	await wait(0.3)
	await shot("shears_funnel_snap.png")
	kill_all(horde)
	await wait(0.2)


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	shears = world.get_node("Weapon/Shears") as Node3D
	specifics = shears.get_node("WeaponSpecifics") as Node3D
	handler = shears.get_node("PickAndDropHandler") as PickAndDropHandler
	specifics.snapped.connect(func(damage: int, hits: int): snaps.append([damage, hits]))
	await wait(0.5)
	await shot("shears_ground.png")

	var carry := handler.get_carry_info()
	check("both players carry the shears", is_instance_valid(carry.main_carrier) and is_instance_valid(carry.secondary_carrier))
	if not is_instance_valid(carry.main_carrier) or not is_instance_valid(carry.secondary_carrier):
		get_tree().quit(1)
		return
	var shooter := carry.main_carrier
	var setter := carry.secondary_carrier
	print("INFO start gap=%.2f shooter=%s forward=%s" % [gap(), shooter.global_position, shears.global_basis.x])

	await open_fully(shooter, setter)
	check("opens near the max carrier distance", gap() > 6.5, "gap=%.2f" % gap())
	check("blades open wide", rad_to_deg(specifics._half_angle) > 34.0, "half angle=%.1f" % rad_to_deg(specifics._half_angle))
	var armed_before: bool = specifics._is_armed
	check("armed when wide open", armed_before)
	await wait(0.8)
	var rig := specifics.get_node("Rig") as Node3D
	var cam := get_viewport().get_camera_3d()
	var tip_seen: bool = Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).has_point(cam.unproject_position(rig.to_global(Vector3(5.0, 0, 0))))
	check("hinge-side view keeps the blade tips on screen", tip_seen)
	await shot("shears_open.png")

	var in_a := spawn_enemy(Vector3(3.0, 0, 0.8))
	var in_b := spawn_enemy(Vector3(2.5, 0, -0.8))
	var out := spawn_enemy(Vector3(-4.0, 0, 0.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	snaps.clear()
	Input.action_press(action(shooter, "right"))
	Input.action_press(action(setter, "left"))
	await wait(0.2)
	await shot("shears_closing.png")
	await wait(0.5)
	Input.action_release(action(shooter, "right"))
	Input.action_release(action(setter, "left"))
	await shot("shears_snap.png")
	print("INFO two-player stroke snaps=%s gap=%.2f" % [snaps, gap()])
	check("two-player wide stroke snaps once", snaps.size() == 1, str(snaps))
	check("wide, fast stroke deals max damage", snaps.size() > 0 and snaps[0][0] == 3, str(snaps))
	check("cuts both enemies in the jaws", hp(in_a) == 0 and hp(in_b) == 0, "hp %d %d" % [hp(in_a), hp(in_b)])
	check("enemy outside the jaws is untouched", hp(out) == 3, "hp %d" % hp(out))
	check("closes near the min carrier distance", gap() < 2.8, "gap=%.2f" % gap())
	check("blades nearly shut", rad_to_deg(specifics._half_angle) < 5.0, "half angle=%.1f" % rad_to_deg(specifics._half_angle))
	Health.apply_damage(out, 999, out.global_position)

	await hold([action(shooter, "left")], 0.15)
	await wait(0.1)
	snaps.clear()
	await hold([action(shooter, "right")], 0.3)
	check("a short stroke does not snap", snaps.is_empty(), "%s gap=%.2f" % [snaps, gap()])

	await open_fully(shooter, setter)
	var solo := spawn_enemy(Vector3(3.0, 0, 0.0))
	await get_tree().physics_frame
	snaps.clear()
	await hold([action(setter, "left")], 1.1)
	print("INFO solo-closing stroke snaps=%s hp=%d gap=%.2f" % [snaps, hp(solo), gap()])
	check("one player closing snaps for less damage", snaps.size() == 1 and snaps[0][0] == 2, str(snaps))
	check("reduced damage leaves a default enemy alive", hp(solo) == 1, "hp %d" % hp(solo))
	if is_instance_valid(solo):
		Health.apply_damage(solo, 999, solo.global_position)

	await open_fully(shooter, setter)
	snaps.clear()
	await hold([action(shooter, "right"), action(setter, "left")], 0.7)
	check("a stroke with nothing in the jaws still snaps", snaps.size() == 1 and snaps[0][1] == 0, str(snaps))

	await _test_blade_collision(shooter, setter)

	setter.carrying_weapon_data.can_carry_status = CarryingWeaponData.CanCarryStatus.NO_WEAPON_AVAILABLE
	await wait(0.6)
	snaps.clear()
	await hold([action(shooter, "left")], 0.5)
	await hold([action(shooter, "right")], 0.5)
	check("no snaps with a single carrier", snaps.is_empty(), str(snaps))
	await shot("shears_solo.png")

	print("RESULT fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
