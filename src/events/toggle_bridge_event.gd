class_name OpenBridgeEvent
extends LevelEvent

@export var platforms: Array[BridgePlatform]

@export_range(0.05, 10.0, 0.05) var focus_move_in_seconds: float = 1.0
@export_range(0.1, 30.0, 0.05) var focus_hold_seconds: float = 2.0
@export_range(0.05, 10.0, 0.05) var focus_move_out_seconds: float = 1.0

@export_range(0.0, 5.0, 0.05) var platform_animation_stagger_seconds: float = 0.15

## If false, skips [GameplayInput] lock and camera focus so the bridge runs while gameplay continues.
@export var use_camera_focus: bool = true


enum EventType {
	OPEN_BRIDGE,
	CLOSE_BRIDGE
}

@export var event_type: EventType = EventType.OPEN_BRIDGE

func _reset_event():
	for platform in platforms:
		if not is_instance_valid(platform):
			continue
		var animation_player := platform.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if animation_player:
			animation_player.play(&"RESET")

func _trigger_event() -> void:
	if use_camera_focus:
		GameplayInput.lock()

	var rig: CameraFollowRig = null
	var focal := Vector3.ZERO
	if use_camera_focus:
		rig = get_node_or_null("../../../CameraFollowRig") as CameraFollowRig
		focal = _compute_platforms_focal_point()

	await _play_platform_animations()

	if use_camera_focus and rig != null:
		await rig.run_focus_on_point(
			focal,
			focus_hold_seconds,
			focus_move_in_seconds,
			focus_move_out_seconds
		)

	if use_camera_focus:
		GameplayInput.unlock()
	
func _complete_event() -> void:
	for platform in platforms:
		if not is_instance_valid(platform):
			continue
		var animation_player := platform.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if animation_player:
			animation_player.play(&"complete")


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
	var sequence: Array[BridgePlatform] = platforms.duplicate()
	if event_type == EventType.CLOSE_BRIDGE:
		sequence.reverse()
	var started_any := false
	for platform in sequence:
		if not is_instance_valid(platform):
			continue
		var animation_player := platform.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if animation_player == null:
			continue
		if started_any and platform_animation_stagger_seconds > 0.0:
			await get_tree().create_timer(platform_animation_stagger_seconds).timeout
		if event_type == EventType.CLOSE_BRIDGE:
			animation_player.play_backwards(&"animate")
		else:
			animation_player.play(&"animate")
		started_any = true


func _on_enemy_group_2_enemies_defeated():
	pass # Replace with function body.
