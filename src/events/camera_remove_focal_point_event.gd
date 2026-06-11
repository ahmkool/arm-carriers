class_name CameraRemoveFocalPointEvent
extends LevelEvent

@export var focal_point: Node3D


func _trigger_event() -> void:
	_remove_focal_point()


func _complete_event() -> void:
	_remove_focal_point()


func _remove_focal_point() -> void:
	if not is_instance_valid(focal_point):
		push_warning("CameraRemoveFocalPointEvent: focal_point is not set or invalid")
		return
	var rig := _find_camera_rig()
	if rig == null:
		push_warning("CameraRemoveFocalPointEvent: CameraFollowRig not found")
		return
	rig.remove_focal_point(focal_point)


func _find_camera_rig() -> CameraFollowRig:
	var world := _find_world_local()
	if world == null:
		return null
	return world.get_node_or_null("CameraFollowRig") as CameraFollowRig


func _find_world_local() -> WorldLocal:
	var n := get_parent()
	while n != null:
		var w := n as WorldLocal
		if w != null:
			return w
		n = n.get_parent()
	return null
