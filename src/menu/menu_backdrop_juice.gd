class_name MenuBackdropJuice
extends Node
## Brings the menu's illustration to life: intro beats, parallax, idle motion, particles and bazooka fire.
## The intro beats are called from the "appearance" animation on the menu's AnimationPlayer.

const SKY_SHADER := preload("res://src/menu/menu_sky.gdshader")
const HORDE_SHADER := preload("res://src/menu/menu_horde.gdshader")
const LOGO_SHADER := preload("res://src/menu/menu_logo_sheen.gdshader")
const SMOKE_TEXTURE := preload("res://assets/sprites/particles/smoke_05_a.png")
const SOUND_SHOT := preload("res://assets/sounds/bazooka_shot.wav")
const SOUND_LOGO_SLAM := preload("res://assets/sounds/explosion/Medium Explosion 4_1.wav")
const SOUND_BOSS_STOMP := preload("res://assets/sounds/axe/yodguard-giant-axe-impact-striking-into-dirt-4-450258.mp3")
const SOUND_PLAYERS_LAND := preload("res://assets/sounds/punch/Punch 3_1.wav")
const SOUND_HORDE := preload("res://assets/sounds/wood/WoodStep03.wav")

const MAX_DELTA := 1.0 / 30.0
const PARALLAX_RANGE := Vector2(16.0, 7.0)
const PARALLAX_SMOOTHING := 4.0
const SHAKE_PIXELS := 18.0
const TRAUMA_DECAY := 1.6
const INTRO_HURRY_SPEED := 4.0

## Positions inside the 1820x1080 illustration, as a fraction of the layer.
const MUZZLE_POINT := Vector2(0.385, 0.70)
const PLAYERS_FEET_POINT := Vector2(0.55, 0.97)
const BOSS_FEET_POINT := Vector2(0.93, 0.98)
const HORDE_FEET_POINT := Vector2(0.12, 0.95)
## Barrel axis from breech to muzzle in the illustration.
const FIRE_DIRECTION := Vector2(-0.97, -0.23)
const RECOIL_IMPULSE := 420.0

const STOMP_INTERVAL_MIN := 6.0
const STOMP_INTERVAL_MAX := 11.0

## A layer's total motion is composed here each frame, so idle, parallax, shake and impacts can overlap.
class Layer:
	var control: Control
	var pivot: Vector2
	var overscan: float
	var rest: Vector2
	var depth: float
	var bob_pixels: float
	var bob_speed: float
	var sway_degrees: float
	var phase: float
	var entry_offset := Vector2.ZERO
	var entry_scale := 1.0
	var offset_x := MenuSpring.new(0.0, 170.0, 0.42)
	var offset_y := MenuSpring.new(0.0, 170.0, 0.42)
	var tilt := MenuSpring.new(0.0, 130.0, 0.35)
	var squash := MenuSpring.new(0.0, 260.0, 0.3)
	var _base_offsets: Array[float]

	func _init(p_control: Control, p_pivot: Vector2, p_overscan: float, p_depth: float) -> void:
		control = p_control
		pivot = p_pivot
		overscan = p_overscan
		depth = p_depth
		_base_offsets = [control.offset_left, control.offset_top, control.offset_right, control.offset_bottom]

	func set_idle(p_bob_pixels: float, p_bob_speed: float, p_sway_degrees: float, p_phase: float) -> void:
		bob_pixels = p_bob_pixels
		bob_speed = p_bob_speed
		sway_degrees = p_sway_degrees
		phase = p_phase

	func point(ratio: Vector2) -> Vector2:
		return control.get_global_transform() * (control.size * ratio)

	func update(delta: float, time: float, parallax: Vector2, shake: Vector2) -> void:
		offset_x.step(delta)
		offset_y.step(delta)
		tilt.step(delta)
		squash.step(delta)
		var bob := Vector2(0.0, sin(time * bob_speed + phase) * bob_pixels)
		var springs := Vector2(offset_x.value, offset_y.value)
		var offset := rest + entry_offset + springs + bob + (parallax + shake) * depth
		control.offset_left = _base_offsets[0] + offset.x
		control.offset_top = _base_offsets[1] + offset.y
		control.offset_right = _base_offsets[2] + offset.x
		control.offset_bottom = _base_offsets[3] + offset.y
		control.pivot_offset = control.size * pivot
		control.rotation_degrees = tilt.value + sin(time * bob_speed * 0.5 + phase) * sway_degrees
		var uniform_scale := overscan * entry_scale
		control.scale = Vector2(uniform_scale * (1.0 - squash.value * 0.5), uniform_scale * (1.0 + squash.value))


