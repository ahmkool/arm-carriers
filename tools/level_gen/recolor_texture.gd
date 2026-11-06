extends SceneTree
## Moves every strongly coloured pixel within a hue range into a narrow band around HUE_TARGET, and saves a copy.
## The band keeps the original gradient's order (HUE_SPREAD of its width), so shading survives without a rainbow.
## Used to turn KayKit's green Orc Raider blue without touching its red war paint, skin tones or metal.
##   SRC=res://in.png DST=res://out.png HUE_MIN=0.14 HUE_MAX=0.52 HUE_TARGET=0.6 HUE_SPREAD=0.25 \
##     godot --headless --path . --script tools/level_gen/recolor_texture.gd

const MIN_SATURATION := 0.2


func _initialize() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(OS.get_environment("SRC")))
	var hue_min := float(OS.get_environment("HUE_MIN"))
	var hue_max := float(OS.get_environment("HUE_MAX"))
	var target := float(OS.get_environment("HUE_TARGET"))
	var spread := float(OS.get_environment("HUE_SPREAD"))
	var changed := 0
	for y in image.get_height():
		for x in image.get_width():
			changed += _recolor(image, x, y, hue_min, hue_max, target, spread)
	var error := image.save_png(ProjectSettings.globalize_path(OS.get_environment("DST")))
	print("RECOLORED pixels=", changed, " error=", error)
	quit(error)


func _recolor(image: Image, x: int, y: int, hue_min: float, hue_max: float, target: float, spread: float) -> int:
	var color := image.get_pixel(x, y)
	if color.s < MIN_SATURATION or color.h < hue_min or color.h > hue_max:
		return 0
	var hue := target + (color.h - (hue_min + hue_max) * 0.5) * spread
	image.set_pixel(x, y, Color.from_hsv(fposmod(hue, 1.0), color.s, color.v, color.a))
	return 1
