extends Node
## Test driver for per-weapon save keys and the v2 -> v3 -> v4 migrations. Needs no level: pass any scene.
##   tools/level_gen/godot.sh test tools/level_gen/verify_save_keys.gd res://src/world/levels/world_boss_scene.tscn <out_dir>
## Touches no save file: it works on SaveMigration and LevelSelectCatalog directly.

const BOSS := "res://src/world/levels/world_boss_scene.tscn"
const LEVEL_1 := "res://src/world/levels/world_local.tscn"

var fails := 0


func _ready() -> void:
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  [" + detail + "]"))
	if not ok:
		fails += 1


func _run() -> void:
	_check_level_key()
	_check_migration()
	_check_catalog()
	print("RESULT %s fails=%d" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _check_level_key() -> void:
	check("key with weapon", GameSave.level_key(BOSS, "saw") == BOSS + "@saw")
	check("key without weapon", GameSave.level_key(BOSS, "") == BOSS)


func _check_migration() -> void:
	var v2 := {
		LEVEL_1: "Checkpoint3",
		"res://src/world/levels/world_boss_scene_sword.tscn": "Checkpoint",
		"res://src/world/levels/world_boss_scene_saw.tscn": "Checkpoint",
		BOSS: "Checkpoint",
		"some_unknown_level": "Checkpoint2",
	}
	var v3: Dictionary = SaveMigration.migrate_v2_keys(v2)
	check("level 1 moves to its bazooka key", v3.get(LEVEL_1 + "@bazooka") == "Checkpoint3", str(v3))
	check("sword boss moves to the merged scene", v3.get(BOSS + "@sword") == "Checkpoint")
	check("saw boss moves to the merged scene", v3.get(BOSS + "@saw") == "Checkpoint")
	check("bazooka boss gets its weapon", v3.get(BOSS + "@bazooka") == "Checkpoint")
	check("unknown keys are kept", v3.get("some_unknown_level") == "Checkpoint2")
	var old_level_2 := "res://src/world/levels/world_local_level_2.tscn"
	var new_level_2 := "res://src/world/levels/world_local_level_2_medieval.tscn"
	var v4: Dictionary = SaveMigration.migrate_v3_keys({old_level_2 + "@bazooka": true, old_level_2 + "@saw": true, BOSS + "@saw": true})
	check("level 2 progress moves to its reskin", v4.get(new_level_2 + "@bazooka") == true and v4.get(new_level_2 + "@saw") == true, str(v4))
	check("other v3 keys are kept", v4.get(BOSS + "@saw") == true and v4.size() == 3)
	var chained: Dictionary = SaveMigration.migrate_v3_keys(SaveMigration.migrate_v2_keys({old_level_2: "Checkpoint4"}))
	check("v2 level 2 progress reaches the reskin", chained.get(new_level_2 + "@bazooka") == "Checkpoint4", str(chained))
	check("no old keys left behind", not v3.has(LEVEL_1) and not v3.has(BOSS), str(v3.keys()))
	check("nothing lost", v3.size() == v2.size(), "%d -> %d" % [v2.size(), v3.size()])


## Every poster weapon must be in WeaponCatalog, and each level's old v2 progress must migrate to one of its
## keys: its own weapon's, or for a reskin that changed weapon, the weapon its original was played with.
## The sword and saw bosses are covered by the migration checks.
func _check_catalog() -> void:
	var migrated_keys: Array = SaveMigration.migrate_v3_keys(_as_keys(SaveMigration.V2_LEVEL_KEYS.values())).keys()
	for group in LevelSelectCatalog.GROUPS:
		for level in group["levels"]:
			_check_catalog_level(group["name"], level, migrated_keys)


func _check_catalog_level(group_name: String, level: Dictionary, migrated_keys: Array) -> void:
	var label := "%s / %s" % [group_name, level["title"]]
	var weapons := LevelSelectCatalog.weapons_for(level)
	for weapon_id in weapons:
		check(label + ": %s in catalog" % weapon_id, not WeaponCatalog.find(weapon_id).is_empty())
	var keys := weapons.map(func(id): return LevelSelectCatalog.save_id(level, id))
	var reached := keys.filter(func(key): return migrated_keys.has(key))
	check(label + ": old progress migrates here", not reached.is_empty(), str(keys[0]))
	_check_ranged_rule(label, level, weapons)


func _as_keys(values: Array) -> Dictionary:
	var result := {}
	for value in values:
		result[value] = true
	return result


func _check_ranged_rule(label: String, level: Dictionary, weapons: Array[String]) -> void:
	if level.get("requires", "") != "ranged":
		check(label + ": open to all 7 weapons", weapons.size() == WeaponCatalog.WEAPONS.size() - level.get("exclude", []).size(), str(weapons))
		return
	var melee := weapons.filter(func(id): return not WeaponCatalog.is_ranged(id))
	check(label + ": ranged only", melee.is_empty(), str(weapons))
