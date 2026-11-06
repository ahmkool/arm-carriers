extends Node
## Test driver for per-weapon save keys and the v2 -> v3 migration. Needs no level: pass any scene.
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
	check("no old keys left behind", not v3.has(LEVEL_1) and not v3.has(BOSS), str(v3.keys()))
	check("nothing lost", v3.size() == v2.size(), "%d -> %d" % [v2.size(), v3.size()])


## Every poster weapon must be in WeaponCatalog, and each level's old v2 progress (made with its own
## weapon) must migrate to that weapon's key. The sword and saw bosses are covered by the migration checks.
func _check_catalog() -> void:
	var migrated_keys: Array = SaveMigration.V2_LEVEL_KEYS.values()
	for group in LevelSelectCatalog.GROUPS:
		for level in group["levels"]:
			_check_catalog_level(group["name"], level, migrated_keys)


func _check_catalog_level(group_name: String, level: Dictionary, migrated_keys: Array) -> void:
	var label := "%s / %s" % [group_name, level["title"]]
	var weapons := LevelSelectCatalog.weapons_for(level)
	for weapon_id in weapons:
		check(label + ": %s in catalog" % weapon_id, not WeaponCatalog.find(weapon_id).is_empty())
	var key := LevelSelectCatalog.save_id(level, level["weapon"])
	check(label + ": old progress migrates here", migrated_keys.has(key), key)
	_check_ranged_rule(label, level, weapons)


func _check_ranged_rule(label: String, level: Dictionary, weapons: Array[String]) -> void:
	if level.get("requires", "") != "ranged":
		check(label + ": open to all 7 weapons", weapons.size() == WeaponCatalog.WEAPONS.size() - level.get("exclude", []).size(), str(weapons))
		return
	var melee := weapons.filter(func(id): return not WeaponCatalog.is_ranged(id))
	check(label + ": ranged only", melee.is_empty(), str(weapons))
