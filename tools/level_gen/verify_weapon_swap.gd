extends Node
## Test driver for weapon swapping: loads one scene with every WeaponCatalog weapon in turn.
## Run through godot.sh with the scene to test, e.g.
## Respawns at every checkpoint with each weapon and checks the carriers stand and carry it there.
##   VERIFY_WEAPONS=bazooka,sword,saw tools/level_gen/godot.sh test tools/level_gen/verify_weapon_swap.gd res://src/world/levels/world_boss_scene.tscn <out_dir>
## VERIFY_WEAPONS lists the WeaponCatalog ids to try; without it, every weapon is tried.
## Skips applying saved progress and untracks the level at once, so save.json stays untouched.

var out_dir: String
var scene_path: String
var fails := 0


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	scene_path = get_tree().current_scene.scene_file_path
	get_tree().create_timer(900.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  [" + detail + "]"))
	if not ok:
		fails += 1


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


func _run() -> void:
	await _wait_for_first_scene()
	await _check_authored_weapon_untouched()
	for weapon in _weapons_to_test():
		await _check_weapon(weapon)
	LevelLoadout.clear()
	print("RESULT %s fails=%d" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(0 if fails == 0 else 1)


## Reloading before the first load finishes warming up spams errors from the freed scene.
func _wait_for_first_scene() -> void:
	var gsm := get_tree().current_scene.get_node("GameStateMachine") as GameStateMachine
	await wait_until(func(): return _state(gsm) == "playing", 30.0)


## Without a loadout the level must play exactly as authored, on its checkpoint markers.
func _check_authored_weapon_untouched() -> void:
	LevelLoadout.clear()
	var world: WorldLocal = await _load_world()
	check("authored: no weapon swapped", world.get_swapped_weapon_id().is_empty())
	var authored_key := GameSave.level_key(scene_path, world.get_active_weapon_id())
	check("authored: saves under its own weapon", world.get_level_id() == authored_key and authored_key.contains("@"), world.get_level_id())
	check("authored: one weapon", world.get_node("Weapon").get_child_count() == 1)
	var gsm := world.get_node("GameStateMachine") as GameStateMachine
	check("authored: reaches playing", await wait_until(func(): return _state(gsm) == "playing", 15.0), _state(gsm))


func _check_weapon(weapon: Dictionary) -> void:
	var id: String = weapon["id"]
	var fails_before := fails
	LevelLoadout.set_weapon(id)
	var world: WorldLocal = await _load_world()
	var expected_key := GameSave.level_key(scene_path, id)
	check(id + ": saves per weapon", world.get_level_id() == expected_key, world.get_level_id())
	var weapon_root := world.get_node("Weapon")
	check(id + ": one weapon", weapon_root.get_child_count() == 1, str(weapon_root.get_child_count()))
	var active := world.get_active_weapon()
	check(id + ": weapon is " + id, active != null and active.scene_file_path == weapon["scene"], "" if active == null else active.scene_file_path)
	var camera_rig := world.get_node("CameraFollowRig") as CameraFollowRig
	check(id + ": camera follows it", camera_rig.big_weapon == active)
	var gsm := world.get_node("GameStateMachine") as GameStateMachine
	var playing := await wait_until(func(): return _state(gsm) == "playing", 20.0)
	check(id + ": reaches playing", playing, _state(gsm))
	var manager := world.checkpoint_manager as CheckpointManager
	var checkpoints := _checkpoints_in_order(manager)
	for index in checkpoints.size():
		await _check_spawn(id, world, gsm, checkpoints[index], index == 0)
	print("SUMMARY %s %s" % [id, "OK" if fails == fails_before else "FAILED"])


## Respawns at the checkpoint (the first one is where the level starts) and checks the carriers.
func _check_spawn(id: String, world: WorldLocal, gsm: GameStateMachine, checkpoint: Checkpoint, is_start: bool) -> void:
	var label := "%s @ %s" % [id, checkpoint.get_save_id()]
	if not is_start:
		(world.checkpoint_manager as CheckpointManager).set_current_checkpoint_silent(checkpoint)
		gsm.transition_to("resettingcheckpoint")
		await wait_until(func(): return _state(gsm) != "playing", 2.0)
		var back := await wait_until(func(): return _state(gsm) == "playing", 20.0)
		check(label + ": respawns", back, _state(gsm))
	_protect_players(world)
	var expected_gap := _spawn_gap(world)
	await wait(1.5)
	_check_carry(label, world, checkpoint, expected_gap)
	check(label + ": no game over", not _state(gsm).begins_with("gameover"), _state(gsm))
	await shot("swap_%s_%s.png" % [id, checkpoint.get_save_id()])


func _checkpoints_in_order(manager: CheckpointManager) -> Array[Checkpoint]:
	var result: Array[Checkpoint] = []
	for child in manager.get_children():
		if child is Checkpoint:
			result.append(child)
	var start := manager.current_checkpoint
	result.sort_custom(func(a, b): return manager.get_progress_order(a) < manager.get_progress_order(b))
	result.erase(start)
	result.push_front(start)
	return result


func _load_world() -> WorldLocal:
	GameSave.set_apply_save_on_next_load(false)
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await wait_until(func(): return get_tree().current_scene is WorldLocal, 10.0)
	var world := get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	return world


## VERIFY_WEAPONS: comma-separated ids, "catalog" for the level's poster weapons, or empty for all.
func _weapons_to_test() -> Array[Dictionary]:
	var wanted := OS.get_environment("VERIFY_WEAPONS")
	if wanted.is_empty():
		return WeaponCatalog.WEAPONS
	if wanted == "catalog":
		wanted = ",".join(_catalog_weapons())
	var result: Array[Dictionary] = []
	for id in wanted.split(","):
		var weapon := WeaponCatalog.find(id.strip_edges())
		check("known weapon " + id, not weapon.is_empty())
		if not weapon.is_empty():
			result.append(weapon)
	return result


func _catalog_weapons() -> Array[String]:
	for group in LevelSelectCatalog.GROUPS:
		for level in group["levels"]:
			if level["scene"] == scene_path:
				return LevelSelectCatalog.weapons_for(level)
	check("level has a poster", false, scene_path)
	return []


## The checkpoint reset revives the players, which clears invulnerability, so grant it after.
func _protect_players(world: WorldLocal) -> void:
	for player in _players(world):
		player.get_node("Health").grant_invulnerability(9999.0)


## Ground distance between where the checkpoint manager says the two carriers stand.
func _spawn_gap(world: WorldLocal) -> float:
	var manager := world.checkpoint_manager as CheckpointManager
	var a := manager.get_spawn_transform().origin
	var b := manager.get_shooter_transform().origin
	return Vector2(a.x - b.x, a.z - b.z).length()


func _check_carry(label: String, world: WorldLocal, checkpoint: Checkpoint, expected: float) -> void:
	var list := _players(world)
	if checkpoint.is_carrying_weapon:
		check(label + ": both carrying", list.all(func(p): return _is_carrying(p)))
	var a: Vector3 = list[0].global_position
	var b: Vector3 = list[1].global_position
	var gap := Vector2(a.x - b.x, a.z - b.z).length()
	## A weapon's carry limits can pull carriers apart from the markers (the saw keeps at least 5.5 m).
	check(label + ": carriers spaced for the weapon", gap > 1.0 and gap < maxf(expected, 7.0) + 1.0, "gap %.2f markers %.2f" % [gap, expected])
	check(label + ": carriers on the floor", list.all(func(p): return p.is_on_floor()), "y %.2f / %.2f" % [a.y, b.y])

func _is_carrying(player: PlayerLocal) -> bool:
	var status: int = player.carrying_weapon_data.can_carry_status
	if status == CarryingWeaponData.CanCarryStatus.CARRYING_SHOOTER:
		return true
	return status == CarryingWeaponData.CanCarryStatus.CARRYING_DIRECTION_SETTER


func _players(world: WorldLocal) -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func _state(gsm: GameStateMachine) -> String:
	return "" if gsm.current == null else String(gsm.current.name).to_lower()
