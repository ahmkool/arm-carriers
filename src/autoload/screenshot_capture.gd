extends Node

## Dev-only: press the `take_screenshot` action (L) to save the current frame
## as a PNG at the game's render resolution, e.g. for Steam store screenshots.

const OUTPUT_DIR := "user://screenshots"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("take_screenshot"):
		return
	if not DevSettings.is_active():
		return
	get_viewport().set_input_as_handled()
	capture()


func capture() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null:
		push_error("ScreenshotCapture: viewport returned no image.")
		return
	var dir_error := DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	if dir_error != OK:
		push_error("ScreenshotCapture: failed to create %s (error %d)." % [OUTPUT_DIR, dir_error])
		return
	var path := _next_file_path()
	var save_error := image.save_png(path)
	if save_error != OK:
		push_error("ScreenshotCapture: failed to save %s (error %d)." % [path, save_error])
		return
	print("Screenshot saved: ", ProjectSettings.globalize_path(path))


func _next_file_path() -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "%s/arm_carriers_%s.png" % [OUTPUT_DIR, stamp]
	var suffix := 2
	while FileAccess.file_exists(path):
		path = "%s/arm_carriers_%s_%d.png" % [OUTPUT_DIR, stamp, suffix]
		suffix += 1
	return path
