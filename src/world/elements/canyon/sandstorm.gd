class_name Sandstorm
extends Node3D
## A sandstorm over the level: fast sand streaks and slow dust clouds blowing along the wind, in boxes that follow
## the camera (world-space particles, so moving the boxes doesn't drag what's already in the air), and low sheets of
## sand haze drifting across the ground. Every so often a gust thickens the dust and haze, speeds the streaks up and
## raises the environment's fog, then dies down again.
## Purely visual: nothing here collides or touches gameplay.

## Its fog is raised during gusts. Leave empty for gusts without haze.
@export var world_environment: WorldEnvironment
@export var gust_interval_min := 7.0
@export var gust_interval_max := 14.0
## Seconds to build up, hold, and die down.
@export var gust_rise := 1.5
@export var gust_hold := 2.5
@export var gust_fall := 2.5
## Multiplies the fog density at a gust's peak.
@export var gust_fog_scale := 2.5
@export var gust_speed_scale := 1.5
## Share of the dust clouds shown between gusts; all of them show at a gust's peak.
@export var calm_dust := 0.45
## Where each box sits relative to the camera, in world axes. The camera looks down from about 10 m above the
## carriers, so the boxes sit around their height, shifted upwind so the sand blows in across the screen.
@export var streaks_offset := Vector3(-6, -11, -6)
@export var dust_offset := Vector3(-8, -13, -6)
## The haze sheets follow the camera across the ground but keep their own heights.
@export var haze_heights: Array[float] = [-0.4, 1.4, 3.6]

const CHASM_FOG_GLOBAL := &"chasm_fog_density"

@onready var _streaks: GPUParticles3D = $Streaks
@onready var _dust: GPUParticles3D = $Dust
@onready var _haze: MeshInstance3D = $Haze
var _haze_sheets: Array[MeshInstance3D] = []
var _rng := RandomNumberGenerator.new()
var _gust_wait := 0.0
var _base_fog := 0.0
## 0 calm, 1 at a gust's peak; tweened.
var _strength := 0.0
var _gust: Tween


func _ready() -> void:
	_rng.randomize()
	_gust_wait = _rng.randf_range(gust_interval_min * 0.5, gust_interval_max * 0.5)
	if world_environment and world_environment.environment:
		# A copy: the scene's Environment is shared and cached across reloads, so a restart mid-gust would keep the
		# gust's fog as the new base and stack the next gust on top.
		world_environment.environment = world_environment.environment.duplicate()
		_base_fog = world_environment.environment.fog_density
	_build_haze_sheets()
	_apply_strength(0.0)


## The scene holds one sheet; it is copied once per height, all sharing its material.
func _build_haze_sheets() -> void:
	_haze_sheets.append(_haze)
	for i in range(1, haze_heights.size()):
		var sheet := _haze.duplicate() as MeshInstance3D
		add_child(sheet)
		_haze_sheets.append(sheet)


func _process(delta: float) -> void:
	_follow_camera()
	_tick_gust(delta)


func _follow_camera() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_streaks.global_position = camera.global_position + streaks_offset
	_dust.global_position = camera.global_position + dust_offset
	for i in _haze_sheets.size():
		_haze_sheets[i].global_position = Vector3(camera.global_position.x, haze_heights[i], camera.global_position.z)


func _tick_gust(delta: float) -> void:
	_gust_wait -= delta
	if _gust_wait > 0.0:
		return
	_gust_wait = _rng.randf_range(gust_interval_min, gust_interval_max) + gust_rise + gust_hold + gust_fall
	_play_gust()


func _play_gust() -> void:
	if _gust and _gust.is_valid():
		_gust.kill()
	_gust = create_tween()
	_gust.tween_method(_apply_strength, _strength, 1.0, gust_rise).set_trans(Tween.TRANS_SINE)
	_gust.tween_interval(gust_hold)
	_gust.tween_method(_apply_strength, 1.0, 0.0, gust_fall).set_trans(Tween.TRANS_SINE)


func _apply_strength(strength: float) -> void:
	_strength = strength
	_dust.amount_ratio = lerpf(calm_dust, 1.0, strength)
	_streaks.speed_scale = lerpf(1.0, gust_speed_scale, strength)
	_dust.speed_scale = lerpf(1.0, gust_speed_scale, strength)
	(_haze.mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter(&"gust", strength)
	if world_environment == null or world_environment.environment == null:
		return
	var fog := _base_fog * lerpf(1.0, gust_fog_scale, strength)
	world_environment.environment.fog_density = fog
	# The chasm shaders apply this fog themselves, so they can fade it out with depth.
	RenderingServer.global_shader_parameter_set(CHASM_FOG_GLOBAL, fog)


## For test drivers: starts a gust now.
func start_gust() -> void:
	_gust_wait = gust_interval_max + gust_rise + gust_hold + gust_fall
	_play_gust()


func gust_strength() -> float:
	return _strength
