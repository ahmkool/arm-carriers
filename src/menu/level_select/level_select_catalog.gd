class_name LevelSelectCatalog
extends RefCounted
## The levels offered by the level select, grouped into the tabs players switch between.
## Level ids match the ones already stored in save files, so progress carries over.

enum Art { SKELETON, HORDE, BOSS }

const GROUPS: Array[Dictionary] = [
	{
		"name": "Start here",
		"levels": [
			{"title": "Level 1", "difficulty": 1, "label": "Easy", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local.tscn"},
			{"title": "Level 2", "difficulty": 2, "label": "Medium", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_level_2.tscn"},
		],
	},
	{
		"name": "Bazooka",
		"levels": [
			{"title": "Gauntlet", "difficulty": 2, "label": "Medium", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_bazooka.tscn"},
			{"title": "Survival", "difficulty": 4, "label": "Impossible", "art": Art.HORDE, "scene": "res://src/world/levels/world_trailer_scene.tscn"},
			{"title": "Boss", "difficulty": 3, "label": "Boss", "art": Art.BOSS, "scene": "res://src/world/levels/world_boss_scene.tscn"},
		],
	},
	{
		"name": "Sword",
		"levels": [
			{"title": "Gauntlet", "difficulty": 2, "label": "Medium", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_sword.tscn"},
			{"title": "Survival", "difficulty": 3, "label": "Hard", "art": Art.HORDE, "scene": "res://src/world/levels/world_local_02.tscn"},
			{"title": "Boss", "difficulty": 3, "label": "Boss", "art": Art.BOSS, "scene": "res://src/world/levels/world_boss_scene_sword.tscn"},
		],
	},
	{
		"name": "Saw",
		"levels": [
			{"title": "Gauntlet", "difficulty": 2, "label": "Medium", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_saw.tscn"},
			{"title": "Survival", "difficulty": 3, "label": "Hard", "art": Art.HORDE, "scene": "res://src/world/levels/world_local_saw_carry.tscn"},
			{"title": "Boss", "difficulty": 3, "label": "Boss", "art": Art.BOSS, "scene": "res://src/world/levels/world_boss_scene_saw.tscn"},
		],
	},
	{
		"name": "Prototypes",
		"levels": [
			{"title": "Sky Islands", "difficulty": 2, "label": "Prototype", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_sky.tscn"},
			{"title": "Dark Dungeon", "difficulty": 2, "label": "Prototype", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_dark_dungeon.tscn"},
			{"title": "Necromancer", "difficulty": 3, "label": "Boss", "art": Art.BOSS, "scene": "res://src/world/levels/world_local_necromancer_boss.tscn"},
		],
	},
	{
		"name": "Prototypes 2",
		"levels": [
			{"title": "Lava Forge", "difficulty": 2, "label": "Prototype", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_lava.tscn"},
			{"title": "Rotor Decks", "difficulty": 2, "label": "Prototype", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_rotor_decks.tscn"},
			{"title": "Space Station", "difficulty": 2, "label": "Prototype", "art": Art.SKELETON, "scene": "res://src/world/levels/world_local_space_station.tscn"},
		],
	},
	{
		"name": "Prototypes 3",
		"levels": [
			{"title": "4GTN", "difficulty": 3, "label": "Boss", "art": Art.BOSS, "scene": "res://src/world/levels/world_local_katana_robot_boss.tscn"},
		],
	},
]
