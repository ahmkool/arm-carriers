extends Node
## Checks the Dev tab: shown in dev mode only, always open, every weapon offered.
## Run against res://src/menu/menu.tscn through godot.sh. It flips DevSettings in memory only.


var fails := 0


func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  [" + detail + "]"))
	if not ok:
		fails += 1


func _ready() -> void:
	await get_tree().process_frame
	var config: DevSettingsConfig = DevSettings._config
	var was_enabled := config.enabled
	var was_unlocked := config.unlock_all_levels
	config.unlock_all_levels = false

	config.enabled = true
	var groups := LevelSelectCatalog.groups()
	var dev_index := groups.size() - 1
	check("dev mode adds the Dev tab last", groups.size() == LevelSelectCatalog.GROUPS.size() + 1 and groups[dev_index]["name"] == "Dev", "%d tabs" % groups.size())
	check("Dev tab is open without unlock_all_levels", LevelSelectCatalog.is_group_open(dev_index))
	check("playground poster is open", LevelSelectCatalog.is_level_open(dev_index, 0) and LevelSelectCatalog.lock_reason(dev_index, 0).is_empty())
	var playground: Dictionary = groups[dev_index]["levels"][0]
	var offered := LevelSelectCatalog.offered_weapons(playground)
	check("every weapon offered", offered.size() == WeaponCatalog.WEAPONS.size(), ", ".join(offered))

	config.enabled = false
	check("no Dev tab outside dev mode", LevelSelectCatalog.groups().size() == LevelSelectCatalog.GROUPS.size(), "%d tabs" % LevelSelectCatalog.groups().size())
	check("playground not findable outside dev mode", LevelSelectCatalog._level_for_scene(LevelSelectCatalog.PLAYGROUND).is_empty())

	config.enabled = was_enabled
	config.unlock_all_levels = was_unlocked
	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
