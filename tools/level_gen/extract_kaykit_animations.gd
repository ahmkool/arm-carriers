extends SceneTree
## Copies animation clips out of a KayKit Character Animations glb into standalone .res files,
## which the Rig_Medium characters (adventurers, skeletons, robots) can play directly.
##   KAYKIT=<collection folder> CLIPS=<pack:clip[:loop],...> OUT=res://<folder> \
##     godot --headless --path . --script tools/level_gen/extract_kaykit_animations.gd
## pack is a file in "KayKit Character Animations 1.1/Animations/gltf/Rig_Medium", without "Rig_Medium_" or ".glb".

const PACK_FOLDER := "/KayKit Character Animations 1.1/Animations/gltf/Rig_Medium/Rig_Medium_%s.glb"


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
	clip.loop_mode = Animation.LOOP_LINEAR if parts.size() > 2 and parts[2] == "loop" else Animation.LOOP_NONE
	var path := "%s/%s.res" % [out_dir, parts[1]]
	var error := ResourceSaver.save(clip, path)
	print("SAVED ", path, " length=%.2f loop=%s error=%d" % [clip.length, clip.loop_mode != Animation.LOOP_NONE, error])
	return 0 if error == OK else 1


func _load_pack(pack: String) -> AnimationPlayer:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(OS.get_environment("KAYKIT") + PACK_FOLDER % pack, state) != OK:
		return null
	var root := document.generate_scene(state)
	return root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
