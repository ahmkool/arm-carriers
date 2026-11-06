extends Node
## The big weapons a level can be played with, and where their carriers stand.
## Spawn offsets are local to a checkpoint (forward is -Z). They are used only when a level is
## played with a weapon other than the one placed in the scene; otherwise the checkpoint markers win.
## "ranged" weapons can hit enemies the carriers cannot walk to, such as ones on other platforms.

const WEAPONS: Array[Dictionary] = [
	{"id": "bazooka", "name": "Bazooka", "ranged": true, "scene": "res://src/weapon/bazooka.tscn", "icon": "res://assets/sprites/ui/icons/weapons/bazooka.png", "setter_offset": Vector3(0.0, 0.0, -0.5083), "shooter_offset": Vector3(0.0, 0.0, 2.1002)},
	{"id": "sword", "name": "Sword", "ranged": false, "scene": "res://src/weapon/sword.tscn", "icon": "res://assets/sprites/ui/icons/weapons/sword.png", "setter_offset": Vector3(0.0, 0.0, -0.5083), "shooter_offset": Vector3(0.0, 0.0, 2.1002)},
	{"id": "saw", "name": "Saw", "ranged": false, "scene": "res://src/weapon/saw.tscn", "icon": "res://assets/sprites/ui/icons/weapons/saw.png", "setter_offset": Vector3(-3.0, 0.0, 0.0), "shooter_offset": Vector3(3.0, 0.0, 0.0)},
	{"id": "catapult", "name": "Catapult", "ranged": true, "scene": "res://src/weapon/catapult.tscn", "icon": "res://assets/sprites/ui/icons/weapons/catapult.png", "setter_offset": Vector3(0.0, 0.0, -2.25), "shooter_offset": Vector3(0.0, 0.0, 2.25)},
	{"id": "pulse_rifle", "name": "Pulse Rifle", "ranged": true, "scene": "res://src/weapon/pulse_rifle.tscn", "icon": "res://assets/sprites/ui/icons/weapons/pulse_rifle.png", "setter_offset": Vector3(0.0, 0.0, -0.5083), "shooter_offset": Vector3(0.0, 0.0, 2.1002)},
	{"id": "siege_bow", "name": "Siege Bow", "ranged": true, "scene": "res://src/weapon/siege_bow.tscn", "icon": "res://assets/sprites/ui/icons/weapons/siege_bow.png", "setter_offset": Vector3(0.0, 0.0, -0.5083), "shooter_offset": Vector3(0.0, 0.0, 2.1002)},
	{"id": "shears", "name": "Shears", "ranged": false, "scene": "res://src/weapon/shears.tscn", "icon": "res://assets/sprites/ui/icons/weapons/shears.png", "setter_offset": Vector3(2.5, 0.0, 0.0), "shooter_offset": Vector3(-2.5, 0.0, 0.0)},
]


## The weapon entry with this id, or an empty dictionary.
func find(weapon_id: String) -> Dictionary:
	for weapon in WEAPONS:
		if weapon["id"] == weapon_id:
			return weapon
	return {}


func is_ranged(weapon_id: String) -> bool:
	return find(weapon_id).get("ranged", false)


## The weapon's level select icon, rendered by tools/weapons/render_weapon_icons.gd.
func icon(weapon_id: String) -> Texture2D:
	var weapon := find(weapon_id)
	if weapon.is_empty():
		return null
	return load(weapon["icon"]) as Texture2D


## The weapon's display name, or its id if it is not in the catalog.
func display_name(weapon_id: String) -> String:
	var weapon := find(weapon_id)
	if weapon.is_empty():
		return weapon_id
	return weapon["name"]


## The id of the weapon whose scene is at this path, or "" if it is not in the catalog.
func id_for_scene_path(scene_path: String) -> String:
	for weapon in WEAPONS:
		if weapon["scene"] == scene_path:
			return weapon["id"]
	return ""


func instantiate(weapon_id: String) -> BigWeapon:
	var weapon := find(weapon_id)
	if weapon.is_empty():
		push_error("WeaponCatalog: unknown weapon id '%s'." % weapon_id)
		return null
	var scene := load(weapon["scene"]) as PackedScene
	if scene == null:
		push_error("WeaponCatalog: failed to load %s." % weapon["scene"])
		return null
	return scene.instantiate() as BigWeapon
