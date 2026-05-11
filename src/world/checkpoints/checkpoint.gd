class_name Checkpoint
extends Node3D

@onready var position_direction_setter = $PositionDirectionSetter
@onready var position_shooter = $PositionShooter

@onready var _trigger_area: Area3D = $TriggerArea

@export var events_completed: Array[LevelEvent]
@export var enemy_groups_defeated: Array[EnemyGroup]

# Called when the node enters the scene tree for the first time.
func _ready():
	var manager := get_parent() as Node
	if manager != null and manager.has_method("register_checkpoint"):
		manager.call("register_checkpoint", self)
	
func on_checkpoint_entered(body: Node3D):
	# This is connected from the scene (`TriggerArea.body_entered`).
	var manager := get_parent() as Node
	if manager != null and manager.has_method("set_current_checkpoint"):
		manager.call("set_current_checkpoint", self, body)
	print("Checkpoint reached !")


func get_spawn_transform() -> Transform3D:
	if is_instance_valid(position_direction_setter) and position_direction_setter is Node3D:
		return (position_direction_setter as Node3D).global_transform
	return global_transform

func set_world_at_checkpoint_state():
	for event in events_completed:
		event._complete_event()
	for enemy_group in enemy_groups_defeated:
		enemy_group.mark_as_defeated()


func get_shooter_transform() -> Transform3D:
	if is_instance_valid(position_shooter) and position_shooter is Node3D:
		return (position_shooter as Node3D).global_transform
	return global_transform
	
func _trigger_checkpoint() -> void:
	var checkpoint_manager: CheckpointManager = get_parent() as CheckpointManager
	checkpoint_manager.set_current_checkpoint(self)
