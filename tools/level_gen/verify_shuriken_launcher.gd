extends Node
## Test driver for the shuriken launcher in world_playground.tscn: the back carrier's real shoot button flings the
## star, which slices the enemies in its path; the front carrier's real shoot button scatters its four kunai; a
## scripted scatter right next to an enemy along a blade shows a kunai lands. Holding the front carrier's button slows
## the star until it is let go or held too long. Also the reload and dry presses.
## Run: tools/level_gen/godot.sh test tools/level_gen/verify_shuriken_launcher.gd res://src/world/levels/world_playground.tscn <out_dir> 120

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
	get_tree().create_timer(100.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  [" + detail + "]"))
	if not ok:
		fails += 1


func info(text: String) -> void:
	print("INFO " + text)


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


func launcher() -> ShurikenLauncherSpecifics:
	return world.get_active_weapon().get_node("WeaponSpecifics") as ShurikenLauncherSpecifics


## [back carrier, front carrier], from the weapon's own carry info.
func carriers() -> Array[PlayerLocal]:
	var carry_info: CarryInfo = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info()
	return [carry_info.main_carrier, carry_info.secondary_carrier]


func tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func forward() -> Vector3:
	var f := launcher().muzzle.global_basis.z
	f.y = 0.0
	return f.normalized()


func on_screen(pos: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow(-40.0)
	return not cam.is_position_behind(pos) and rect.has_point(cam.unproject_position(pos))


func spawn_enemy(at: Vector3) -> EnemyLocal:
	var enemy := (load("res://src/enemy/enemy_local.tscn") as PackedScene).instantiate() as EnemyLocal
	world.get_node("Enemies").add_child(enemy)
	enemy.global_position = Vector3(at.x, carriers()[0].global_position.y, at.z)
	if "is_offensive" in enemy:
		enemy.set("is_offensive", false)
	return enemy


func hp(enemy: EnemyLocal) -> int:
	if not is_instance_valid(enemy):
		return 0
	return Health.from_target(enemy).current_hp


func clear_prototype_group() -> void:
	for e in world.get_node("Enemies/Prototype/InstancedEnemies").get_children():
		e.queue_free()


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	clear_prototype_group()
	await wait(1.5)
	var weapon := world.get_active_weapon()
	check("carrying the shuriken launcher", weapon != null and weapon.scene_file_path.ends_with("shuriken_launcher.tscn"))
	var c := carriers()
	check("both carriers hold it", is_instance_valid(c[0]) and is_instance_valid(c[1]))
	check("a star is loaded", launcher().is_loaded() and launcher().get_node("ShurikenMuzzle/LoadedShuriken").visible)
	await shot("01_loaded.png")

	# ---- Front carrier with no star out: a dry click, nothing thrown. ----
	var thrown := [0]
	launcher().kunais_scattered.connect(func(k: Array[Kunai]): thrown[0] += k.size())
	await tap(c[1].action_shoot)
	check("front carrier's press with no star out throws nothing", thrown[0] == 0)

	# ---- Back carrier flings the star through two enemies in a line. ----
	var muzzle := launcher().muzzle.global_position
	var near := spawn_enemy(muzzle + forward() * 4.0)
	var far := spawn_enemy(muzzle + forward() * 7.5)
	await wait(0.3)
	var launched: Array = [null]
	launcher().shuriken_launched.connect(func(s: Shuriken): launched[0] = s)
	await tap(c[0].action_shoot)
	var star: Shuriken = launched[0]
	check("back carrier's shoot flings a star", star != null)
	if star == null:
		_finish()
		return
	check("the deck is empty while it reloads", not launcher().is_loaded() and not launcher().get_node("ShurikenMuzzle/LoadedShuriken").visible)
	await tap(c[0].action_shoot)
	check("pressing again during the reload flings nothing new", launcher().get_scatterable().size() == 1)
	await wait(0.25)
	await shot("02_star_flying.png")
	await wait_until(func(): return not is_instance_valid(star) or star.is_hovering(), 3.0)
	check("the star sliced both enemies in its line", hp(near) == 1 and hp(far) == 1, "hp near=%d far=%d" % [hp(near), hp(far)])
	check("the star hangs at the end of its range", is_instance_valid(star) and star.is_hovering())
	check("the hanging star is on screen", is_instance_valid(star) and on_screen(star.global_position))
	await shot("02b_hovering.png")
	var travelled := (star.global_position - muzzle) if is_instance_valid(star) else Vector3.ZERO
	travelled.y = 0.0
	info("star range %.1f m" % travelled.length())

	# ---- Front carrier scatters the kunai with a real press while it hangs. ----
	var kunais: Array = []
	var on_scatter := func(k: Array[Kunai]): kunais.assign(k)
	launcher().kunais_scattered.connect(on_scatter)
	await tap(c[1].action_shoot)
	launcher().kunais_scattered.disconnect(on_scatter)
	check("front carrier's shoot scatters four kunai", kunais.size() == 4, "%d" % kunais.size())
	check("the star has no kunai left", not is_instance_valid(star) or not star.has_kunais())
	check("kunai fly out in four directions", _four_directions(kunais, star.global_position if is_instance_valid(star) else Vector3.ZERO))
	await wait(0.12)
	await shot("03_scatter.png")
	await tap(c[1].action_shoot)
	check("a second press scatters nothing more", thrown[0] == 4, "%d thrown" % thrown[0])
	var popped: bool = await wait_until(func(): return not is_instance_valid(star), 2.0)
	check("the star pops after hanging", popped)

	# ---- Front carrier holds shoot: the star slows down, then letting go scatters. ----
	await wait_until(func(): return launcher().is_loaded(), 2.0)
	launched[0] = null
	await tap(c[0].action_shoot)
	var slow_star: Shuriken = launched[0]
	check("a second star is flung", slow_star != null)
	if slow_star == null:
		_finish()
		return
	await wait(0.15)
	var before_hold := slow_star.global_position
	Input.action_press(c[1].action_shoot)
	await wait(0.6)
	check("holding slows the star", launcher().is_holding() and slow_star.is_slowed() and slow_star.get_time_scale() < 0.2, "time scale %.2f" % slow_star.get_time_scale())
	var drift := slow_star.global_position.distance_to(before_hold)
	check("the slowed star drifts instead of flying", drift < 3.0, "%.1f m in 0.6 s (full speed would be 9)" % drift)
	check("holding keeps the kunai in", slow_star.has_kunais() and thrown[0] == 4)
	await shot("05_slowed.png")
	Input.action_release(c[1].action_shoot)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check("letting go scatters the kunai", thrown[0] == 8 and not launcher().is_holding(), "%d thrown" % thrown[0])
	await get_tree().physics_frame
	check("the star speeds up again after the scatter", not slow_star.is_slowed())
	await wait_until(func(): return not is_instance_valid(slow_star), 3.0)

	# ---- Holding too long scatters by itself. ----
	await wait_until(func(): return launcher().is_loaded(), 2.0)
	await tap(c[0].action_shoot)
	await wait(0.15)
	Input.action_press(c[1].action_shoot)
	var auto: bool = await wait_until(func(): return thrown[0] == 12, ShurikenLauncherSpecifics.MAX_HOLD_SEC + 1.0)
	Input.action_release(c[1].action_shoot)
	check("a hold past the limit scatters by itself", auto, "%d thrown" % thrown[0])
	await wait(1.0)

	# ---- A kunai finishes an enemy standing along a blade. ----
	await wait_until(func(): return launcher().is_loaded(), 2.0)
	var second := launcher().launch_shuriken()
	await wait(0.4)
	var target := spawn_enemy(_blade_point(second, 3.0))
	Health.apply_damage(target, 2, target.global_position)
	# Same frame as the spawn, so the blade hasn't turned away from the enemy yet.
	second.scatter()
	var finished: bool = await wait_until(func(): return hp(target) == 0, 1.5)
	check("a kunai kills a wounded enemy along its blade", finished, "hp=%d" % hp(target))
	await shot("04_kunai_hit.png")
	await wait(1.0)
	_finish()


## Each kunai's heading, relative to the star, is 90 degrees from the next.
func _four_directions(kunais: Array, center: Vector3) -> bool:
	if kunais.size() != 4:
		return false
	var headings: Array[float] = []
	for k in kunais:
		var kunai := k as Kunai
		if not is_instance_valid(kunai):
			continue
		var d: Vector3 = kunai.global_basis.z
		headings.append(atan2(d.x, d.z))
	headings.sort()
	if headings.size() != 4:
		return false
	for i in 3:
		if absf(angle_difference(headings[i], headings[i + 1]) - PI / 2.0) > 0.05:
			return false
	return true


## A point `metres` out along the star's first blade, as it points right now.
func _blade_point(star: Shuriken, metres: float) -> Vector3:
	var visual: Node3D = null
	for child in star.get_children():
		if child is ShurikenVisual:
			visual = child
	var dir := visual.global_basis.z
	dir.y = 0.0
	return star.global_position + dir.normalized() * metres


func _finish() -> void:
	print("RESULT fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