var _layers: Array[Layer] = []
var _players: Layer
var _boss: Layer
var _horde: Layer
var _logo: Layer

var _muzzle_glow: Sprite2D
var _muzzle_smoke: CPUParticles2D
var _fx_root: Node2D
var _flash: ColorRect
var _pointer := Vector2.ZERO
var _parallax := Vector2.ZERO
var _trauma := 0.0
var _time := 0.0
var _glow_boost := 0.0
var _intro_finished := false
var _intro_hurried := false
var _next_stomp_time := 0.0

@onready var _menu: Control = get_parent()
@onready var _animation: AnimationPlayer = $"../AnimationPlayer"
@onready var _prompt: Label = $"../PressStartRoot/PromptLabel"
@onready var _press_start_root: Control = $"../PressStartRoot"


func _ready() -> void:
	_build_layers()
	_apply_shaders()
	_build_muzzle()
	_build_overlays.call_deferred()
	_hold_layers_for_intro()
	_press_start_root.visibility_changed.connect(_on_press_start_visibility_changed)
	_animation.animation_finished.connect(_on_intro_finished)
	_next_stomp_time = randf_range(STOMP_INTERVAL_MIN, STOMP_INTERVAL_MAX)


func _input(event: InputEvent) -> void:
	if not event is InputEventMouseMotion:
		return
	var viewport_size := _menu.get_viewport_rect().size
	_pointer = (event.position / viewport_size - Vector2(0.5, 0.5)) * 2.0


func _process(delta: float) -> void:
	var step_delta := minf(delta, MAX_DELTA)
	_time += step_delta
	_trauma = maxf(_trauma - TRAUMA_DECAY * step_delta, 0.0)
	_parallax = _parallax.lerp(-_pointer * PARALLAX_RANGE, minf(PARALLAX_SMOOTHING * step_delta, 1.0))
	var shake := Vector2(sin(_time * 47.0), cos(_time * 53.0)) * _trauma * _trauma * SHAKE_PIXELS
	for layer in _layers:
		layer.update(step_delta, _time, _parallax, shake)
	_update_muzzle(step_delta)
	_update_prompt()
	_try_boss_idle_stomp()


## Fires the big bazooka from the menu art: recoil, muzzle blast, smoke and a boom.
func fire_bazooka() -> void:
	var recoil := -FIRE_DIRECTION * RECOIL_IMPULSE
	_players.offset_x.velocity += recoil.x
	_players.offset_y.velocity += recoil.y
	_players.tilt.velocity += 26.0
	_horde.offset_y.velocity -= 120.0
	_boss.tilt.velocity += 10.0
	_add_trauma(0.55)
	_glow_boost = 1.0
	var muzzle := _players.point(MUZZLE_POINT)
	_burst_smoke(muzzle, FIRE_DIRECTION, 14, Color(0.72, 0.66, 0.6, 0.9), 0.4)
	_burst_sparks(muzzle, FIRE_DIRECTION, 26)
	_play_detached(SOUND_SHOT, -13.0, randf_range(0.95, 1.08))


## Speeds up whatever is left of the intro once the player is already in a menu.
func hurry_intro() -> void:
	if _intro_finished:
		return
	_intro_hurried = true
	_animation.speed_scale = INTRO_HURRY_SPEED


