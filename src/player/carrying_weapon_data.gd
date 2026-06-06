class_name CarryingWeaponData
extends Node

@onready var player_node = $".."

@export var arm_left_path: NodePath = ^"Mannequin_Medium/Rig_Medium/Skeleton3D/Mannequin_Medium_ArmLeft"
@export var arm_right_path: NodePath = ^"Mannequin_Medium/Rig_Medium/Skeleton3D/Mannequin_Medium_ArmRight"

signal weapon_dropped()

const RELOAD_SOUND := preload("res://assets/sounds/ammo/reload.wav")
const SKIP_PICKUP_DROP := true

enum CanCarryStatus {
	CAN_CARRY_SHOOTER,
	CAN_CARRY_DIRECTION_SETTER,
	CARRYING_SHOOTER,
	CARRYING_DIRECTION_SETTER,
	NO_WEAPON_AVAILABLE,
}
var can_carry_status: CanCarryStatus = CanCarryStatus.NO_WEAPON_AVAILABLE

var _arm_left: MeshInstance3D
var _arm_right: MeshInstance3D


func _ready() -> void:
	_arm_left = _require_arm_mesh(arm_left_path, "arm_left_path")
	_arm_right = _require_arm_mesh(arm_right_path, "arm_right_path")


func _physics_process(_delta: float) -> void:
	_process_weapon_carrying()
	_update_arms_visibility()

func _process_weapon_carrying() -> void:
	if _process_not_carrying():
		return
	if _process_carrying():
		return

func _process_not_carrying() -> bool:
	if can_carry_status == CanCarryStatus.NO_WEAPON_AVAILABLE:
		return false
	if can_carry_status == CanCarryStatus.CARRYING_SHOOTER:
		return false
	if can_carry_status == CanCarryStatus.CARRYING_DIRECTION_SETTER:
		return false
	
	if can_carry_status != CanCarryStatus.CAN_CARRY_SHOOTER and can_carry_status != CanCarryStatus.CAN_CARRY_DIRECTION_SETTER:
		$"../UI".hide()
		return false
	
	var label = $"../UI/PanelContainer/Label" as Label
	label.text = "Press triangle to carry"
	$"../UI".show()
		
	if GameplayInput.is_locked() or not Input.is_action_just_pressed(player_node.action_action):
		return false
	if SKIP_PICKUP_DROP:
		return false

	var world_node = player_node.get_parent().get_parent()
	var big_weapon_node: BigWeapon = world_node.get_node("Weapon").get_child(0) as BigWeapon
	var pick_and_drop_handler: PickAndDropHandler = big_weapon_node.get_node("PickAndDropHandler")
	if pick_and_drop_handler == null:
		push_error("BigWeapon '%s' is missing a PickAndDropHandler child" % big_weapon_node.name)
		return false
	if can_carry_status == CanCarryStatus.CAN_CARRY_SHOOTER:
		var player_position = pick_and_drop_handler.get_node("ShooterPosition").global_position
		get_parent().global_position = player_position
		can_carry_status = CanCarryStatus.CARRYING_SHOOTER
		get_parent().weapon_carrier_pin_joint.set_node_b(big_weapon_node.get_path())
	elif can_carry_status == CanCarryStatus.CAN_CARRY_DIRECTION_SETTER:
		var player_position = pick_and_drop_handler.get_node("DirectionSetterPosition").global_position
		get_parent().global_position = player_position
		can_carry_status = CanCarryStatus.CARRYING_DIRECTION_SETTER
		get_parent().weapon_carrier_pin_joint.set_node_b(big_weapon_node.get_path())
	_play_weapon_pickup_sound()
	return true


func _play_weapon_pickup_sound() -> void:
	var sfx := AudioStreamPlayer3D.new()
	player_node.add_child(sfx)
	sfx.bus = "SFX"
	sfx.stream = RELOAD_SOUND
	sfx.finished.connect(sfx.queue_free, CONNECT_ONE_SHOT)
	sfx.play()

func _update_arms_visibility() -> void:
	_arm_left.show()
	_arm_right.show()
	if can_carry_status != CanCarryStatus.CARRYING_SHOOTER and can_carry_status != CanCarryStatus.CARRYING_DIRECTION_SETTER:
		return
	var world_node = player_node.get_parent().get_parent()
	var big_weapon_node: BigWeapon = world_node.get_node("Weapon").get_child(0) as BigWeapon
	var pick_and_drop_handler: PickAndDropHandler = big_weapon_node.get_node("PickAndDropHandler")
	var arms_visibility: PickAndDropHandler.HideArmsType = pick_and_drop_handler.hide_arms_type
	if arms_visibility == PickAndDropHandler.HideArmsType.LEFT_ARM_HIDDEN:
		_arm_left.hide()
		return
	if arms_visibility == PickAndDropHandler.HideArmsType.RIGHT_ARM_HIDDEN:
		_arm_right.hide()
		return
	if arms_visibility != PickAndDropHandler.HideArmsType.BOTH_ARMS_HIDDEN:
		return
	_arm_left.hide()
	_arm_right.hide()


func _require_arm_mesh(path: NodePath, export_name: String) -> MeshInstance3D:
	if path.is_empty():
		_fail_missing_arm(export_name, path, "path is empty")
		return null
	var mesh := player_node.get_node_or_null(path) as MeshInstance3D
	if mesh != null:
		return mesh
	_fail_missing_arm(export_name, path, "node is missing or not a MeshInstance3D")
	return null


func _fail_missing_arm(export_name: String, path: NodePath, reason: String) -> void:
	push_error(
		"CarryingWeaponData on '%s': %s (%s) — %s"
		% [player_node.name, export_name, path, reason]
	)
	get_tree().quit(1)

func _process_carrying() -> bool:
	if can_carry_status != CanCarryStatus.CARRYING_SHOOTER and can_carry_status != CanCarryStatus.CARRYING_DIRECTION_SETTER:
		return false
	
	var label = $"../UI/PanelContainer/Label" as Label
	label.text = "Press triangle to drop weapon"
	$"../UI".show()
		
	if GameplayInput.is_locked() or not Input.is_action_just_pressed(player_node.action_action):
		return false
	if SKIP_PICKUP_DROP:
		return false

	var world_node = player_node.get_parent().get_parent()
	if can_carry_status == CanCarryStatus.CARRYING_SHOOTER:
		can_carry_status = CanCarryStatus.NO_WEAPON_AVAILABLE
		get_parent().weapon_carrier_pin_joint.set_node_b("")
	elif can_carry_status == CanCarryStatus.CARRYING_DIRECTION_SETTER:
		can_carry_status = CanCarryStatus.NO_WEAPON_AVAILABLE
		get_parent().weapon_carrier_pin_joint.set_node_b("")
	return true
