class_name LevelSelectCatalog
extends RefCounted
## The levels offered by the level select, grouped into the tabs players switch between.
##
## Story worlds come in play order, each ending on its boss:
## - The first level of the first world is always open.
## - Clearing a level opens the next one in its world.
## - Slaying a world's boss (its last level) opens the next world.
## A group with "challenge": true is not part of that chain. It opens once its "unlock_after" level
## is cleared, and then all its levels are open.
##
## Each level can be played with every WeaponCatalog weapon, except:
## - "requires": "ranged" limits it to ranged weapons, for levels with enemies the carriers cannot
##   walk to. Levels built for a ranged weapon have it, since nobody has checked they can be beaten
##   on foot.
## - "exclude" lists weapons known not to work there.
## "weapon" is the one placed in the scene. It comes first and is picked by default. Until the
## level is cleared once it is the only weapon offered; clearing it opens the others.
## Progress is saved per level and weapon (see GameSave.level_key).
## DEV_GROUPS are added after these only in dev mode (DevSettings active: editor or debug build).
## Use groups(), not GROUPS, for what the level select shows.

enum Art { SKELETON, HORDE, BOSS }

const DUNGEON_BOSS := "res://src/world/levels/world_boss_scene.tscn"
const PLAYGROUND := "res://src/world/levels/world_playground.tscn"

