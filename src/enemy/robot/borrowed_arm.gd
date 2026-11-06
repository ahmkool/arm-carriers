extends Node
## Gives a robot another robot's arm, so a model whose arm is a built-in weapon can hold a real one.
## Both robots share the Rig_Medium skeleton, so the borrowed arm follows the same bones.

@export var donor_scene: PackedScene
@export var donor_arm_name := "Robot_One_ArmRight"
@export var skeleton: Skeleton3D
@export var replaced_arm: MeshInstance3D


func _ready() -> void:
	var donor := donor_scene.instantiate()
	var arm := donor.find_child(donor_arm_name, true, false) as MeshInstance3D
	if arm == null:
		push_error("borrowed_arm: %s has no %s" % [donor_scene.resource_path, donor_arm_name])
		donor.free()
		return
	arm.get_parent().remove_child(arm)
	donor.free()
	replaced_arm.visible = false
	skeleton.add_child(arm)
	arm.skeleton = arm.get_path_to(skeleton)
