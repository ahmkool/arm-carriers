class_name PulseRifleSpecifics
extends Node3D
## Rapid-fire rifle. The back carrier holds the shoot button for a steady stream of bolts,
## and the front carrier steers it. Each bolt hits for little, so the rifle trades the
## bazooka's one big blast for sustained, aimed fire. Bolts can also shoot down plasma.

signal fired(bolt: PulseBolt)

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

const BOLT_SCENE := preload("res://src/weapon/pulse_rifle/pulse_bolt.tscn")
const SHOT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/sounds/gun/Gun 6-1.wav"),
	preload("res://assets/sounds/gun/Gun 6-2.wav"),
]

@export var pick_and_drop_handler: PickAndDropHandler

@onready var muzzle: Marker3D = $Muzzle
@onready var _muzzle_flash: Node3D = $Muzzle/MuzzleFlash

var _cooldown_remaining := 0.0
var _flash_remaining := 0.0


func _ready() -> void:
	_muzzle_flash.visible = false


func _physics_process(delta: float) -> void:
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	_update_muzzle_flash(delta)
	var carry_info := pick_and_drop_handler.get_carry_info()
	if not _is_carried_by_both(carry_info):
		return
	_try_fire(carry_info.main_carrier)


## Fires one bolt straight away, ignoring input and the fire rate. Used by test drivers.
func fire_bolt() -> PulseBolt:
	var bolt := BOLT_SCENE.instantiate() as PulseBolt
	get_tree().current_scene.add_child(bolt)
	bolt.launch(muzzle.global_position, _get_spread_direction(), BOLT_SPEED, BOLT_RANGE, DAMAGE)
	_cooldown_remaining = FIRE_INTERVAL_SEC
	_play_shot_feedback()
	fired.emit(bolt)
	return bolt


func _is_carried_by_both(carry_info: CarryInfo) -> bool:
	return is_instance_valid(carry_info.main_carrier) and is_instance_valid(carry_info.secondary_carrier)


func _try_fire(shooter: PlayerLocal) -> void:
	if GameplayInput.is_locked():
		return
	if not Input.is_action_pressed(shooter.action_shoot):
		return
	if _cooldown_remaining > 0.0:
		return
	fire_bolt()


func _get_spread_direction() -> Vector3:
	var forward := muzzle.global_basis.z
	forward.y = 0.0
	var angle := deg_to_rad(randf_range(-SPREAD_DEG, SPREAD_DEG))
	return forward.normalized().rotated(Vector3.UP, angle)


func _play_shot_feedback() -> void:
	var sound: AudioStream = SHOT_SOUNDS.pick_random()
	ImpactFeedback.play_sfx(sound, muzzle.global_position, randf_range(0.95, 1.12), -8.0)
	CameraFeedback.add_trauma(SHOT_TRAUMA)
	_show_muzzle_flash()
	var feedback := CarryFeedback.from_weapon(get_parent())
	if feedback == null:
		return
	feedback.play_light_recoil(muzzle.global_position, FLASH_COLOR)


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
