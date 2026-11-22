class_name DialogEvent
extends LevelEvent
## Plays a Zelda-style dialog sequence, optionally focusing the camera on a speaker.

const DialogBoxScript := preload("res://src/world/ui/dialog_box.gd")
const ACTIVE_DIALOG_GROUP := &"active_dialog_event"
const DIALOG_BOX_PATH := "UI/DialogBox"
const CAMERA_RIG_PATH := "CameraFollowRig"
const FACE_TURN_SECONDS := 0.45

@export var speaker_name: String = ""
@export var portrait: Texture2D
@export_multiline var lines: PackedStringArray = PackedStringArray()
## When true, plays only the first time this event triggers in the level (skips on checkpoint retries).
@export var play_once: bool = true

@export_group("Camera & Speaker")
@export var focus_target: Node3D
## Used when [member focus_target] is unset; resolves the live enemy from the group so retries work.
@export var focus_enemy_group: EnemyGroup
@export var face_players_during_dialog: bool = true
## World-space offset applied to the focal point so the speaker sits above the bottom dialog box.
@export var focus_offset: Vector3 = Vector3(0.0, 0.0, 1.5)
@export var focus_zoom_offset: float = 0.0
@export_range(0.05, 5.0, 0.05) var focus_move_in_seconds: float = 0.85
@export_range(0.05, 5.0, 0.05) var focus_move_out_seconds: float = 0.65

@export_group("Voice")
@export var voice_sound: AudioStream
@export_range(0.25, 2.0, 0.05) var voice_pitch: float = 0.48

var _has_played := false
var _cancelled := false
var _active_dialog_box: DialogBoxScript = null
var _active_camera_rig: CameraFollowRig = null
var _face_tween: Tween = null


func cancel() -> void:
	_cancelled = true
	_aborted = true
	_kill_face_tween()
	if is_instance_valid(_active_dialog_box):
		_active_dialog_box.cancel()
	if is_instance_valid(_active_camera_rig):
		_active_camera_rig.cancel_focus()
	GameplayInput.unlock()


func _exit_tree() -> void:
	if is_in_group(ACTIVE_DIALOG_GROUP):
		cancel()


func _trigger_event() -> void:
	if _should_skip():
		return
	var world := LevelNodes.find_world(self)
	if world == null:
		return
	var dialog_box := world.get_node_or_null(DIALOG_BOX_PATH) as DialogBoxScript
	if dialog_box == null:
		return

	_begin_sequence(world, dialog_box)
	var speaker := _resolve_speaker_node()
	_maybe_face_players(world, speaker)
	var did_focus := await _maybe_focus_camera(speaker)
	if _is_interrupted():
		_finish_aborted()
		return

	var finished_ok := await dialog_box.play_dialog(
		speaker_name,
		lines,
		portrait,
		voice_sound,
		voice_pitch
	)
	if not finished_ok or _is_interrupted():
		_finish_aborted()
		return

	_has_played = true
	await _release_camera(did_focus)
	if _is_interrupted():
		_finish_aborted()
		return
	_finish_completed()


func _should_skip() -> bool:
	if lines.is_empty():
		return true
	if play_once and _has_played:
		return true
	return false


func _begin_sequence(world: WorldLocal, dialog_box: DialogBoxScript) -> void:
	_cancelled = false
	_active_dialog_box = dialog_box
	_active_camera_rig = world.get_node_or_null(CAMERA_RIG_PATH) as CameraFollowRig
	add_to_group(ACTIVE_DIALOG_GROUP)
	GameplayInput.lock()


func _finish_completed() -> void:
	_cleanup_sequence()
	GameplayInput.unlock()


func _finish_aborted() -> void:
	_aborted = true
	if is_instance_valid(_active_camera_rig):
		_active_camera_rig.cancel_focus()
	_cleanup_sequence()
	GameplayInput.unlock()


func _cleanup_sequence() -> void:
	_kill_face_tween()
	if is_in_group(ACTIVE_DIALOG_GROUP):
		remove_from_group(ACTIVE_DIALOG_GROUP)
	_active_dialog_box = null
	_active_camera_rig = null


func _is_interrupted() -> bool:
	if _cancelled:
		return true
	return not is_inside_tree()


func _maybe_focus_camera(speaker: Node3D) -> bool:
	if speaker == null or _active_camera_rig == null:
		return false
	var focal_point := speaker.global_position + focus_offset
	await _active_camera_rig.begin_focus_on_point(
		focal_point,
		focus_move_in_seconds,
		focus_zoom_offset
	)
	return true


func _release_camera(did_focus: bool) -> void:
	if did_focus and is_instance_valid(_active_camera_rig):
		await _active_camera_rig.end_focus(focus_move_out_seconds)
		return
	if not is_inside_tree():
		return
	# Wait one physics step so the button press that closed the dialog cannot fire the weapon.
	await get_tree().physics_frame


func _resolve_speaker_node() -> Node3D:
	if is_instance_valid(focus_target):
		return focus_target
	return _find_enemy_in_group()


func _find_enemy_in_group() -> Node3D:
	if focus_enemy_group == null:
		return null
	var instances_parent := focus_enemy_group.get_node_or_null("InstancedEnemies")
	if instances_parent == null:
		instances_parent = focus_enemy_group
	for child in instances_parent.get_children():
		var enemy := child as EnemyLocal
		if enemy == null or not enemy.is_alive():
			continue
		return enemy
	return null


func _maybe_face_players(world: WorldLocal, speaker: Node3D) -> void:
	if not face_players_during_dialog or speaker == null:
		return
	var players_center := _compute_players_midpoint(world)
	if not players_center.is_finite():
		return
	var flat_dir := players_center - speaker.global_position
	flat_dir.y = 0.0
	if flat_dir.length_squared() < 0.0001:
		return
	var from_basis := speaker.global_basis.orthonormalized()
	var to_basis := Basis.looking_at(flat_dir.normalized(), Vector3.UP)
	_kill_face_tween()
	_face_tween = create_tween()
	_face_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_face_tween.tween_method(
		func(weight: float) -> void:
			if is_instance_valid(speaker):
				speaker.global_basis = from_basis.slerp(to_basis, weight),
		0.0,
		1.0,
		FACE_TURN_SECONDS
	)


func _compute_players_midpoint(world: WorldLocal) -> Vector3:
	var players := world.players as Node
	if players == null:
		return Vector3(INF, INF, INF)
	var sum := Vector3.ZERO
	var count := 0
	for child in players.get_children():
		var player := child as Node3D
		if player == null:
			continue
		sum += player.global_position
		count += 1
	if count == 0:
		return Vector3(INF, INF, INF)
	return sum / float(count)


func _kill_face_tween() -> void:
	if _face_tween == null:
		return
	_face_tween.kill()
	_face_tween = null
