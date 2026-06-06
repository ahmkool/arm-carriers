extends Node3D

@export var look_at_point: Vector3 = Vector3(0.0, 1.5, 0.0)
@export var camera_side: float = 14.0
@export var camera_height: float = 2.8
@export var camera_fov: float = 38.0
@export var disable_follow_rig: bool = true

@onready var _camera: Camera3D = $Camera3D


func _ready() -> void:
	_camera.fov = camera_fov
	global_position = Vector3(camera_side, camera_height, look_at_point.z)
	look_at(look_at_point, Vector3.UP)
	_camera.current = true
	if not disable_follow_rig:
		return
	_disable_gameplay_camera()


func _disable_gameplay_camera() -> void:
	var follow_rig := get_parent().get_node_or_null("CameraFollowRig")
	if follow_rig == null:
		return
	var gameplay_cam := follow_rig.get_node_or_null("ShakePivot/Camera3D") as Camera3D
	if gameplay_cam == null:
		return
	gameplay_cam.current = false
	follow_rig.set_process(false)
