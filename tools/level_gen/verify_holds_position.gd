extends Node
## Test driver for EnemyLocal.holds_position, on world_playground.tscn. Run through godot.sh:
##   tools/level_gen/godot.sh test tools/level_gen/verify_holds_position.gd res://src/world/levels/world_playground.tscn <out_dir>
## One of each kind of enemy is posted 9 to 14 m from the carriers with holds_position on, plus one chaser without it
## as a control. They are woken for 8 s; the posted ones must not move (flyers may still rise to their hover height)
## yet still turn to face the carriers, and the shooters still fire. Then each takes a hit that would knock it back.
## Save tracking is disabled, so save.json stays untouched.

const POSTED := {
	"chaser": "res://src/enemy/enemy_aviator.tscn",
	"gunner": "res://src/enemy/enemy_aviator_gunner.tscn",
	"gun_shield": "res://src/enemy/enemy_aviator_gun_shield.tscn",
	"ground_mech": "res://src/enemy/enemy_ground_mech.tscn",
	"winged_mech": "res://src/enemy/enemy_winged_mech.tscn",
}
const CONTROL := "res://src/enemy/enemy_aviator.tscn"

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


func players() -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func spawn(path: String, at: Vector3, holds: bool) -> EnemyLocal:
	var enemy := (load(path) as PackedScene).instantiate() as EnemyLocal
	enemy.holds_position = holds
	enemy.is_offensive = false
	world.get_node("Enemies/Prototype/InstancedEnemies").add_child(enemy)
	var ground := NavigationServer3D.map_get_closest_point(enemy.navigation_agent.get_navigation_map(), at)
	enemy.global_position = Vector3(ground.x, enemy.global_position.y, ground.z)
	# Facing away from the carriers, so turning to face them shows.
	enemy.global_basis = Basis.looking_at(Vector3.FORWARD, Vector3.UP)
	return enemy


func facing_error(enemy: EnemyLocal) -> float:
	var target: Vector3 = players()[0].global_position
	var to := flat(target - enemy.global_position).normalized()
	var facing := flat(-enemy.global_basis.z).normalized()
	return rad_to_deg(acos(clampf(to.dot(facing), -1.0, 1.0)))


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.0)
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)
	for child in world.get_node("Enemies/Prototype/InstancedEnemies").get_children():
		child.free()
	var centre: Vector3 = players()[0].global_position
	var posted := {}
	var x := -8.0
	for kind in POSTED:
		posted[kind] = spawn(POSTED[kind], centre + Vector3(x, 0, -11.0), true)
		x += 4.0
	var control := spawn(CONTROL, centre + Vector3(0, 0, -14.0), false)
	await wait(2.5)  # past the Spawning state
	var starts := {}
	for kind in posted:
		starts[kind] = flat(posted[kind].global_position)
	var control_start := flat(control.global_position)
	var bolts := [0]
	get_tree().node_added.connect(func(n: Node): if n is FireballSpawn: bolts[0] += 1)
	for enemy in posted.values() + [control]:
		enemy.is_offensive = true
	await wait(8.0)
	get_tree().root.get_texture().get_image().save_png(out_dir + "/holding.png")
	check("the control chaser without the flag walks at the carriers", flat(control.global_position).distance_to(control_start) > 3.0,
		"%.1f m" % flat(control.global_position).distance_to(control_start))
	for kind in posted:
		var enemy: EnemyLocal = posted[kind]
		var moved: float = flat(enemy.global_position).distance_to(starts[kind])
		check(kind + " holds its spot", moved < 0.3, "moved %.2f m" % moved)
		check(kind + " still turns to face the carriers", facing_error(enemy) < 35.0, "%.0f° off" % facing_error(enemy))
	check("the posted shooters still fire", bolts[0] >= 3, "%d bolts" % bolts[0])
	await check_no_knockback(posted)
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


func check_no_knockback(posted: Dictionary) -> void:
	for kind in posted:
		var enemy: EnemyLocal = posted[kind]
		var start := flat(enemy.global_position)
		var health := Health.from_target(enemy)
		health.max_hp = 99
		health.reset_to_full()
		# Hit from behind its back, so a shield doesn't take it, then shoved hard.
		Health.apply_damage(enemy, 1, enemy.global_position + enemy.global_basis.z * 2.0)
		enemy.begin_knockback(12.0, 0.4, true)
		await wait(0.6)
		var moved := flat(enemy.global_position).distance_to(start)
		check(kind + " isn't knocked back by a hit", moved < 0.3, "moved %.2f m" % moved)
