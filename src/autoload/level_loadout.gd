extends Node
## Which weapon the menu chose for the next level. Empty means the weapon placed in the scene.
## Set on every level request, so a level started from the editor always plays as authored.

var weapon_id := ""


func set_weapon(p_weapon_id: String) -> void:
	weapon_id = p_weapon_id


func clear() -> void:
	weapon_id = ""
