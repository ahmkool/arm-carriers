extends SceneTree
## Copies animation clips out of a KayKit Character Animations glb into standalone .res files,
## which the Rig_Medium characters (adventurers, skeletons, robots) can play directly.
##   KAYKIT=<collection folder> CLIPS=<pack:clip[:loop|:hold],...> OUT=res://<folder> \
##     godot --headless --path . --script tools/level_gen/extract_kaykit_animations.gd
## pack is a file in "KayKit Character Animations 1.1/Animations/gltf/Rig_Medium", without "Rig_Medium_" or ".glb".
## RIG=Large reads the Rig_Large packs instead, for large characters such as the golems.
## :hold saves the clip's last frame as a still loop, named <clip>_Hold, for clips that move into a pose and stay.

const PACK_FOLDER := "/KayKit Character Animations 1.1/Animations/gltf/Rig_%s/Rig_%s_%s.glb"
const HOLD_LENGTH := 1.0


func _initialize() -> void:
	var out_dir := OS.get_environment("OUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var failures := 0
	for entry in OS.get_environment("CLIPS").split(","):
		failures += _extract(entry.split(":"), out_dir)
	quit(failures)


func _extract(parts: PackedStringArray, out_dir: String) -> int:
	var player := _load_pack(parts[0])
	if player == null or not player.has_animation(parts[1]):
		printerr("MISSING ", ":".join(parts))
		return 1
	var clip := player.get_animation(parts[1]).duplicate(true) as Animation
	var mode := parts[2] if parts.size() > 2 else ""
	clip.loop_mode = Animation.LOOP_LINEAR if mode == "loop" or mode == "hold" else Animation.LOOP_NONE
	var name := parts[1]
	if mode == "hold":
		_hold_last_pose(clip)
		name += "_Hold"
	var path := "%s/%s.res" % [out_dir, name]
	var error := ResourceSaver.save(clip, path)
	print("SAVED ", path, " length=%.2f loop=%s error=%d" % [clip.length, clip.loop_mode != Animation.LOOP_NONE, error])
	return 0 if error == OK else 1


## Turns `clip` into a still loop of its last frame. For clips that move into a pose and then hold it, such as
## Ranged_1H_Aiming (it raises the weapon, then stays): looped as they are, they replay the raise every cycle.
func _hold_last_pose(clip: Animation) -> void:
	var end := clip.length
	for track in clip.get_track_count():
		var value: Variant = _value_at(clip, track, end)
		if value == null:
			continue
		while clip.track_get_key_count(track) > 0:
			clip.track_remove_key(track, 0)
		clip.track_insert_key(track, 0.0, value)
		clip.track_insert_key(track, HOLD_LENGTH, value)
	clip.length = HOLD_LENGTH


func _value_at(clip: Animation, track: int, time: float) -> Variant:
	match clip.track_get_type(track):
		Animation.TYPE_POSITION_3D:
			return clip.position_track_interpolate(track, time)
		Animation.TYPE_ROTATION_3D:
			return clip.rotation_track_interpolate(track, time)
		Animation.TYPE_SCALE_3D:
			return clip.scale_track_interpolate(track, time)
		Animation.TYPE_VALUE:
			return clip.value_track_interpolate(track, time)
	return null


func _load_pack(pack: String) -> AnimationPlayer:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var rig := OS.get_environment("RIG") if OS.has_environment("RIG") else "Medium"
	if document.append_from_file(OS.get_environment("KAYKIT") + PACK_FOLDER % [rig, rig, pack], state) != OK:
		return null
	var root := document.generate_scene(state)
	return root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
