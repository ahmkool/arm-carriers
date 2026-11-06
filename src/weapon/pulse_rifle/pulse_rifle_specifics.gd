class_name PulseRifleSpecifics
extends Node3D
## Rapid-fire rifle. The back carrier holds the shoot button for a steady stream of bolts.
## Each bolt hits for little, so the rifle trades the bazooka's one big blast for sustained,
## aimed fire. Bolts can also shoot down plasma.
##
## Firing heats the barrel. The front carrier's shoot button vents that heat as a cone
## blast from the muzzle (`PulseVent`): the hotter the barrel, the wider, harder and
## further it hits. Venting near the top of the gauge is a perfect vent that also lets the
## rifle fire faster without heating for a moment. Waiting too long overheats the rifle,
## which locks it while it cools. So the front carrier picks when to spend the heat: often
## to keep the stream going, or late, once enemies bunch up, for a big blast.

signal fired(bolt: PulseBolt)
signal vented(heat: float, hit_count: int, perfect: bool)
signal overheated

const FIRE_INTERVAL_SEC := 0.1
const DAMAGE := 1
const BOLT_SPEED := 42.0
## Like the bazooka's rockets, bolts fly through terrain, so this only removes misses.
const BOLT_RANGE := 30.0
## Sideways spread either side, so a held trigger sprays a little instead of one thin line.
const SPREAD_DEG := 2.5
## Each shot adds this much, and a held trigger settles at about four times it.
const SHOT_TRAUMA := 0.06
const FLASH_COLOR := Color(0.45, 0.95, 1.0)
const FLASH_VISIBLE_SEC := 0.04

## A held trigger overheats after 36 bolts, about 3.6 s.
const HEAT_PER_SHOT := 0.028
## The barrel starts cooling on its own this long after the last bolt.
const HEAT_COOL_DELAY_SEC := 0.6
const HEAT_COOL_PER_SEC := 0.3
const OVERHEAT_LOCK_SEC := 2.0
## Below this a vent is only a dry click: too little heat to blast with.
const MIN_VENT_HEAT := 0.15
const PERFECT_VENT_HEAT := 0.8
const OVERDRIVE_SEC := 2.5
const OVERDRIVE_FIRE_INTERVAL_SEC := 0.065
## Vents at least this hot shove the carriers back like a bazooka shot.
const HEAVY_VENT_HEAT := 0.5
const VENT_TRAUMA_PER_HEAT := 0.5

const COOL_COLOR := Color(0.45, 0.95, 1.0)
const WARM_COLOR := Color(1.0, 0.55, 0.1)
const HOT_COLOR := Color(1.0, 0.12, 0.05)
## Heat at which the glow has turned fully orange, before going red towards overheat.
const WARM_HEAT := 0.55
const OVERDRIVE_COLOR := Color(0.7, 1.0, 1.0)
const GLOW_MAX_ALPHA := 0.7
const LIGHT_MAX_ENERGY := 2.5
const LIGHT_RANGE := 4.0
const WARNING_FLICKER_HZ := 9.0
const SHOT_PITCH_RISE := 0.25

const BOLT_SCENE := preload("res://src/weapon/pulse_rifle/pulse_bolt.tscn")
const STEAM_SCENE := preload("res://src/vfx/puff_disappear.tscn")
const STEAM_FREE_SEC := 1.5
const SHOT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/sounds/gun/Gun 6-1.wav"),
	preload("res://assets/sounds/gun/Gun 6-2.wav"),
]
const VENT_SOUND := preload("res://assets/sounds/explosion/Medium Explosion 9_7.wav")
const HISS_SOUND := preload("res://assets/sounds/ammo/reload.wav")
const OVERHEAT_SOUND := preload("res://assets/sounds/explosion/Small Explosion 2_1.wav")

@export var pick_and_drop_handler: PickAndDropHandler

@onready var muzzle: Marker3D = $Muzzle
@onready var _muzzle_flash: Node3D = $Muzzle/MuzzleFlash
@onready var _model: Node3D = $Model

var heat := 0.0
var _cooldown_remaining := 0.0
var _flash_remaining := 0.0
var _since_last_shot := 0.0
var _overheat_remaining := 0.0
var _overdrive_remaining := 0.0
var _was_in_perfect_window := false
var _glow_material: StandardMaterial3D
var _heat_light: OmniLight3D


func _ready() -> void:
	_muzzle_flash.visible = false
	_setup_heat_glow()


