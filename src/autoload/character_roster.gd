extends Node
## The playable characters and who each player picked in the character select.
## Levels started without the menu fall back to the `character_scenes` set on `Players`.

const CHARACTERS: Array[Dictionary] = [
	{"name": "Knight", "scene": preload("res://src/player/characters/knight.tscn"), "icon": preload("res://assets/sprites/ui/icons/knight_icon.png")},
	{"name": "Ranger", "scene": preload("res://src/player/characters/ranger.tscn"), "icon": preload("res://assets/sprites/ui/icons/ranger_icon.png")},
	{"name": "Barbarian", "scene": preload("res://src/player/characters/barbarian.tscn"), "icon": preload("res://assets/sprites/ui/icons/barbarian_icon.png")},
	{"name": "Mage", "scene": preload("res://src/player/characters/mage.tscn"), "icon": preload("res://assets/sprites/ui/icons/mage_icon.png")},
	{"name": "Rogue", "scene": preload("res://src/player/characters/rogue.tscn"), "icon": preload("res://assets/sprites/ui/icons/rogue_icon.png")},
	{"name": "Hooded Rogue", "scene": preload("res://src/player/characters/rogue_hooded.tscn"), "icon": preload("res://assets/sprites/ui/icons/rogue_hooded_icon.png")},
	{"name": "Druid", "scene": preload("res://src/player/characters/druid.tscn"), "icon": preload("res://assets/sprites/ui/icons/druid_icon.png")},
	{"name": "Engineer", "scene": preload("res://src/player/characters/engineer.tscn"), "icon": preload("res://assets/sprites/ui/icons/engineer_icon.png")},
]
const PLAYER_COUNT := 2
const DEFAULT_PICKS: Array[int] = [0, 1]


## Saves the picks so the next Play goes straight to the level select.
func set_picks(first: int, second: int) -> void:
	if first == second:
		push_error("CharacterRoster: both players picked character %d." % first)
		return
	var names: Array[String] = [CHARACTERS[first]["name"], CHARACTERS[second]["name"]]
	GameSave.set_character_picks(names)


## True once both players have a saved, still valid and different character.
func has_picks() -> bool:
	var first := _saved_pick(0)
	var second := _saved_pick(1)
	if first < 0 or second < 0:
		return false
	return first != second


## The saved pick for the device, or its default. Used to place the cursors when the select opens.
func remembered_pick(device_id: int) -> int:
	if not has_picks():
		return DEFAULT_PICKS[device_id]
	return _saved_pick(device_id)


## Null when the players never went through the character select.
func scene_for_device(device_id: int) -> PackedScene:
	if device_id < 0 or device_id >= PLAYER_COUNT:
		return null
	if not has_picks():
		return null
	return CHARACTERS[_saved_pick(device_id)]["scene"]


## Index into CHARACTERS of the saved name, or -1 when missing or no longer in the roster.
func _saved_pick(device_id: int) -> int:
	var names := GameSave.get_character_picks()
	if device_id >= names.size():
		return -1
	for index in CHARACTERS.size():
		if CHARACTERS[index]["name"] == names[device_id]:
			return index
	return -1
