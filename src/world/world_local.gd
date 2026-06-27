class_name WorldLocal
extends Node3D

@export var level_id: String = ""
@export var skip_save: bool = false
@export var vfx_warmup_scenes: Array[PackedScene] = []

@onready var players = $Players
@onready var enemies = $Enemies
@onready var checkpoint_manager: Node = $CheckpointManager
# Called when the node enters the scene tree for the first time.

func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass

func get_level_id() -> String:
	if not level_id.is_empty():
		return level_id
	if scene_file_path.is_empty():
		return ""
	return scene_file_path


func restart_game() -> void:
	var game_state_machine = get_node_or_null("GameStateMachine") as GameStateMachine
	if game_state_machine == null:
		return

	game_state_machine.transition_to("resettingcheckpoint")

func get_active_weapon() -> BigWeapon:
	var weapon_root := get_node_or_null("Weapon")
	if weapon_root == null:
		return null
	for child in weapon_root.get_children():
		var weapon := child as BigWeapon
		if weapon != null:
			return weapon
	return null
