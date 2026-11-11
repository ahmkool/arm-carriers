class_name WorldLocal
extends Node3D

@export var level_id: String = ""
@export var skip_save: bool = false
@export var vfx_warmup_scenes: Array[PackedScene] = []
## Per-level colours for the siege bow's aim guide and arrow shafts, for floors they blend into.
## Left fully transparent (the default), the bow keeps its own colours.
@export var aim_guide_color: Color = KEEP_WEAPON_COLOR
@export var arrow_shaft_color: Color = KEEP_WEAPON_COLOR

const KEEP_WEAPON_COLOR := Color(0, 0, 0, 0)

@onready var players = $Players
@onready var enemies = $Enemies
@onready var checkpoint_manager: Node = $CheckpointManager

## Set when the menu swapped in a weapon other than the authored one. Checkpoints then place its
## carriers with their WeaponSpawns markers or the catalog offsets, not the authored weapon's markers.
var _swapped_weapon_id := ""
var _loadout_applied := false


## Runs before any child's _ready, so everything that looks up the weapon finds the swapped one.
func _enter_tree() -> void:
	if _loadout_applied:
		return
	_loadout_applied = true
	_apply_loadout_weapon()


## The save key: this level with the weapon being carried, so each weapon keeps its own progress.
func get_level_id() -> String:
	var base_id := _get_base_level_id()
	if base_id.is_empty():
		return ""
	return GameSave.level_key(base_id, get_active_weapon_id())


## The catalog id of the weapon being carried, or "" when there is none or it is not in the catalog.
func get_active_weapon_id() -> String:
	if not _swapped_weapon_id.is_empty():
		return _swapped_weapon_id
	var weapon := get_active_weapon()
	if weapon == null:
		return ""
	return WeaponCatalog.id_for_scene_path(weapon.scene_file_path)


func _get_base_level_id() -> String:
	if not level_id.is_empty():
		return level_id
	return scene_file_path


func restart_game() -> void:
	var game_state_machine = get_node_or_null("GameStateMachine") as GameStateMachine
	if game_state_machine == null:
		return

	game_state_machine.transition_to("resettingcheckpoint")


func jump_to_checkpoint(checkpoint: Checkpoint) -> void:
	if checkpoint == null:
		return
	if scene_file_path.is_empty():
		_jump_to_checkpoint_in_place(checkpoint)
		return
	var tree := get_tree()
	if tree == null:
		return
	DevSettings.request_checkpoint_jump(checkpoint.get_save_id(), skip_save)
	var err := tree.change_scene_to_file(scene_file_path)
	if err != OK:
		push_error("WorldLocal: failed to reload level for checkpoint '%s' (error %d)." % [checkpoint.get_save_id(), err])


func _jump_to_checkpoint_in_place(checkpoint: Checkpoint) -> void:
	var manager := checkpoint_manager as CheckpointManager
	if manager == null:
		return
	manager.set_current_checkpoint_silent(checkpoint)
	restart_game()

func get_active_weapon() -> BigWeapon:
	var weapon_root := get_node_or_null("Weapon")
	if weapon_root == null:
		return null
	for child in weapon_root.get_children():
		var weapon := child as BigWeapon
		if weapon != null:
			return weapon
	return null


## The weapon the menu swapped in, or "" when the level plays with its authored weapon.
func get_swapped_weapon_id() -> String:
	return _swapped_weapon_id


func _apply_loadout_weapon() -> void:
	var weapon_id := LevelLoadout.weapon_id
	if weapon_id.is_empty():
		return
	var weapon_root := get_node_or_null("Weapon")
	if weapon_root == null:
		push_warning("WorldLocal: no Weapon node to swap '%s' into." % weapon_id)
		return
	var authored := get_active_weapon()
	if _is_authored_weapon(authored, weapon_id):
		return
	var replacement := WeaponCatalog.instantiate(weapon_id)
	if replacement == null:
		return
	_replace_weapon(weapon_root, authored, replacement)
	_swapped_weapon_id = weapon_id


func _is_authored_weapon(authored: BigWeapon, weapon_id: String) -> bool:
	if authored == null:
		return false
	return WeaponCatalog.id_for_scene_path(authored.scene_file_path) == weapon_id


## Keeps the authored weapon's slot and transform; the checkpoint reset poses it anyway.
func _replace_weapon(weapon_root: Node, authored: BigWeapon, replacement: BigWeapon) -> void:
	if authored == null:
		weapon_root.add_child(replacement)
		weapon_root.move_child(replacement, 0)
		return
	var index := authored.get_index()
	replacement.transform = authored.transform
	weapon_root.remove_child(authored)
	authored.free()
	weapon_root.add_child(replacement)
	weapon_root.move_child(replacement, index)
