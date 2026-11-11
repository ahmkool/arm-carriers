extends Node
## Test driver for pulse bolts bouncing off shields, on world_playground.tscn.
## Run through godot.sh, see docs/level-creation-for-agents.md.
## Save tracking is disabled, so save.json stays untouched.

const BOLT_SCENE := preload("res://src/weapon/pulse_rifle/pulse_bolt.tscn")

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0
var rifle: PulseRifleSpecifics
var bolt_height := 1.0
var _enemies := {}


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(90.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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


func enemy(node_name: String) -> EnemyLocal:
	return _enemies[node_name]


## Checkpoint snapshots rename the enemies, so tell them apart by their shield, before it breaks.
func _find_enemy(shielded: bool) -> EnemyLocal:
	for child in world.get_node("Enemies/Prototype/InstancedEnemies").get_children():
		if child is EnemyLocal and (EnemyShield.find_on(child) != null) == shielded:
			return child
	return null


func hp(e: EnemyLocal) -> int:
	return Health.from_target(e).current_hp


func fire(from: Vector3, direction: Vector3) -> PulseBolt:
	var bolt := BOLT_SCENE.instantiate() as PulseBolt
	world.add_child(bolt)
	bolt.launch(Vector3(from.x, bolt_height, from.z), direction.normalized(), PulseRifleSpecifics.BOLT_SPEED,
		PulseRifleSpecifics.BOLT_RANGE, PulseRifleSpecifics.DAMAGE)
	return bolt


## Follows a bolt until it ends, returning its last direction and where it was. Takes a screenshot
## named `shot_name` once the bolt has flown `shot_after` seconds.
func track(bolt: PulseBolt, shot_name := "", shot_after := 0.0) -> Dictionary:
	var last := {"direction": bolt._direction, "position": bolt.global_position, "bounces": 0}
	var started := Time.get_ticks_msec()
	while is_instance_valid(bolt) and not bolt._is_spent:
		last = {"direction": bolt._direction, "position": bolt.global_position, "bounces": bolt._bounces}
		if not shot_name.is_empty() and Time.get_ticks_msec() - started >= shot_after * 1000.0:
			get_tree().root.get_texture().get_image().save_png(out_dir + "/" + shot_name)
			shot_name = ""
		await get_tree().physics_frame
	return last


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.0)
	rifle = world.get_active_weapon().get_node("WeaponSpecifics") as PulseRifleSpecifics
	bolt_height = rifle.muzzle.global_position.y
	_enemies = {"ShieldedRobot": _find_enemy(true), "HiddenGunner": _find_enemy(false)}
	print("INFO muzzle height %.2f" % bolt_height)
	check("the round shield is up in a pulse rifle run", EnemyShield.is_shielded(enemy("ShieldedRobot")))
	check("both flat shields exist", world.get_node_or_null("Level/Shields/CoverShield") != null and world.get_node_or_null("Level/Shields/BankShield") != null)
	var overview := Camera3D.new()
	world.add_child(overview)
	overview.look_at_from_position(Vector3(4, 16, 4), Vector3(4, 0, -10), Vector3.UP)
	overview.make_current()
	await wait(0.2)
	await shot("mirrors_overview.png")
	await check_cover_bounces()
	await check_bank_shot()
	await check_round_shield()
	await check_enemy_shots_pass()
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


func check_cover_bounces() -> void:
	var gunner := enemy("HiddenGunner")
	var before := hp(gunner)
	var end: Dictionary = await track(fire(Vector3(7, 0, -2), Vector3.FORWARD))
	check("a straight shot at the gunner bounces off the cover", end.bounces == 1, str(end))
	check("the bounced bolt flies back towards the players", end.direction.z > 0.99, str(end.direction))
	check("the gunner behind cover is unhurt", hp(gunner) == before, "%d -> %d" % [before, hp(gunner)])


func check_bank_shot() -> void:
	var gunner := enemy("HiddenGunner")
	var before := hp(gunner)
	var end: Dictionary = await track(fire(Vector3(14, 0, -2), Vector3.FORWARD), "mirrors_bank_shot.png", 0.3)
	check("the bank shot bounces off the angled shield", end.bounces == 1, str(end))
	check("the bank shot turns 90° towards the gunner", end.direction.x < -0.99, str(end.direction))
	check("the bank shot hits the gunner", hp(gunner) < before, "%d -> %d" % [before, hp(gunner)])


func check_round_shield() -> void:
	var robot := enemy("ShieldedRobot")
	var before := hp(robot)
	var centre := robot.global_position
	var end: Dictionary = await track(fire(Vector3(centre.x, 0, -2), Vector3.FORWARD))
	check("a head-on bolt bounces straight back off the bubble", end.bounces == 1 and end.direction.z > 0.99, str(end))
	var glance: Dictionary = await track(fire(Vector3(centre.x + 0.8, 0, -2), Vector3.FORWARD))
	check("an off-centre bolt glances off sideways", glance.bounces == 1 and glance.direction.x > 0.5, str(glance.direction))
	check("bolts that bounce leave the robot unhurt", hp(robot) == before, "%d -> %d" % [before, hp(robot)])
	EnemyShield.find_on(robot).shatter()
	await wait(0.4)
	var after: Dictionary = await track(fire(Vector3(centre.x, 0, -2), Vector3.FORWARD))
	check("once shattered, bolts go through to the robot", after.bounces == 0 and hp(robot) < before, "%s hp %d" % [after, hp(robot)])


## The gunner fires through its own cover at the players once awake: some laser bolt must start
## behind the cover's line (z = -8.5) and carry on past it.
func check_enemy_shots_pass() -> void:
	var gunner := enemy("HiddenGunner")
	var seen := {}
	var crossed := [0]
	# Laser bolts one-hit kill, and a respawn would swap the gunner for a fresh copy.
	for p in world.players.get_children():
		if p is PlayerLocal:
			Health.from_target(p).grant_invulnerability(9999.0)
	world.get_node("Level/Events/WakePrototype").trigger()
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline and crossed[0] == 0:
		for node in world.find_children("*", "Node3D", true, false):
			if not node is Fireball:
				continue
			var z: float = node.global_position.z
			if not seen.has(node):
				seen[node] = z
			elif seen[node] < -9.0 and z > -8.0:
				crossed[0] += 1
		await get_tree().physics_frame
	await shot("mirrors_gunner_awake.png")
	check("the gunner holds its post behind the cover", gunner.global_position.z < -11.0, str(gunner.global_position))
	check("the gunner shoots", seen.size() > 0, "%d bolts" % seen.size())
	check("its laser bolts pass through its own cover", crossed[0] > 0)
