extends Node
## Test driver for the bazooka's mid-air detonation and its prompt, on world_local_bazooka.tscn.
## Run through godot.sh, see docs/level-creation-for-agents.md.
## Uses the carriers' real buttons. Save tracking is disabled, so save.json stays untouched.

const ROCKET_SPEED := 5.0

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0
var bazooka: BazookaSpecifics
var back: PlayerLocal
var front: PlayerLocal
var fired: Array = []
var detonated: Array = []


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


func living_enemies() -> Array:
	return world.get_node("Enemies/EnemyGroup/InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func forward() -> Vector3:
	var f := bazooka.muzzle.global_basis.z
	f.y = 0.0
	return f.normalized()


## Pins a robot in place, so it can't walk into the rocket's path on its own.
func pin(enemy: EnemyLocal, at: Vector3) -> void:
	enemy.speed = 0.0
	enemy.velocity = Vector3.ZERO
	enemy.global_position = Vector3(at.x, enemy.global_position.y, at.z)


func prompt() -> FrontCarrierPrompt:
	for child in bazooka.get_children():
		if child is FrontCarrierPrompt:
			return child
	return null


func check_prompt_over_front(label: String) -> void:
	var p := prompt()
	var offset := p.global_position - front.global_position
	check(label, p.visible and Vector2(offset.x, offset.z).length() < 0.1 and offset.y > 2.5, "visible=%s offset=%s" % [p.visible, offset])


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.0)
	for p in world.players.get_children():
		if p is PlayerLocal:
			p.get_node("Health").grant_invulnerability(9999.0)
	var weapon := world.get_node("Weapon/Bazooka")
	bazooka = weapon.get_node("WeaponSpecifics") as BazookaSpecifics
	bazooka.fired.connect(func(r): fired.append(r))
	bazooka.detonated.connect(func(r): detonated.append(r))
	var carry: CarryInfo = weapon.get_node("PickAndDropHandler").get_carry_info()
	back = carry.main_carrier
	front = carry.secondary_carrier
	check("both carriers hold the bazooka", is_instance_valid(back) and is_instance_valid(front))
	_clear_the_range()
	await check_nothing_to_detonate()
	await check_mid_air_detonation()
	await check_oldest_first()
	await check_prompt_retires()
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


## Parks every robot well behind the carriers, so no rocket hits one by accident. Each spot
## is snapped onto walkable ground: a robot parked over the water would fall and die.
func _clear_the_range() -> void:
	var behind := bazooka.muzzle.global_position - forward() * 14.0
	var side := forward().cross(Vector3.UP)
	var enemies := living_enemies()
	for i in enemies.size():
		pin(enemies[i], on_ground(enemies[i], behind + side * (i - enemies.size() * 0.5) * 2.0))


func on_ground(enemy: EnemyLocal, point: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(enemy.navigation_agent.get_navigation_map(), point)


func check_nothing_to_detonate() -> void:
	check("the detonate prompt starts hidden", not prompt().visible)
	await tap(front.action_shoot)
	check("the front carrier's button does nothing with no rocket in the air", detonated.is_empty() and fired.is_empty())


## A robot beside the rocket's path, which the rocket alone would fly straight past.
func check_mid_air_detonation() -> void:
	var enemies := living_enemies()
	var target: EnemyLocal = enemies[0]
	var control: EnemyLocal = enemies[1]
	var origin := bazooka.muzzle.global_position
	var side := forward().cross(Vector3.UP)
	pin(target, origin + forward() * 4.0 + side * 2.5)
	pin(control, origin + forward() * 4.0 + side * 7.0)
	await wait(0.2)
	await tap(back.action_shoot)
	check("the back carrier fires a rocket", fired.size() == 1)
	await wait(0.3)
	check_prompt_over_front("a rocket in the air shows the detonate prompt over the front carrier")
	check("the prompt is highlighted while a rocket flies", prompt()._text.modulate == FrontCarrierPrompt.HIGHLIGHT_COLOR)
	var rocket: BazookaBulletLocal = fired[0]
	await wait_until(func(): return (rocket.global_position - origin).dot(forward()) >= 4.0, 2.0)
	await shot("detonate_prompt.png")
	check("the rocket is still flying beside the robot", not rocket.is_spent() and target.is_alive())
	await tap(front.action_shoot)
	await wait(0.05)
	await shot("detonate_blast.png")
	check("the front carrier's button detonates the rocket", detonated.size() == 1 and rocket.is_spent())
	await wait(0.3)
	check("the mid-air blast kills the robot beside the path", not target.is_alive())
	check("the robot out of the blast is untouched", control.is_alive())
	check("the prompt hides once no rocket is flying", not prompt().visible)
	pin(control, on_ground(control, bazooka.muzzle.global_position - forward() * 14.0))


func check_oldest_first() -> void:
	await tap(back.action_shoot)
	await wait(BazookaSpecifics.FIRE_COOLDOWN_SEC + 0.1)
	await tap(back.action_shoot)
	check("two rockets fly at once", fired.size() == 3 and not fired[1].is_spent() and not fired[2].is_spent(), str(fired.size()))
	await tap(front.action_shoot)
	check("one tap detonates only the oldest rocket", detonated.size() == 2 and fired[1].is_spent() and not fired[2].is_spent())
	await tap(front.action_shoot)
	check("the next tap detonates the newer rocket", detonated.size() == 3 and fired[2].is_spent())


## Detonations count towards learning it: after three the prompt stays away while rockets fly.
func check_prompt_retires() -> void:
	print("INFO detonations so far: ", FrontCarrierPrompt.get_uses(BazookaSpecifics.DETONATE_WORD))
	check("three detonations have been made", FrontCarrierPrompt.is_learned(BazookaSpecifics.DETONATE_WORD))
	await wait(BazookaSpecifics.FIRE_COOLDOWN_SEC)
	await tap(back.action_shoot)
	await wait(0.3)
	check("after %d detonations the prompt retires" % FrontCarrierPrompt.USES_TO_LEARN, not prompt().visible and bazooka.get_oldest_rocket() != null, "prompt visible=%s, rocket flying=%s, fired=%d" % [prompt().visible, bazooka.get_oldest_rocket() != null, fired.size()])
