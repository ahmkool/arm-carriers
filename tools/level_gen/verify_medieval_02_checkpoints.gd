extends Node
## Test driver for the checkpoints of world_local_02_medieval.tscn ("Level 3"). Run through godot.sh, see
## docs/level-creation-for-agents.md. Respawns at every checkpoint and checks that no enemy is alive there (every
## earlier group defeated, every later one not yet spawned), that both carriers stand on the platform they were on
## when the checkpoint was earned, and that each waiting group appears only when its arrival trigger fires.
## Save tracking is disabled.

## Checkpoint -> where the carriers stand when it is earned: x and z ranges in metres, or [x, z, radius].
const ISLANDS := {
	"CheckpointWarmup": [-24.0, -6.0, 170.9, 188.9],
	"CheckpointHorde": [-24.0, -6.0, 170.9, 188.9],
	"CheckpointSkulls": [-27.0, -3.0, 147.0, 164.9],
	"CheckpointLabyrinth": [-13.4955, 136.356, 4.5],
	"CheckpointStart": [-18.0, -6.0, 51.0, 60.0],
	"Checkpoint": [-18.0, 0.0, 30.0, 45.0],
}
## Checkpoint -> the trigger that starts the next fight there, and the groups it spawns.
const NEXT_FIGHT := {
	"CheckpointHorde": ["Level/HordeArrival", ["Enemies/Horde"]],
	"CheckpointLabyrinth": ["Level/LabyrinthArrival", ["Enemies/LabyrinthMages", "Enemies/LabyrinthSkeletons"]],
	"CheckpointStart": ["Level/ArenaArrival", ["Enemies/MageTurretGroup"]],
}
## Alive at level start.
const START_ALIVE := ["Warmup: 10"]
## Checkpoints where the fight is already under way on respawn, so enemies may be alive.
const FIRST := "CheckpointWarmup"

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
	get_tree().create_timer(200.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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
	await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png(out_dir + "/" + file_name)


func players() -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func protect_players() -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)


## "Group: count" for every group with a living enemy.
func alive_enemies() -> Array[String]:
	var out: Array[String] = []
	for group in world.get_node("Enemies").get_children():
		var count := _alive_under(group)
		if count > 0:
			out.append("%s: %d" % [group.name, count])
	return out


func _alive_under(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is EnemyLocal and not child.is_queued_for_deletion() and child.is_alive():
			count += 1
		count += _alive_under(child)
	return count


func on_island(p: Node3D, bounds: Array) -> bool:
	var at := p.global_position
	if bounds.size() == 3:
		return Vector2(at.x - bounds[0], at.z - bounds[1]).length() < bounds[2]
	return at.x > bounds[0] and at.x < bounds[1] and at.z > bounds[2] and at.z < bounds[3]


## The trigger's centre has level floor under it, so carriers can stand in it.
func _area_has_floor(area: Area3D) -> bool:
	var shape := area.get_node("CollisionShape3D") as CollisionShape3D
	var at := shape.global_position
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 6.0, Checkpoint.LEVEL_COLLISION_LAYER)
	return not area.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func respawn_at(cp_name: String) -> void:
	world.checkpoint_manager.set_current_checkpoint(world.get_node("CheckpointManager/" + cp_name))
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(3.0)  # they drop from the checkpoint's height; a wrongly started wave would show by now
	protect_players()


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	await wait(1.0)
	check("level start: only the first group is in the level", alive_enemies() == START_ALIVE, str(alive_enemies()))

	for cp_name in ISLANDS:
		await respawn_at(cp_name)
		var bounds: Array = ISLANDS[cp_name]
		var where := players().map(func(p): return "%.1f, %.1f, %.1f" % [p.global_position.x, p.global_position.y, p.global_position.z])
		check(cp_name + ": both carriers on the island where it was earned", players().all(func(p): return on_island(p, bounds)), str(where))
		check(cp_name + ": both carriers on the floor", players().all(func(p): return p.is_on_floor() and p.global_position.y > -2.0), str(where))
		check(cp_name + ": game still playing", state() == "playing", state())
		if cp_name != FIRST:
			check(cp_name + ": no enemy alive", alive_enemies().is_empty(), str(alive_enemies()))
		await shot(cp_name.to_lower() + ".png")
		if not NEXT_FIGHT.has(cp_name):
			continue
		var fight: Array = NEXT_FIGHT[cp_name]
		var area := world.get_node(fight[0]) as AllPlayersAreaTrigger
		check(cp_name + ": " + area.name + " overlaps floor", _area_has_floor(area))
		area.all_players_inside.emit()
		await wait(0.5)
		for path in fight[1]:
			var group := world.get_node(path) as NormalEnemyGroup
			check(cp_name + ": " + group.name + " appears when its trigger fires", _alive_under(group) == group._enemy_snapshots.size(), str(alive_enemies()))

	print("RESULT fails=%d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