func beat_horde() -> void:
	var tween := create_tween()
	tween.tween_property(_horde, "entry_offset", Vector2.ZERO, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_land_horde)


func beat_players() -> void:
	var tween := create_tween()
	tween.tween_property(_players, "entry_offset", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_land_players)


func beat_boss() -> void:
	var tween := create_tween()
	tween.tween_property(_boss, "entry_offset", Vector2.ZERO, 0.26).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_land_boss)


func beat_logo() -> void:
	var tween := create_tween()
	tween.tween_property(_logo, "entry_scale", 1.0, 0.16).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tween.tween_callback(_land_logo)


func _build_layers() -> void:
	var feet := Vector2(0.5, 1.0)
	var center := Vector2(0.5, 0.5)
	var sky := _add_layer("Background", center, 1.06, 0.25)
	sky.set_idle(0.0, 0.0, 0.0, 0.0)
	_boss = _add_layer("Boss", feet, 1.05, 0.45)
	_boss.set_idle(2.5, 1.1, 0.25, 1.7)
	_players = _add_layer("Players", feet, 1.05, 0.8)
	_players.set_idle(4.0, 2.1, 0.35, 0.0)
	_horde = _add_layer("Skeletons", feet, 1.05, 1.1)
	_horde.set_idle(3.0, 2.8, 0.2, 0.6)
	var ground := _add_layer("GroundSkeletons", feet, 1.05, 1.2)
	ground.set_idle(0.0, 0.0, 0.0, 0.0)
	_logo = _add_layer("Logo", center, 1.0, 0.5)
	_logo.set_idle(5.0, 1.3, 0.7, 0.4)
	for layer: Layer in [_boss, _players, _horde, ground]:
		layer.rest = Vector2(0.0, 24.0)


func _add_layer(node_name: String, pivot: Vector2, overscan: float, depth: float) -> Layer:
	var layer := Layer.new(_menu.get_node(node_name) as Control, pivot, overscan, depth)
	_layers.append(layer)
	return layer


func _apply_shaders() -> void:
	_assign_shader(_menu.get_node("Background") as Control, SKY_SHADER)
	_assign_shader(_horde.control, HORDE_SHADER)
	_assign_shader(_logo.control, LOGO_SHADER)


func _assign_shader(control: Control, shader: Shader) -> void:
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	control.material = shader_material


