class_name OpenBridgeEvent
extends LevelEvent

@export var platforms: Array[BridgePlatform]

@export_range(0.05, 10.0, 0.05) var focus_move_in_seconds: float = 1.0
@export_range(0.1, 30.0, 0.05) var focus_hold_seconds: float = 2.0
@export_range(0.05, 10.0, 0.05) var focus_move_out_seconds: float = 1.0


func _trigger_event() -> void:
	GameplayInput.lock()

	var rig := get_node_or_null("../../../CameraFollowRig") as CameraFollowRig
	var focal := _compute_platforms_focal_point()

	_play_platform_animations()

	if rig:
		await rig.run_focus_on_point(
			focal,
			focus_hold_seconds,
			focus_move_in_seconds,
			focus_move_out_seconds
		)

	GameplayInput.unlock()


func _compute_platforms_focal_point() -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for platform in platforms:
		if not is_instance_valid(platform):
			continue
		sum += platform.global_position
		count += 1
	return sum / float(count)


func _play_platform_animations() -> void:
	for platform in platforms:
		if not is_instance_valid(platform):
			continue
		var animation_player := platform.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if animation_player:
			animation_player.play(&"animate")
