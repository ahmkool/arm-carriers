class_name LevelSelectCatalog
extends RefCounted
## The levels offered by the level select, grouped into the tabs players switch between.
## Each level can be played with every WeaponCatalog weapon, except:
## - "requires": "ranged" limits it to ranged weapons, for levels with enemies the carriers cannot
##   walk to. Levels built for a ranged weapon have it, since nobody has checked they can be beaten
##   on foot.
## - "exclude" lists weapons known not to work there.
## "weapon" is the one placed in the scene. It comes first and is picked by default.
## Progress is saved per level and weapon (see GameSave.level_key).

enum Art { SKELETON, HORDE, BOSS }

const GROUPS: Array[Dictionary] = [
	{
		"name": "Start here",
		"levels": [
			{"title": "Level 1", "difficulty": 1, "label": "Easy", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local.tscn", "weapon": "bazooka", "requires": "ranged"},
			{"title": "Level 2", "difficulty": 2, "label": "Medium", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_level_2.tscn", "weapon": "bazooka", "requires": "ranged"},
		],
	},
	{
		"name": "Gauntlets",
		"levels": [
			{"title": "Gauntlet", "difficulty": 2, "label": "Medium", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_bazooka.tscn", "weapon": "bazooka", "requires": "ranged"},
			{"title": "Gauntlet", "difficulty": 2, "label": "Medium", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_sword.tscn", "weapon": "sword"},
			{"title": "Gauntlet", "difficulty": 2, "label": "Medium", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_saw.tscn", "weapon": "saw"},
		],
	},
	{
		"name": "Survival",
		"levels": [
			{"title": "Survival", "difficulty": 4, "label": "Impossible", "art": Art.HORDE, "scene": "res://src/world/levels/world_trailer_scene.tscn", "weapon": "bazooka", "requires": "ranged"},
			{"title": "Survival", "difficulty": 3, "label": "Hard", "art": Art.HORDE, "scene": "res://src/world/levels/world_local_02.tscn", "weapon": "sword"},
			{"title": "Survival", "difficulty": 3, "label": "Hard", "art": Art.HORDE, "scene": "res://src/world/levels/world_local_saw_carry.tscn", "weapon": "saw"},
		],
	},
	{
		"name": "Bosses",
		"levels": [
			{"title": "Skeleton Boss", "difficulty": 3, "label": "Boss", "art": Art.BOSS, "scene": "res://src/world/levels/world_boss_scene.tscn", "weapon": "bazooka"},
			{"title": "Necromancer", "difficulty": 3, "label": "Boss", "art": Art.BOSS, "scene": "res://src/world/levels/world_local_necromancer_boss.tscn", "weapon": "sword"},
			{"title": "4GTN", "difficulty": 3, "label": "Boss", "art": Art.BOSS, "scene": "res://src/world/levels/world_local_katana_robot_boss.tscn", "weapon": "pulse_rifle", "requires": "ranged"},
		],
	},
	{
		"name": "Bosses 2",
		"levels": [
			{"title": "Frost Golem", "difficulty": 3, "label": "Boss", "art": Art.BOSS, "scene": "res://src/world/levels/world_local_frost_golem_boss.tscn", "weapon": "sword"},
		],
	},
	{
		"name": "Prototypes",
		"levels": [
			{"title": "Sky Islands", "difficulty": 2, "label": "Prototype", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_sky.tscn", "weapon": "bazooka", "requires": "ranged"},
			{"title": "Dark Dungeon", "difficulty": 2, "label": "Prototype", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_dark_dungeon.tscn", "weapon": "sword"},
			{"title": "Lava Forge", "difficulty": 2, "label": "Prototype", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_lava.tscn", "weapon": "catapult", "requires": "ranged"},
		],
	},
	{
		"name": "Prototypes 2",
		"levels": [
			{"title": "Rotor Decks", "difficulty": 2, "label": "Prototype", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_rotor_decks.tscn", "weapon": "bazooka", "requires": "ranged"},
			{"title": "Space Station", "difficulty": 2, "label": "Prototype", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_space_station.tscn", "weapon": "pulse_rifle", "requires": "ranged"},
			{"title": "Frozen Shore", "difficulty": 2, "label": "Prototype", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_snow.tscn", "weapon": "sword"},
		],
	},
]


## The key the level's checkpoint and completion are saved under when played with this weapon.
static func save_id(level: Dictionary, weapon_id: String) -> String:
	return GameSave.level_key(level["scene"], weapon_id)


## The weapons the level can be played with: its own first, then the others in catalog order.
static func weapons_for(level: Dictionary) -> Array[String]:
	var own: String = level["weapon"]
	var result: Array[String] = [own]
	for weapon in WeaponCatalog.WEAPONS:
		if _offers(level, weapon["id"]):
			result.append(weapon["id"])
	return result


static func _offers(level: Dictionary, weapon_id: String) -> bool:
	if weapon_id == level["weapon"]:
		return false
	if level.get("exclude", []).has(weapon_id):
		return false
	if level.get("requires", "") == "ranged":
		return WeaponCatalog.is_ranged(weapon_id)
	return true