## Deferred because the menu is still adding its own children during _ready.
func _build_overlays() -> void:
	var overlay_index := _logo.control.get_index() + 1
	_flash = ColorRect.new()
	_flash.color = Color(1.0, 0.97, 0.88, 0.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(_flash)
	_menu.move_child(_flash, overlay_index)
	_fx_root = Node2D.new()
	_menu.add_child(_fx_root)
	_menu.move_child(_fx_root, overlay_index + 1)
	_build_embers()


func _build_muzzle() -> void:
	_muzzle_smoke = _make_smoke_particles(9, 2.6)
	_muzzle_smoke.gravity = Vector2(-14.0, -46.0)
	_muzzle_smoke.spread = 30.0
	_muzzle_smoke.direction = FIRE_DIRECTION
	_muzzle_smoke.initial_velocity_min = 12.0
	_muzzle_smoke.initial_velocity_max = 30.0
	_muzzle_smoke.scale_amount_min = 0.1
	_muzzle_smoke.scale_amount_max = 0.2
	_muzzle_smoke.color_ramp = _fade_ramp(Color(1.0, 0.94, 0.88, 0.32))
	_players.control.add_child(_muzzle_smoke)
	_muzzle_glow = Sprite2D.new()
	_muzzle_glow.texture = _soft_dot_texture(256)
	_muzzle_glow.material = _additive_material()
	_muzzle_glow.modulate = Color(1.0, 0.42, 0.14, 0.0)
	_players.control.add_child(_muzzle_glow)


func _build_embers() -> void:
	var embers := CPUParticles2D.new()
	embers.amount = 26
	embers.lifetime = 7.0
	embers.preprocess = 7.0
	embers.texture = _soft_dot_texture(32)
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var viewport_size := _menu.get_viewport_rect().size
	embers.position = Vector2(viewport_size.x * 0.5, viewport_size.y)
	embers.emission_rect_extents = Vector2(viewport_size.x * 0.55, 30.0)
	embers.direction = Vector2(0.3, -1.0)
	embers.spread = 25.0
	embers.gravity = Vector2.ZERO
	embers.initial_velocity_min = 40.0
	embers.initial_velocity_max = 110.0
	embers.scale_amount_min = 0.25
	embers.scale_amount_max = 0.8
	embers.color_ramp = _fade_ramp(Color(1.0, 0.55, 0.12, 0.9))
	_menu.add_child(embers)
	_menu.move_child(embers, _horde.control.get_index())


func _hold_layers_for_intro() -> void:
	_horde.entry_offset = Vector2(-90.0, 190.0)
	_players.entry_offset = Vector2(0.0, 300.0)
	_boss.entry_offset = Vector2(80.0, 260.0)
	_logo.entry_scale = 2.6


func _land_horde() -> void:
	_horde.squash.velocity -= 1.6
	_add_trauma(0.22)
	_burst_smoke(_horde.point(HORDE_FEET_POINT), Vector2.UP, 8, Color(0.85, 0.72, 0.55, 0.6), 0.3)
	_play_intro_sound(SOUND_HORDE, -8.0, 0.7)


func _land_players() -> void:
	_players.squash.velocity -= 2.4
	_players.tilt.velocity -= 18.0
	_add_trauma(0.42)
	_burst_smoke(_players.point(PLAYERS_FEET_POINT), Vector2.UP, 12, Color(0.85, 0.72, 0.55, 0.7), 0.36)
	_play_intro_sound(SOUND_PLAYERS_LAND, -10.0, 0.8)


func _land_boss() -> void:
	_stomp_boss()
	_add_trauma(0.5)
	_play_intro_sound(SOUND_BOSS_STOMP, -9.0, 0.85)


func _land_logo() -> void:
	_logo.squash.velocity -= 3.4
	_logo.tilt.velocity -= 34.0
	_add_trauma(0.8)
	_flash_screen(0.3)
	var impact := _logo.point(Vector2(0.5, 0.86))
	_burst_smoke(impact, Vector2.DOWN, 16, Color(1.0, 0.97, 0.92, 0.8), 0.42)
	_burst_sparks(impact, Vector2.UP, 24)
	_play_intro_sound(SOUND_LOGO_SLAM, -15.0, 1.1)


func _stomp_boss() -> void:
	_boss.squash.velocity -= 1.8
	_boss.tilt.velocity += 8.0
	_burst_smoke(_boss.point(BOSS_FEET_POINT), Vector2.UP, 8, Color(0.85, 0.72, 0.55, 0.5), 0.3)


func _try_boss_idle_stomp() -> void:
	if not _intro_finished:
		return
	if _time < _next_stomp_time:
		return
	_next_stomp_time = _time + randf_range(STOMP_INTERVAL_MIN, STOMP_INTERVAL_MAX)
	_stomp_boss()


func _update_muzzle(delta: float) -> void:
	var muzzle_local := _players.control.size * MUZZLE_POINT
	_muzzle_smoke.position = muzzle_local
	_muzzle_glow.position = muzzle_local
	_glow_boost = maxf(_glow_boost - delta * 3.5, 0.0)
	var flicker := 0.3 + 0.1 * sin(_time * 7.0) + 0.06 * sin(_time * 23.0)
	_muzzle_glow.modulate.a = flicker + _glow_boost * 0.45
	_muzzle_glow.scale = Vector2.ONE * (0.8 + _glow_boost * 0.9)


func _update_prompt() -> void:
	_prompt.pivot_offset = _prompt.size * 0.5
	_prompt.scale = Vector2.ONE * (1.0 + 0.05 * sin(_time * 3.4))
	_prompt.self_modulate.a = 0.82 + 0.18 * sin(_time * 3.4)


func _add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


func _flash_screen(strength: float) -> void:
	_flash.color.a = strength
	var tween := create_tween()
	tween.tween_property(_flash, "color:a", 0.0, 0.3)


func _burst_smoke(at: Vector2, direction: Vector2, amount: int, color: Color, size: float) -> void:
	var smoke := _make_smoke_particles(amount, 0.9)
	smoke.one_shot = true
	smoke.explosiveness = 0.95
	smoke.direction = direction
	smoke.spread = 55.0
	smoke.initial_velocity_min = 90.0
	smoke.initial_velocity_max = 320.0
	smoke.damping_min = 240.0
	smoke.damping_max = 360.0
	smoke.scale_amount_min = size * 0.5
	smoke.scale_amount_max = size
	smoke.color_ramp = _fade_ramp(color)
	_emit_burst(smoke, at)


func _burst_sparks(at: Vector2, direction: Vector2, amount: int) -> void:
	var sparks := CPUParticles2D.new()
	sparks.amount = amount
	sparks.lifetime = 0.7
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.texture = _soft_dot_texture(32)
	sparks.direction = direction
	sparks.spread = 38.0
	sparks.initial_velocity_min = 260.0
	sparks.initial_velocity_max = 820.0
	sparks.damping_min = 300.0
	sparks.damping_max = 600.0
	sparks.gravity = Vector2(0.0, 420.0)
	sparks.scale_amount_min = 0.3
	sparks.scale_amount_max = 0.9
	sparks.color_ramp = _fade_ramp(Color(1.0, 0.6, 0.12, 1.0))
	_emit_burst(sparks, at)


func _emit_burst(particles: CPUParticles2D, at: Vector2) -> void:
	particles.position = at
	particles.finished.connect(particles.queue_free)
	_fx_root.add_child(particles)
	particles.emitting = true


func _make_smoke_particles(amount: int, lifetime: float) -> CPUParticles2D:
	var smoke := CPUParticles2D.new()
	smoke.amount = amount
	smoke.lifetime = lifetime
	smoke.texture = SMOKE_TEXTURE
	smoke.angle_min = -180.0
	smoke.angle_max = 180.0
	smoke.angular_velocity_min = -40.0
	smoke.angular_velocity_max = 40.0
	smoke.gravity = Vector2(0.0, -30.0)
	var growth := Curve.new()
	growth.add_point(Vector2(0.0, 0.5))
	growth.add_point(Vector2(1.0, 1.0))
	smoke.scale_amount_curve = growth
	return smoke


func _fade_ramp(color: Color) -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	return ramp


func _soft_dot_texture(size: int) -> GradientTexture2D:
	var falloff := Gradient.new()
	falloff.set_color(0, Color.WHITE)
	falloff.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	falloff.add_point(0.45, Color(1.0, 1.0, 1.0, 0.28))
	var texture := GradientTexture2D.new()
	texture.gradient = falloff
	texture.width = size
	texture.height = size
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


func _additive_material() -> CanvasItemMaterial:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return additive


func _play_intro_sound(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if _intro_hurried:
		return
	_play_detached(stream, volume_db, pitch)


## Parented to the tree root so the sound keeps ringing while the level scene takes over.
func _play_detached(stream: AudioStream, volume_db: float, pitch: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.finished.connect(player.queue_free)
	get_tree().root.add_child(player)
	player.play()


func _on_press_start_visibility_changed() -> void:
	if _press_start_root.visible:
		return
	fire_bazooka()


func _on_intro_finished(_animation_name: StringName) -> void:
	_intro_finished = true
	_animation.speed_scale = 1.0