func _physics_process(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	_update_muzzle_flash(delta)
	_update_heat(delta)
	var carry_info := pick_and_drop_handler.get_carry_info()
	if not _is_carried_by_both(carry_info):
		return
	_cue_perfect_window(carry_info.secondary_carrier)
	_try_vent(carry_info.secondary_carrier)
	_try_fire(carry_info.main_carrier)


func _process(_delta: float) -> void:
	_update_heat_glow()


func is_overheated() -> bool:
	return _overheat_remaining > 0.0


func is_in_overdrive() -> bool:
	return _overdrive_remaining > 0.0


func is_in_perfect_window() -> bool:
	return heat >= PERFECT_VENT_HEAT and not is_overheated()


## Fires one bolt straight away, ignoring input and the fire rate. Used by test drivers.
func fire_bolt() -> PulseBolt:
	var bolt := BOLT_SCENE.instantiate() as PulseBolt
	get_tree().current_scene.add_child(bolt)
	bolt.launch(muzzle.global_position, _get_spread_direction(), BOLT_SPEED, BOLT_RANGE, DAMAGE)
	_cooldown_remaining = _get_fire_interval()
	_since_last_shot = 0.0
	_play_shot_feedback()
	fired.emit(bolt)
	_add_shot_heat()
	return bolt


## Dumps the barrel's heat as a cone blast straight away. Used by `_try_vent` and test drivers.
func vent() -> int:
	var vent_heat := heat
	var perfect := vent_heat >= PERFECT_VENT_HEAT
	var forward := muzzle.global_basis.z
	var hit_count := PulseVent.blast(get_world_3d(), muzzle.global_position, forward, vent_heat)
	heat = 0.0
	_was_in_perfect_window = false
	if perfect:
		_overdrive_remaining = OVERDRIVE_SEC
	_play_vent_feedback(vent_heat, forward, perfect)
	vented.emit(vent_heat, hit_count, perfect)
	return hit_count


func _is_carried_by_both(carry_info: CarryInfo) -> bool:
	return is_instance_valid(carry_info.main_carrier) and is_instance_valid(carry_info.secondary_carrier)


func _try_fire(shooter: PlayerLocal) -> void:
	if GameplayInput.is_locked():
		return
	if not Input.is_action_pressed(shooter.action_shoot):
		return
	if is_overheated():
		return
	if _cooldown_remaining > 0.0:
		return
	fire_bolt()


func _try_vent(front_carrier: PlayerLocal) -> void:
	if GameplayInput.is_locked():
		return
	if not Input.is_action_just_pressed(front_carrier.action_shoot):
		return
	if is_overheated():
		return
	if heat < MIN_VENT_HEAT:
		_play_dry_vent(front_carrier)
		return
	vent()


func _get_fire_interval() -> float:
	if is_in_overdrive():
		return OVERDRIVE_FIRE_INTERVAL_SEC
	return FIRE_INTERVAL_SEC


func _add_shot_heat() -> void:
	if is_in_overdrive():
		return
	heat = minf(1.0, heat + HEAT_PER_SHOT)
	if heat < 1.0:
		return
	_overheat()


func _overheat() -> void:
	_overheat_remaining = OVERHEAT_LOCK_SEC
	_was_in_perfect_window = false
	_play_overheat_feedback()
	overheated.emit()


## While overheated the heat drains over the lock, so the glow fades as the rifle recovers.
func _update_heat(delta: float) -> void:
	_since_last_shot += delta
	_overdrive_remaining = maxf(0.0, _overdrive_remaining - delta)
	if is_overheated():
		_overheat_remaining = maxf(0.0, _overheat_remaining - delta)
		heat = clampf(_overheat_remaining / OVERHEAT_LOCK_SEC, 0.0, 1.0)
		return
	if _since_last_shot < HEAT_COOL_DELAY_SEC:
		return
	heat = maxf(0.0, heat - HEAT_COOL_PER_SEC * delta)


## A short buzz in the front carrier's hands the moment a perfect vent becomes possible.
func _cue_perfect_window(front_carrier: PlayerLocal) -> void:
	var in_window := is_in_perfect_window()
	if in_window == _was_in_perfect_window:
		return
	_was_in_perfect_window = in_window
	if not in_window:
		return
	ImpactFeedback.rumble(front_carrier, 0.5, 0.2, 0.1)
	ImpactFeedback.play_sfx(HISS_SOUND, muzzle.global_position, 2.2, -12.0)


func _get_spread_direction() -> Vector3:
	var forward := muzzle.global_basis.z
	forward.y = 0.0
	var angle := deg_to_rad(randf_range(-SPREAD_DEG, SPREAD_DEG))
	return forward.normalized().rotated(Vector3.UP, angle)


func _play_shot_feedback() -> void:
	var sound: AudioStream = SHOT_SOUNDS.pick_random()
	var pitch := randf_range(0.95, 1.12) + heat * SHOT_PITCH_RISE
	ImpactFeedback.play_sfx(sound, muzzle.global_position, pitch, -8.0)
	CameraFeedback.add_trauma(SHOT_TRAUMA)
	_show_muzzle_flash()
	var feedback := _get_carry_feedback()
	if feedback == null:
		return
	feedback.play_light_recoil(muzzle.global_position, FLASH_COLOR)


func _play_vent_feedback(vent_heat: float, forward: Vector3, perfect: bool) -> void:
	var wave_color := _get_heat_color(vent_heat)
	if perfect:
		wave_color = OVERDRIVE_COLOR
	PulseVentWave.spawn(get_tree().current_scene, muzzle.global_position, forward, PulseVent.get_range(vent_heat), wave_color)
	ImpactFeedback.play_sfx(VENT_SOUND, muzzle.global_position, lerpf(1.6, 1.0, vent_heat), lerpf(-14.0, -4.0, vent_heat))
	ImpactFeedback.play_sfx(HISS_SOUND, muzzle.global_position, 0.7, -8.0)
	CameraFeedback.add_trauma(vent_heat * VENT_TRAUMA_PER_HEAT)
	_spawn_steam()
	if perfect:
		ImpactFeedback.play_explosion()
	var feedback := _get_carry_feedback()
	if feedback == null:
		return
	if vent_heat < HEAVY_VENT_HEAT:
		feedback.play_light_recoil(muzzle.global_position, wave_color)
		return
	feedback.play_recoil(forward, muzzle.global_position)


func _play_dry_vent(front_carrier: PlayerLocal) -> void:
	var feedback := _get_carry_feedback()
	if feedback == null:
		return
	feedback.play_dry_click(front_carrier, muzzle.global_position)


func _play_overheat_feedback() -> void:
	ImpactFeedback.play_sfx(OVERHEAT_SOUND, muzzle.global_position, 0.7, -6.0)
	ImpactFeedback.play_sfx(HISS_SOUND, muzzle.global_position, 0.5, -4.0)
	CameraFeedback.add_trauma(0.3)
	_spawn_steam()
	var feedback := _get_carry_feedback()
	if feedback == null:
		return
	var carry_info := pick_and_drop_handler.get_carry_info()
	_dry_click_if_valid(feedback, carry_info.main_carrier)
	_dry_click_if_valid(feedback, carry_info.secondary_carrier)


func _dry_click_if_valid(feedback: CarryFeedback, carrier: PlayerLocal) -> void:
	if not is_instance_valid(carrier):
		return
	feedback.play_dry_click(carrier, muzzle.global_position)


func _spawn_steam() -> void:
	var steam := STEAM_SCENE.instantiate() as GPUParticles3D
	get_tree().current_scene.add_child(steam)
	steam.global_position = muzzle.global_position
	steam.emitting = true
	get_tree().create_timer(STEAM_FREE_SEC).timeout.connect(steam.queue_free, CONNECT_ONE_SHOT)


func _get_carry_feedback() -> CarryFeedback:
	return CarryFeedback.from_weapon(get_parent())


func _show_muzzle_flash() -> void:
	_flash_remaining = FLASH_VISIBLE_SEC
	_muzzle_flash.visible = true
	_muzzle_flash.rotation.z = randf() * TAU
	_muzzle_flash.scale = Vector3.ONE * randf_range(0.8, 1.2)


func _update_muzzle_flash(delta: float) -> void:
	if _flash_remaining <= 0.0:
		return
	_flash_remaining -= delta
	if _flash_remaining > 0.0:
		return
	_muzzle_flash.visible = false


## A tinting overlay on every mesh of the model, so the whole barrel glows as it heats.
## It mixes rather than adds: added on top of the light model, every colour washes out to white.
func _setup_heat_glow() -> void:
	_glow_material = StandardMaterial3D.new()
	_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glow_material.albedo_color = Color(COOL_COLOR, 0.0)
	for mesh in _model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_overlay = _glow_material
	_heat_light = OmniLight3D.new()
	_heat_light.omni_range = LIGHT_RANGE
	_heat_light.light_energy = 0.0
	_heat_light.shadow_enabled = false
	muzzle.add_child(_heat_light)


func _update_heat_glow() -> void:
	var color := _get_heat_color(heat)
	var strength := heat * heat
	if is_in_overdrive():
		color = OVERDRIVE_COLOR
		strength = maxf(strength, 0.5)
	strength *= _get_warning_flicker()
	_glow_material.albedo_color = Color(color, strength * GLOW_MAX_ALPHA)
	_heat_light.light_color = color
	_heat_light.light_energy = strength * LIGHT_MAX_ENERGY


## Pulses the glow while a perfect vent is possible, so the front carrier knows to vent now.
func _get_warning_flicker() -> float:
	if not is_in_perfect_window():
		return 1.0
	var wave := sin(Time.get_ticks_msec() / 1000.0 * TAU * WARNING_FLICKER_HZ)
	return 0.65 + 0.35 * wave


func _get_heat_color(value: float) -> Color:
	if value < WARM_HEAT:
		return COOL_COLOR.lerp(WARM_COLOR, value / WARM_HEAT)
	return WARM_COLOR.lerp(HOT_COLOR, (value - WARM_HEAT) / (1.0 - WARM_HEAT))
