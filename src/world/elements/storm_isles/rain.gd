class_name Rain
extends Node3D
## Rain over the level: streaks falling in a box that follows the camera, splashes on the floor GridMap's top tiles,
## and now and then a lightning flash on the sun. Ripples on the sea are in the water shader (`rain_ripples`).
## Purely visual: nothing here collides or touches gameplay.

## The GridMap whose floor tiles get splashes. Only cells at `splash_layer` with nothing on the layer above count.
@export var floor_grid: GridMap
@export var splash_layer := -1
@export var splashes_per_cell := 6
## The light that flashes for lightning. Leave empty for rain without lightning.
@export var lightning_light: DirectionalLight3D
@export var lightning_interval_min := 9.0
@export var lightning_interval_max := 22.0
@export var lightning_energy := 2.6
## Where the drop box sits relative to the camera, in world axes: just below the lens and a little ahead (-z), since
## the camera looks down and forward. The drops fall straight down, so under this steep camera they streak out from
## the point below it, longest at the screen's edges, which reads as a downpour.
@export var drops_offset := Vector3(0, -3.5, -5.0)

const SPLASH_TOP_OFFSET := 0.03
const POINTS_PER_ROW := 256

@onready var _drops: GPUParticles3D = $Drops
@onready var _splashes: GPUParticles3D = $Splashes
var _rng := RandomNumberGenerator.new()
var _lightning_wait := 0.0
var _light_energy := 1.0
var _flash: Tween


func _ready() -> void:
	_rng.randomize()
	_lightning_wait = _next_lightning_wait()
	if lightning_light:
		_light_energy = lightning_light.light_energy
	_setup_splashes()


func _process(delta: float) -> void:
	_follow_camera()
	_tick_lightning(delta)


func _follow_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_drops.global_position = camera.global_position + drops_offset


func _tick_lightning(delta: float) -> void:
	if lightning_light == null:
		return
	_lightning_wait -= delta
	if _lightning_wait > 0.0:
		return
	_lightning_wait = _next_lightning_wait()
	_play_flash()


func _next_lightning_wait() -> float:
	return _rng.randf_range(lightning_interval_min, lightning_interval_max)


## Two quick flickers, then back to the normal light.
func _play_flash() -> void:
	if _flash and _flash.is_valid():
		_flash.kill()
	_flash = create_tween()
	_flash.tween_property(lightning_light, "light_energy", lightning_energy, 0.04)
	_flash.tween_property(lightning_light, "light_energy", _light_energy * 0.8, 0.09)
	_flash.tween_property(lightning_light, "light_energy", lightning_energy * 0.8, 0.05)
	_flash.tween_property(lightning_light, "light_energy", _light_energy, 0.45)


func _setup_splashes() -> void:
	var points := _splash_points()
	if points.is_empty():
		_splashes.emitting = false
		return
	var material := _splashes.process_material as ParticleProcessMaterial
	material.emission_point_texture = _points_texture(points)
	material.emission_point_count = points.size()
	_splashes.amount = maxi(1, points.size() / 3)
	_splashes.visibility_aabb = _bounds(points).grow(2.0)


## Random spots on top of every open floor cell, in this node's space (the emitter sits at its origin).
func _splash_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	if floor_grid == null:
		return points
	var half := floor_grid.cell_size.x * 0.5
	for cell in floor_grid.get_used_cells():
		if not _is_open_floor(cell):
			continue
		var centre := floor_grid.to_global(floor_grid.map_to_local(cell))
		var top_y := centre.y + SPLASH_TOP_OFFSET
		for i in splashes_per_cell:
			var spot := Vector3(centre.x + _rng.randf_range(-half, half), top_y, centre.z + _rng.randf_range(-half, half))
			points.append(to_local(spot))
	return points


func _is_open_floor(cell: Vector3i) -> bool:
	if cell.y != splash_layer:
		return false
	return floor_grid.get_cell_item(cell + Vector3i.UP) == GridMap.INVALID_CELL_ITEM


func _points_texture(points: PackedVector3Array) -> ImageTexture:
	var rows := ceili(float(points.size()) / POINTS_PER_ROW)
	var image := Image.create(POINTS_PER_ROW, rows, false, Image.FORMAT_RGBF)
	for i in points.size():
		var p := points[i]
		image.set_pixel(i % POINTS_PER_ROW, i / POINTS_PER_ROW, Color(p.x, p.y, p.z))
	return ImageTexture.create_from_image(image)


func _bounds(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box