const GROUPS: Array[Dictionary] = [
	{
		"name": "Dungeon",
		"levels": [
			{"title": "Level 1", "difficulty": 1, "label": "Easy", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local.tscn", "weapon": "bazooka", "requires": "ranged"},
			{"title": "Level 2", "difficulty": 1, "label": "Easy", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_level_2_medieval.tscn", "weapon": "siege_bow", "requires": "ranged"},
			{"title": "Gauntlet", "difficulty": 2, "label": "Medium", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_bazooka.tscn", "weapon": "bazooka", "requires": "ranged"},
			{"title": "Skeleton Boss", "difficulty": 2, "label": "Boss", "art": Art.BOSS, "scene": DUNGEON_BOSS, "weapon": "bazooka"},
		],
	},
	{
		"name": "Crypt",
		"levels": [
			{"title": "Dark Dungeon", "difficulty": 2, "label": "Medium", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_dark_dungeon.tscn", "weapon": "sword"},
			{"title": "Blade Hall", "difficulty": 2, "label": "Medium", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_sword.tscn", "weapon": "sword"},
			{"title": "Saw Mill", "difficulty": 2, "label": "Medium", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_saw.tscn", "weapon": "saw"},
			{"title": "Necromancer", "difficulty": 3, "label": "Boss", "art": Art.BOSS, "scene": "res://src/world/levels/world_local_necromancer_boss.tscn", "weapon": "sword"},
		],
	},
	{
		"name": "Frozen Shore",
		"levels": [
			{"title": "Frozen Shore", "difficulty": 2, "label": "Medium", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_snow.tscn", "weapon": "sword"},
			{"title": "Frost Golem", "difficulty": 3, "label": "Boss", "art": Art.BOSS, "scene": "res://src/world/levels/world_local_frost_golem_boss.tscn", "weapon": "sword"},
		],
	},
	{
		"name": "Lava Forge",
		"levels": [
			{"title": "Lava Forge", "difficulty": 3, "label": "Hard", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_lava.tscn", "weapon": "catapult", "requires": "ranged"},
			{"title": "The Clanker", "difficulty": 3, "label": "Boss", "art": Art.BOSS, "scene": "res://src/world/levels/world_local_clanker_boss.tscn", "weapon": "catapult", "requires": "ranged"},
		],
	},
	{
		"name": "Sky Station",
		"levels": [
			{"title": "Sky Islands", "difficulty": 3, "label": "Hard", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_sky.tscn", "weapon": "bazooka", "requires": "ranged"},
			{"title": "Rotor Decks", "difficulty": 3, "label": "Hard", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_rotor_decks.tscn", "weapon": "bazooka", "requires": "ranged"},
			{"title": "Space Station", "difficulty": 3, "label": "Hard", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_space_station.tscn", "weapon": "pulse_rifle", "requires": "ranged"},
			{"title": "Sky Barge", "difficulty": 2, "label": "Medium", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_sky_station.tscn", "weapon": "fork_cannon", "requires": "ranged"},
			{"title": "4GTN", "difficulty": 4, "label": "Boss", "art": Art.BOSS, "scene": "res://src/world/levels/world_local_katana_robot_boss.tscn", "weapon": "pulse_rifle", "requires": "ranged"},
		],
	},
	{
		"name": "Challenges",
		"challenge": true,
		"unlock_after": DUNGEON_BOSS,
		"levels": [
			{"title": "Survival", "difficulty": 3, "label": "Hard", "art": Art.HORDE, "scene": "res://src/world/levels/world_local_02.tscn", "weapon": "sword"},
			{"title": "Survival", "difficulty": 3, "label": "Hard", "art": Art.HORDE, "scene": "res://src/world/levels/world_local_saw_carry.tscn", "weapon": "saw"},
			{"title": "Survival", "difficulty": 4, "label": "Impossible", "art": Art.HORDE, "scene": "res://src/world/levels/world_trailer_scene.tscn", "weapon": "bazooka", "requires": "ranged"},
		],
	},
]

## Sandboxes for prototyping, shown only in dev mode. Always open, outside every unlock chain, and
## every weapon is offered ("all_weapons"). Their scenes set skip_save, so they never count as cleared.
const DEV_GROUPS: Array[Dictionary] = [
	{
		"name": "Dev",
		"dev": true,
		"levels": [
			{"title": "Playground", "difficulty": 1, "label": "Dev", "art": Art.SKELETON, "scene": PLAYGROUND, "weapon": "bazooka", "all_weapons": true},
			{"title": "Spike Trap", "difficulty": 2, "label": "Dev", "art": Art.HORDE, "scene": "res://src/world/levels/world_spike_trap_prototype.tscn", "weapon": "bazooka", "all_weapons": true},
			{"title": "Sky Station II", "difficulty": 2, "label": "Dev", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_sky_station_2.tscn", "weapon": "fork_cannon", "requires": "ranged"},
		],
	},
]

## Opens every level and weapon, for test drivers. Players get the same with DevSettings'
## unlock_all_levels in debug builds.
static var force_unlock_all := false


## The groups the level select shows: GROUPS, plus DEV_GROUPS in dev mode.
static func groups() -> Array[Dictionary]:
	if not DevSettings.is_active():
		return GROUPS
	var all: Array[Dictionary] = GROUPS.duplicate()
	all.append_array(DEV_GROUPS)
	return all


## The key the level's checkpoint and completion are saved under when played with this weapon.
static func save_id(level: Dictionary, weapon_id: String) -> String:
	return GameSave.level_key(level["scene"], weapon_id)


## Every weapon the level can be played with: its own first, then the others in catalog order.
static func weapons_for(level: Dictionary) -> Array[String]:
	var own: String = level["weapon"]
	var result: Array[String] = [own]
	for weapon in WeaponCatalog.WEAPONS:
		if _offers(level, weapon["id"]):
			result.append(weapon["id"])
	return result


## The weapons players may pick right now: only the level's own until it has been cleared once.
static func offered_weapons(level: Dictionary) -> Array[String]:
	if unlocks_all() or level.get("all_weapons", false) or is_cleared(level):
		return weapons_for(level)
	var own: Array[String] = [level["weapon"]]
	return own


## Cleared with any weapon.
static func is_cleared(level: Dictionary) -> bool:
	for weapon_id in weapons_for(level):
		if GameSave.is_level_completed(save_id(level, weapon_id)):
			return true
	return false


static func cleared_count(group_index: int) -> int:
	var count := 0
	for level in groups()[group_index]["levels"]:
		if is_cleared(level):
			count += 1
	return count


static func is_group_open(group_index: int) -> bool:
	if unlocks_all() or group_index == 0:
		return true
	var group: Dictionary = groups()[group_index]
	if group.get("dev", false):
		return true
	if group.get("challenge", false):
		return _is_scene_cleared(group["unlock_after"])
	var previous := _previous_story_group(group_index)
	if previous < 0:
		return true
	return is_cleared(groups()[previous]["levels"].back())


static func is_level_open(group_index: int, level_index: int) -> bool:
	if not is_group_open(group_index):
		return false
	if level_index == 0 or unlocks_all():
		return true
	if _is_outside_story(groups()[group_index]):
		return true
	return is_cleared(groups()[group_index]["levels"][level_index - 1])


## What players must do to open a locked level, for its poster. Empty when it is open.
static func lock_reason(group_index: int, level_index: int) -> String:
	if is_level_open(group_index, level_index):
		return ""
	if not is_group_open(group_index):
		return _group_lock_reason(group_index)
	return _beat_text(groups()[group_index]["levels"][level_index - 1])


static func unlocks_all() -> bool:
	return force_unlock_all or DevSettings.unlocks_all_levels()


static func _group_lock_reason(group_index: int) -> String:
	var group: Dictionary = groups()[group_index]
	if group.get("challenge", false):
		return _beat_text(_level_for_scene(group["unlock_after"]))
	return _beat_text(groups()[_previous_story_group(group_index)]["levels"].back())


static func _beat_text(level: Dictionary) -> String:
	if level.is_empty():
		return "Locked"
	var verb := "Slay " if level["art"] == Art.BOSS else "Clear "
	return verb + String(level["title"])


static func _previous_story_group(group_index: int) -> int:
	for index in range(group_index - 1, -1, -1):
		if not _is_outside_story(groups()[index]):
			return index
	return -1


static func _is_scene_cleared(scene: String) -> bool:
	var level := _level_for_scene(scene)
	if level.is_empty():
		return false
	return is_cleared(level)


static func _level_for_scene(scene: String) -> Dictionary:
	for group in groups():
		for level in group["levels"]:
			if level["scene"] == scene:
				return level
	return {}


## Challenge and dev groups are not part of the story's unlock chain.
static func _is_outside_story(group: Dictionary) -> bool:
	return group.get("challenge", false) or group.get("dev", false)


static func _offers(level: Dictionary, weapon_id: String) -> bool:
	if weapon_id == level["weapon"]:
		return false
	if level.get("exclude", []).has(weapon_id):
		return false
	if level.get("requires", "") == "ranged":
		return WeaponCatalog.is_ranged(weapon_id)
	return true
