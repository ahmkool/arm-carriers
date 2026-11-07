extends Node
## Test driver for strong shoves pushing small enemies off ledges, on world_local_siege_bow.tscn.
## Robots stand just inside the island's edge and are blasted outwards by the siege bow's
## shockwave and the pulse rifle's vent, called directly. Save tracking is disabled.
## Run through godot.sh, see docs/level-creation-for-agents.md.

const ENEMY_SCENE := "res://src/enemy/enemy_local.tscn"
## How far inside the walkable edge each robot stands, and how far behind it the blast goes off.
const INSIDE_EDGE := 0.8
const BLAST_BEHIND := 2.0
const DIRECTIONS := 16

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0
var nav_map: RID


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


func enemy_state(enemy: EnemyLocal) -> String:
	if not is_instance_valid(enemy) or enemy.enemy_state_machine.current_state == null:
		return ""
	return String(enemy.enemy_state_machine.current_state.name).to_lower()


func on_navmesh(point: Vector3) -> bool:
	var closest := NavigationServer3D.map_get_closest_point(nav_map, point)
	return Vector2(closest.x - point.x, closest.z - point.z).length() < 0.3


## The nearest walkable edge from `from`: the direction to it and how far away it is.
func find_edge(from: Vector3) -> Dictionary:
	var best := {"distance": INF, "direction": Vector3.ZERO}
	for i in DIRECTIONS:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / DIRECTIONS)
		var distance := 0.0
		while distance < 30.0 and on_navmesh(from + direction * distance):
			distance += 0.1
		if distance < best.distance:
			best = {"distance": distance, "direction": direction}
	return best


## Spawns a robot just inside the edge and waits for it to finish spawning.
func robot_at_edge(edge_point: Vector3, direction: Vector3) -> EnemyLocal:
	var enemy := (load(ENEMY_SCENE) as PackedScene).instantiate() as EnemyLocal
	world.get_node("Enemies").add_child(enemy)
	enemy.global_position = edge_point - direction * INSIDE_EDGE
	await wait_until(func(): return not ["", "spawning"].has(enemy_state(enemy)), 4.0)
	await pin(enemy, edge_point - direction * INSIDE_EDGE)
	return enemy


## Holds a robot in place so it doesn't walk off towards the players before the blast.
func pin(enemy: EnemyLocal, at: Vector3) -> void:
	enemy.speed = 0.0
	enemy.velocity = Vector3.ZERO
	enemy.global_position = Vector3(at.x, enemy.global_position.y, at.z)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	for p in world.players.get_children():
		if p is PlayerLocal:
			p.get_node("Health").grant_invulnerability(9999.0)
	await wait(0.5)
	var probe := (load(ENEMY_SCENE) as PackedScene).instantiate() as EnemyLocal
	world.get_node("Enemies").add_child(probe)
	nav_map = probe.navigation_agent.get_navigation_map()
	probe.queue_free()
	var start: Vector3 = (world.players.get_children().filter(func(c): return c is PlayerLocal)[0] as PlayerLocal).global_position
	var edge := find_edge(start)
	var direction: Vector3 = edge.direction
	var edge_point: Vector3 = start + direction * float(edge.distance)
	print("INFO nearest edge %.1f m from the players, towards %s" % [edge.distance, direction])
	await check_shockwave_ring_out(edge_point, direction)
	await check_vent_ring_out(edge_point, direction)
	await check_normal_hit_stays(edge_point, direction)
	await check_opted_out_stays(edge_point, direction)
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


func check_fell_and_died(label: String, enemy: EnemyLocal, floor_y: float) -> void:
	var died: bool = await wait_until(func(): return not enemy.is_alive(), 5.0)
	var y := enemy.global_position.y if is_instance_valid(enemy) else NAN
	check(label, died and y < floor_y - EnemyLocal.FALL_DEATH_DEPTH + 0.5, "died=%s y=%.1f floor=%.1f state=%s" % [died, y, floor_y, enemy_state(enemy)])


func check_stayed_on_ledge(label: String, enemy: EnemyLocal, floor_y: float) -> void:
	await wait(1.5)
	var y := enemy.global_position.y
	check(label, enemy.is_alive() and absf(y - floor_y) < 0.5 and on_navmesh(enemy.global_position), "alive=%s y=%.1f floor=%.1f" % [enemy.is_alive(), y, floor_y])


func check_shockwave_ring_out(edge_point: Vector3, direction: Vector3) -> void:
	var robot := await robot_at_edge(edge_point, direction)
	var floor_y := robot.global_position.y
	var hits := BowShockwave.blast(get_viewport().world_3d, robot.global_position - direction * BLAST_BEHIND)
	check("the shockwave hits the robot at the edge", hits == 1, str(hits))
	await wait(0.25)
	check("the robot is carried past the walkable edge", not on_navmesh(robot.global_position))
	await shot("ledge_shove_shockwave.png")
	await check_fell_and_died("a robot shoved off the ledge by the shockwave falls and dies", robot, floor_y)


func check_vent_ring_out(edge_point: Vector3, direction: Vector3) -> void:
	var robot := await robot_at_edge(edge_point, direction)
	var floor_y := robot.global_position.y
	# A weak vent, so the shove does the work rather than the damage.
	var heat := 0.3
	check("a 30% vent doesn't kill a full-health robot", PulseVent.get_damage(heat) < Health.from_target(robot).current_hp)
	var hits := PulseVent.blast(get_viewport().world_3d, robot.global_position - direction * BLAST_BEHIND, direction, heat)
	check("the vent hits the robot at the edge", hits == 1, str(hits))
	await check_fell_and_died("a robot shoved off the ledge by a vent falls and dies", robot, floor_y)


func check_normal_hit_stays(edge_point: Vector3, direction: Vector3) -> void:
	var robot := await robot_at_edge(edge_point, direction)
	var floor_y := robot.global_position.y
	Health.apply_damage(robot, 1, robot.global_position - direction)
	await check_stayed_on_ledge("an ordinary hit still stops at the edge", robot, floor_y)
	Health.from_target(robot).kill()


## Bosses turn `can_fall_off_ledges` off; a robot with it off stands in for one here.
func check_opted_out_stays(edge_point: Vector3, direction: Vector3) -> void:
	var robot := await robot_at_edge(edge_point, direction)
	robot.can_fall_off_ledges = false
	var floor_y := robot.global_position.y
	BowShockwave.blast(get_viewport().world_3d, robot.global_position - direction * BLAST_BEHIND)
	await check_stayed_on_ledge("an enemy that can't fall off ledges stops at the edge", robot, floor_y)
	var boss := (load("res://src/enemy/enemy_frost_golem.tscn") as PackedScene).instantiate() as EnemyLocal
	check("the frost golem can't be pushed off ledges", not boss.can_fall_off_ledges)
	boss.free()
