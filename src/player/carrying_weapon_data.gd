class_name CarryingWeaponData
extends Node

@onready var player_node = $".."

enum CanCarryStatus {
	CAN_CARRY_SHOOTER,
	CAN_CARRY_DIRECTION_SETTER,
	CARRYING_SHOOTER,
	CARRYING_DIRECTION_SETTER,
	NO_WEAPON_AVAILABLE,
}
var can_carry_status: CanCarryStatus = CanCarryStatus.NO_WEAPON_AVAILABLE

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
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
	return true

func _update_arms_visibility() -> void:
	var player: PlayerLocal = get_parent()
	player.get_node("Mannequin_Medium/Rig_Medium/Skeleton3D/Mannequin_Medium_ArmLeft").show()
	player.get_node("Mannequin_Medium/Rig_Medium/Skeleton3D/Mannequin_Medium_ArmRight").show()
	if can_carry_status != CanCarryStatus.CARRYING_SHOOTER and can_carry_status != CanCarryStatus.CARRYING_DIRECTION_SETTER:
		return
	var world_node = player_node.get_parent().get_parent()
	var big_weapon_node: BigWeapon = world_node.get_node("Weapon").get_child(0) as BigWeapon
	var pick_and_drop_handler: PickAndDropHandler = big_weapon_node.get_node("PickAndDropHandler")
	var arms_visibility: PickAndDropHandler.HideArmsType = pick_and_drop_handler.hide_arms_type
	if arms_visibility == PickAndDropHandler.HideArmsType.LEFT_ARM_HIDDEN:
		player.get_node("Mannequin_Medium/Rig_Medium/Skeleton3D/Mannequin_Medium_ArmLeft").hide()
	elif arms_visibility == PickAndDropHandler.HideArmsType.RIGHT_ARM_HIDDEN:
		player.get_node("Mannequin_Medium/Rig_Medium/Skeleton3D/Mannequin_Medium_ArmRight").hide()
	elif arms_visibility == PickAndDropHandler.HideArmsType.BOTH_ARMS_HIDDEN:
		player.get_node("Mannequin_Medium/Rig_Medium/Skeleton3D/Mannequin_Medium_ArmLeft").hide()
		player.get_node("Mannequin_Medium/Rig_Medium/Skeleton3D/Mannequin_Medium_ArmRight").hide()

func _process_carrying() -> bool:
	if can_carry_status != CanCarryStatus.CARRYING_SHOOTER and can_carry_status != CanCarryStatus.CARRYING_DIRECTION_SETTER:
		return false
	
	var label = $"../UI/PanelContainer/Label" as Label
	label.text = "Press triangle to drop weapon"
	$"../UI".show()
		
	if GameplayInput.is_locked() or not Input.is_action_just_pressed(player_node.action_action):
		return false
	
	var world_node = player_node.get_parent().get_parent()
	if can_carry_status == CanCarryStatus.CARRYING_SHOOTER:
		can_carry_status = CanCarryStatus.NO_WEAPON_AVAILABLE
		get_parent().weapon_carrier_pin_joint.set_node_b("")
	elif can_carry_status == CanCarryStatus.CARRYING_DIRECTION_SETTER:
		can_carry_status = CanCarryStatus.NO_WEAPON_AVAILABLE
		get_parent().weapon_carrier_pin_joint.set_node_b("")
	return true
