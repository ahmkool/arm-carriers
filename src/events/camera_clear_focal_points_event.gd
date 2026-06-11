class_name CameraClearFocalPointsEvent
extends LevelEvent


func _trigger_event() -> void:
	_clear_focal_points()


func _complete_event() -> void:
	_clear_focal_points()


func _clear_focal_points() -> void:
	var rig := _find_camera_rig()
	if rig == null:
		push_warning("CameraClearFocalPointsEvent: CameraFollowRig not found")
		return
	rig.clear_focal_points()


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
