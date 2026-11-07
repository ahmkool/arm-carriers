extends Node
## Test driver for 4GTN's shield, on world_local_katana_robot_boss.tscn.
## Run through godot.sh, see docs/level-creation-for-agents.md.
## With the pulse rifle: the boss raises a shield in phase 2 and fights on behind it, bolts
## bounce off, the VENT prompt shows even when retired, the shield never wears off, and a
## vent that breaks it stuns the boss. Then the level reloads with the siege bow, where it
## never shields. The breaking vent is a scripted blast from in front of the boss; the bolts
## are real input.
## Save tracking is disabled, so save.json stays untouched.

const CELL := 2.999
const SCENE := "res://src/world/levels/world_local_katana_robot_boss.tscn"

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0
var boss: EnemyLocal
var moves: Array[StringName] = []
var _last_attack_state: EnemyState


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	get_tree().create_timer(240.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  [" + detail + "]"))
	if not ok:
		fails += 1


func w(cx: float, cz: float, y: float = 0.0) -> Vector3:
	return Vector3((cx + 0.5) * CELL, y, (cz + 0.5) * CELL)


func state() -> String:
	return "" if gsm == null or gsm.current == null else String(gsm.current.name).to_lower()


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


func boss_state() -> String:
	if not is_instance_valid(boss) or boss.enemy_state_machine.current_state == null:
		return ""
	return String(boss.enemy_state_machine.current_state.name).to_lower()


func boss_moves() -> KatanaRobotMoves:
	return boss.get_node("KatanaRobotMoves") as KatanaRobotMoves


func fireballs_in_flight() -> Array:
	return get_tree().current_scene.get_children().filter(func(c): return c is Fireball)


func _track_moves() -> void:
	if not is_instance_valid(boss):
		return
	var current := boss.enemy_state_machine.current_state
	if current == _last_attack_state:
		return
	_last_attack_state = current
	if boss_state() != "attacking":
		return
	moves.append(current.get("_move"))


## Reloads the boss arena with another weapon.
func reload_with(weapon_id: String) -> void:
	LevelLoadout.set_weapon(weapon_id)
	get_tree().change_scene_to_file(SCENE)
	await wait_until(func(): return get_tree().current_scene is WorldLocal and get_tree().current_scene != world, 10.0)
	await start_fight(weapon_id)


## Puts the carriers in the arena, wakes 4GTN and puts it in phase 2.
func start_fight(weapon_id: String) -> void:
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("%s: reaches Playing" % weapon_id, ok, state())
	await wait(1.0)
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)
	# Inside the arena, where the boss can reach them, facing it down the deck.
	var carry: CarryInfo = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info()
	var front_carrier: PlayerLocal = carry.secondary_carrier
	var back_carrier: PlayerLocal = carry.main_carrier
	front_carrier.global_position = w(0, -9, front_carrier.global_position.y)
	back_carrier.global_position = w(0, -7, back_carrier.global_position.y)
	await wait(0.5)
	boss = world.get_node("Enemies/BossGroup/InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal)[0]
	moves.clear()
	_last_attack_state = null
	if not get_tree().physics_frame.is_connected(_track_moves):
		get_tree().physics_frame.connect(_track_moves)
	world.get_node("Enemies/BossGroup").trigger(true)
	await wait_until(func(): return moves.has(&"taunt"), 5.0)
	var health := Health.from_target(boss)
	health.take_damage(health.current_hp - health.max_hp / 2, boss.global_position)
	await wait(0.2)


func _run() -> void:
	await start_fight("pulse_rifle")
	check("half health puts 4GTN in phase 2", BossPhaseController.from_enemy(boss).get_current_phase() == 2)
	await check_shield_goes_up()
	await check_fights_on_behind_it()
	await check_break_stuns()
	await check_next_shield_waits()
	await reload_with("siege_bow")
	await check_other_weapon()
	LevelLoadout.clear()
	print("INFO moves: ", moves)
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


func rifle() -> PulseRifleSpecifics:
	return world.get_active_weapon().get_node("WeaponSpecifics") as PulseRifleSpecifics


func check_shield_goes_up() -> void:
	# Retire the VENT prompt first: the boss's shield must bring it back.
	while not FrontCarrierPrompt.is_learned(PulseRifleSpecifics.VENT_WORD):
		FrontCarrierPrompt.note_use(PulseRifleSpecifics.VENT_WORD)
	var raised: bool = await wait_until(func(): return EnemyShield.is_shielded(boss), 12.0)
	check("phase 2 opens with 4GTN raising a shield", raised and moves.has(&"shield"), str(moves))
	var hp_before := Health.from_target(boss).current_hp
	var info: CarryInfo = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info()
	Input.action_press(info.main_carrier.action_shoot)
	await wait(1.2)
	Input.action_release(info.main_carrier.action_shoot)
	await wait(0.1)
	check("4GTN takes no damage while shielded", Health.from_target(boss).current_hp == hp_before, "%d -> %d" % [hp_before, Health.from_target(boss).current_hp])
	var prompt: FrontCarrierPrompt = rifle().get_children().filter(func(c): return c is FrontCarrierPrompt)[0]
	check("the shield brings back the retired VENT prompt", prompt.visible, "heat %.2f, prompt visible %s" % [rifle().heat, prompt.visible])
	await shot("boss_shield.png")


## It keeps attacking with the shield up, and the shield doesn't wear off or burst.
func check_fights_on_behind_it() -> void:
	var index := moves.rfind(&"shield")
	var fought: bool = await wait_until(func(): return moves.size() > index + 2, 12.0)
	check("4GTN keeps attacking behind its shield", fought, str(moves.slice(index)))
	check("the shield is still up after those moves", EnemyShield.is_shielded(boss))
	await wait(4.0)
	check("the shield doesn't wear off", EnemyShield.is_shielded(boss))
	check("he raises only one shield at a time", moves.count(&"shield") == 1, str(moves))
	await shot("boss_shield_fighting.png")


func check_break_stuns() -> void:
	await wait_until(func(): return boss_state() != "attacking", 3.0)
	for f in fireballs_in_flight():
		f.queue_free()
	var front: PlayerLocal = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info().secondary_carrier
	var toward: Vector3 = boss.global_position - front.global_position
	toward.y = 0.0
	var origin: Vector3 = boss.global_position - toward.normalized() * 5.0
	var hits := PulseVent.blast(world.get_world_3d(), origin, toward.normalized(), 0.6)
	check("a vent in front of 4GTN hits it", hits >= 1, str(hits))
	await get_tree().physics_frame
	check("the vent breaks the shield", not EnemyShield.is_shielded(boss))
	var stunned: bool = await wait_until(func(): return boss_state() == "stunned", 0.5)
	check("breaking the shield stuns 4GTN", stunned, boss_state())
	await wait(0.4)
	await shot("boss_stunned.png")
	var hp_before := Health.from_target(boss).current_hp
	Health.apply_damage(boss, 3, origin)
	check("a stunned 4GTN takes damage", Health.from_target(boss).current_hp == hp_before - 3)
	await wait(1.0)
	check("4GTN stays stunned for a while", boss_state() == "stunned", boss_state())
	var recovered: bool = await wait_until(func(): return boss_state() != "stunned", 2.0)
	check("4GTN recovers after the stun", recovered, boss_state())
	var light := boss.get_node("Robot/Rig_Large/Skeleton3D/KatanaHand/Katana/BladeLight") as OmniLight3D
	await wait(0.4)
	check("its blade lights up again", light.light_energy > 1.0, "%.1f" % light.light_energy)
	check("4GTN's model stands up straight again", absf(boss.get_node("Robot").rotation.x) < 0.01)


## The next shield waits out the cooldown from the break, then goes up again.
func check_next_shield_waits() -> void:
	var behavior := boss.behavior as KatanaRobotBehavior
	await wait(3.0)
	check("no new shield straight after the break", not EnemyShield.is_shielded(boss), "cooldown %.1f s" % behavior._shield_remaining)
	behavior._shield_remaining = 0.0
	var raised: bool = await wait_until(func(): return EnemyShield.is_shielded(boss), 8.0)
	check("4GTN raises a new shield once the cooldown is over", raised and moves.count(&"shield") == 2, str(moves))


func check_other_weapon() -> void:
	check("siege bow: 4GTN can't raise a shield", not boss_moves().can_raise_shield())
	await wait(8.0)
	check("siege bow: phase 2 has no shield", not moves.has(&"shield") and not EnemyShield.is_shielded(boss), str(moves))
