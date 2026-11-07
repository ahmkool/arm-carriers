extends Node
## Test driver for the Siege Bow's shockwave and its prompt, on world_local_siege_bow.tscn.
## Run through godot.sh, see docs/level-creation-for-agents.md.
## Uses the carriers' real buttons. Save tracking is disabled, so save.json stays untouched.

const ENEMY_SCENE := "res://src/enemy/enemy_local.tscn"

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0
var specifics: SiegeBowSpecifics
var shooter: PlayerLocal
var setter: PlayerLocal
var charges := 0
var uses: Array = []


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(150.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame


func action(player: PlayerLocal, suffix: String) -> String:
	return "p%s_%s" % [player.device_id, suffix]


func draw_bow(seconds: float) -> void:
	await hold([action(shooter, "down"), action(setter, "up")], seconds)
	await wait(0.3)


func close_bow() -> void:
	await hold([action(shooter, "up"), action(setter, "down")], 1.0)
	await wait(0.2)


func hp(enemy: EnemyLocal) -> int:
	return Health.from_target(enemy).current_hp if is_instance_valid(enemy) else 0


func enemy_state(enemy: EnemyLocal) -> String:
	if not is_instance_valid(enemy) or enemy.enemy_state_machine.current_state == null:
		return ""
	return String(enemy.enemy_state_machine.current_state.name).to_lower()


func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func spawn_enemy(at: Vector3) -> EnemyLocal:
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as EnemyLocal
	world.get_node("Enemies").add_child(enemy)
	enemy.global_position = Vector3(at.x, shooter.global_position.y, at.z)
	return enemy


func kill(enemies: Array) -> void:
	for e in enemies:
		if is_instance_valid(e) and e.is_alive():
			Health.apply_damage(e, 999, e.global_position)


func prompt() -> FrontCarrierPrompt:
	for child in specifics.get_children():
		if child is FrontCarrierPrompt:
			return child
	return null


func is_glowing() -> bool:
	return (specifics.get_node("Grip/GripMesh") as MeshInstance3D).material_overlay != null


func check_prompt_over_front(label: String) -> void:
	var p := prompt()
	var offset := p.global_position - setter.global_position
	check(label, p.visible and Vector2(offset.x, offset.z).length() < 0.1 and offset.y > 2.5, "visible=%s offset=%s" % [p.visible, offset])


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	for p in world.players.get_children():
		if p is PlayerLocal:
			p.get_node("Health").grant_invulnerability(9999.0)
	var bow := world.get_node("Weapon/SiegeBow") as Node3D
	specifics = bow.get_node("WeaponSpecifics") as SiegeBowSpecifics
	specifics.shockwave_charged.connect(func(): charges += 1)
	specifics.shockwave_used.connect(func(hits: int): uses.append(hits))
	await wait(1.0)
	var carry: CarryInfo = (bow.get_node("PickAndDropHandler") as PickAndDropHandler).get_carry_info()
	shooter = carry.main_carrier
	setter = carry.secondary_carrier
	check("both players carry the bow", is_instance_valid(shooter) and is_instance_valid(setter))
	await check_starts_uncharged()
	await check_miss_doesnt_charge()
	await check_hit_charges()
	await check_shockwave_blast()
	await check_prompt_retires()
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


func check_starts_uncharged() -> void:
	check("the shockwave starts uncharged", not specifics.is_shockwave_ready())
	check("the shockwave prompt starts hidden", not prompt().visible)
	check("an uncharged bow doesn't glow", not is_glowing())
	await tap(setter.action_shoot)
	check("the front carrier's button does nothing while uncharged", uses.is_empty())


func check_miss_doesnt_charge() -> void:
	await draw_bow(0.6)
	await tap(shooter.action_shoot)
	await wait(1.2)
	check("an arrow that hits nothing doesn't charge the shockwave", not specifics.is_shockwave_ready() and charges == 0)
	await close_bow()


func check_hit_charges() -> void:
	await draw_bow(1.0)
	var grip := (specifics.get_node("Grip") as Node3D).global_position
	var target := spawn_enemy(grip + specifics.global_basis.z.normalized() * 5.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await tap(shooter.action_shoot)
	var charged: bool = await wait_until(func(): return specifics.is_shockwave_ready(), 1.0)
	check("an arrow that hits an enemy charges the shockwave", charged and charges == 1, "target hp %d" % hp(target))
	await wait(0.3)
	check_prompt_over_front("a charged bow shows the shockwave prompt over the front carrier")
	check("a charged bow glows", is_glowing())
	await shot("shockwave_charged.png")
	kill([target])
	await close_bow()
	check("the charge waits through the reload", specifics.is_shockwave_ready())


## Rings the front carrier with robots, plus one out of reach, and sets the shockwave off.
func check_shockwave_blast() -> void:
	var origin := setter.global_position
	var forward := specifics.global_basis.z.normalized()
	var side := forward.cross(Vector3.UP)
	var ring := [spawn_enemy(origin + forward * 2.5), spawn_enemy(origin + side * 3.0), spawn_enemy(origin - side * 3.0)]
	var far := spawn_enemy(origin + forward * 9.0)
	# A fresh robot has no state for a frame, then spends about 2 s spawning.
	var ready: bool = await wait_until(func(): return (ring + [far]).all(func(e): return not ["", "spawning"].has(enemy_state(e))), 4.0)
	check("the robots finish spawning", ready, str((ring + [far]).map(func(e): return enemy_state(e))))
	for i in ring.size():
		ring[i].global_position = [origin + forward * 2.5, origin + side * 3.0, origin - side * 3.0][i] * Vector3(1, 0, 1) + Vector3(0, ring[i].global_position.y, 0)
		ring[i].velocity = Vector3.ZERO
	await get_tree().physics_frame
	origin = setter.global_position
	var hp_before: Array = ring.map(func(e): return hp(e))
	var dist_before: Array = ring.map(func(e): return flat_distance(e.global_position, origin))
	var far_hp := hp(far)
	await tap(setter.action_shoot)
	await wait(0.05)
	await shot("shockwave_blast.png")
	check("the front carrier's button sets off the shockwave", uses.size() == 1)
	if uses.is_empty():
		return
	check("the shockwave hits all three robots around the front carrier", uses[0] == 3, str(uses[0]))
	check("using the shockwave spends the charge", not specifics.is_shockwave_ready() and not is_glowing())
	check("the robot out of reach is untouched", hp(far) == far_hp, "hp %d" % hp(far))
	for i in ring.size():
		var lost: int = hp_before[i] - hp(ring[i])
		check("robot %d takes %d damage" % [i, BowShockwave.DAMAGE], lost == BowShockwave.DAMAGE, "lost %d" % lost)
	await wait(0.4)
	for i in ring.size():
		var pushed := flat_distance(ring[i].global_position, origin) - float(dist_before[i])
		check("robot %d is shoved away from the front carrier" % i, pushed > 1.5, "%.2f m" % pushed)
	await wait(0.5)
	var reeling: Array = ring.map(func(e): return enemy_state(e))
	check("the robots are still reeling ~1 s later", reeling.all(func(s): return s == "takingdamage"), str(reeling))
	await wait(BowShockwave.STAGGER_SEC)
	var recovered: Array = ring.map(func(e): return enemy_state(e))
	check("the robots recover after the stagger", recovered.all(func(s): return s != "takingdamage"), str(recovered))
	check("the prompt hides once the charge is spent", not prompt().visible)
	await tap(setter.action_shoot)
	check("one charge gives one shockwave", uses.size() == 1)
	kill(ring + [far])


## Uses count towards learning it: after three the prompt stays away on a charged bow.
func check_prompt_retires() -> void:
	while not FrontCarrierPrompt.is_learned(SiegeBowSpecifics.SHOCKWAVE_WORD):
		specifics.charge_shockwave()
		await wait(0.3)
		check_prompt_over_front("the prompt shows while still learning (%d uses)" % FrontCarrierPrompt.get_uses(SiegeBowSpecifics.SHOCKWAVE_WORD))
		await tap(setter.action_shoot)
		await wait(0.3)
	specifics.charge_shockwave()
	await wait(0.3)
	check("after %d uses the prompt retires" % FrontCarrierPrompt.USES_TO_LEARN, not prompt().visible)
	check("a charged bow still glows once the prompt has retired", is_glowing())
