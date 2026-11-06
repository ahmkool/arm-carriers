class_name SaveMigration
extends RefCounted
## Renames save keys from older save versions. Pure: takes and returns plain dictionaries.

## Version 2 keyed progress by level id alone; version 3 adds the weapon ("<level id>@<weapon id>").
## Each level's id maps to the weapon placed in its scene. The sword and saw boss scenes were merged
## into world_boss_scene, so their progress moves there. Keys not listed here are kept as they were.
const V2_LEVEL_KEYS := {
	"res://src/world/levels/world_boss_scene.tscn": "res://src/world/levels/world_boss_scene.tscn@bazooka",
	"res://src/world/levels/world_boss_scene_saw.tscn": "res://src/world/levels/world_boss_scene.tscn@saw",
	"res://src/world/levels/world_boss_scene_sword.tscn": "res://src/world/levels/world_boss_scene.tscn@sword",
	"res://src/world/levels/world_dungeon_scene.tscn": "res://src/world/levels/world_dungeon_scene.tscn@bazooka",
	"res://src/world/levels/world_enemy_test.tscn": "res://src/world/levels/world_enemy_test.tscn@bazooka",
	"res://src/world/levels/world_enemy_test_2.tscn": "res://src/world/levels/world_enemy_test_2.tscn@bazooka",
	"res://src/world/levels/world_local.tscn": "res://src/world/levels/world_local.tscn@bazooka",
	"res://src/world/levels/world_local_02.tscn": "res://src/world/levels/world_local_02.tscn@sword",
	"res://src/world/levels/world_local_03.tscn": "res://src/world/levels/world_local_03.tscn@saw",
	"res://src/world/levels/world_local_bazooka.tscn": "res://src/world/levels/world_local_bazooka.tscn@bazooka",
	"res://src/world/levels/world_local_dark_dungeon.tscn": "res://src/world/levels/world_local_dark_dungeon.tscn@sword",
	"res://src/world/levels/world_local_katana_robot_boss.tscn": "res://src/world/levels/world_local_katana_robot_boss.tscn@pulse_rifle",
	"res://src/world/levels/world_local_lava.tscn": "res://src/world/levels/world_local_lava.tscn@catapult",
	"res://src/world/levels/world_local_level_2.tscn": "res://src/world/levels/world_local_level_2.tscn@bazooka",
	"res://src/world/levels/world_local_level_3.tscn": "res://src/world/levels/world_local_level_3.tscn@bazooka",
	"res://src/world/levels/world_local_necromancer_boss.tscn": "res://src/world/levels/world_local_necromancer_boss.tscn@sword",
	"res://src/world/levels/world_local_rotor_decks.tscn": "res://src/world/levels/world_local_rotor_decks.tscn@bazooka",
	"res://src/world/levels/world_local_saw.tscn": "res://src/world/levels/world_local_saw.tscn@saw",
	"res://src/world/levels/world_local_saw_carry.tscn": "res://src/world/levels/world_local_saw_carry.tscn@saw",
	"res://src/world/levels/world_local_shears.tscn": "res://src/world/levels/world_local_shears.tscn@shears",
	"res://src/world/levels/world_local_siege_bow.tscn": "res://src/world/levels/world_local_siege_bow.tscn@siege_bow",
	"res://src/world/levels/world_local_sky.tscn": "res://src/world/levels/world_local_sky.tscn@bazooka",
	"res://src/world/levels/world_local_space_station.tscn": "res://src/world/levels/world_local_space_station.tscn@pulse_rifle",
	"res://src/world/levels/world_local_sword.tscn": "res://src/world/levels/world_local_sword.tscn@sword",
	"res://src/world/levels/world_more_realistic_test.tscn": "res://src/world/levels/world_more_realistic_test.tscn@bazooka",
	"res://src/world/levels/world_moving_platforms_dev.tscn": "res://src/world/levels/world_moving_platforms_dev.tscn@bazooka",
	"res://src/world/levels/world_parallel_bridge_1.tscn": "res://src/world/levels/world_parallel_bridge_1.tscn@bazooka",
	"res://src/world/levels/world_social_side_scene.tscn": "res://src/world/levels/world_social_side_scene.tscn@bazooka",
	"res://src/world/levels/world_trailer_bridge_magicians.tscn": "res://src/world/levels/world_trailer_bridge_magicians.tscn@saw",
	"res://src/world/levels/world_trailer_mage_static_scene.tscn": "res://src/world/levels/world_trailer_mage_static_scene.tscn@sword",
	"res://src/world/levels/world_trailer_scene.tscn": "res://src/world/levels/world_trailer_scene.tscn@bazooka",
	"res://src/world/levels/world_trailer_sword_carry.tscn": "res://src/world/levels/world_trailer_sword_carry.tscn@sword",
}


## Returns `entries` with its v2 keys renamed.
static func migrate_v2_keys(entries: Dictionary) -> Dictionary:
	var result := {}
	for key in entries:
		result[V2_LEVEL_KEYS.get(key, key)] = entries[key]
	return result
