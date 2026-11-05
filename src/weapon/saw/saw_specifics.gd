class_name SawSpecifics
extends Node3D
## Feedback while the disc is cutting: grind loop, sparks, slowed spin and weapon shudder.
## `saw/hit_box.gd` reports the contacts.

const SPARKS_SCENE := preload("res://src/vfx/saw_sparks.tscn")
const GRIND_SOUND := preload("res://assets/sounds/cogs/807844__sabacky__complex-mechanism-long.wav")

const GRIND_HOLD_SEC := 0.25
const GRIND_TICK_SEC := 0.07
const GRIND_TICK_SPARK_DENSITY := 0.3
const GRIND_PITCH := 1.5
const GRIND_VOLUME_DB := -8.0
const GRIND_SILENT_DB := -40.0
const GRIND_FADE_DB_PER_SEC := 120.0

const SPIN_NORMAL := 1.0
const SPIN_WHILE_GRINDING := 0.45
const SPIN_ON_BITE := 0.2
const SPIN_CHANGE_PER_SEC := 2.5

var _grind_hold := 0.0
var _grind_tick_cooldown := 0.0
var _contact_point := Vector3.ZERO
var _spin := SPIN_NORMAL

@onready var _spin_animation: AnimationPlayer = $"../AnimationPlayer"
var _grind_sfx: AudioStreamPlayer3D


func _ready() -> void:
	_grind_sfx = AudioStreamPlayer3D.new()
	_grind_sfx.bus = "SFX"
	_grind_sfx.stream = GRIND_SOUND
	_grind_sfx.pitch_scale = GRIND_PITCH
	_grind_sfx.volume_db = GRIND_SILENT_DB
	_grind_sfx.finished.connect(_on_grind_sfx_finished)
	add_child(_grind_sfx)


## A hit landed on an enemy.
func notify_bite(contact_point: Vector3) -> void:
	notify_contact(contact_point)
	_spin = SPIN_ON_BITE
	_spawn_sparks(1.0)
	var feedback := _get_carry_feedback()
	if feedback == null:
		return
	feedback.play_saw_bite()


## A live enemy is touching the disc, whether or not a hit landed this time.
func notify_contact(contact_point: Vector3) -> void:
	_contact_point = contact_point
	_grind_hold = GRIND_HOLD_SEC


func _process(delta: float) -> void:
	_grind_hold = maxf(0.0, _grind_hold - delta)
	_grind_tick_cooldown = maxf(0.0, _grind_tick_cooldown - delta)
	_update_spin(delta)
	_update_grind_sound(delta)
	_try_grind_tick()


func _update_spin(delta: float) -> void:
	var target := SPIN_WHILE_GRINDING if _grind_hold > 0.0 else SPIN_NORMAL
	_spin = move_toward(_spin, target, SPIN_CHANGE_PER_SEC * delta)
	_spin_animation.speed_scale = _spin


func _update_grind_sound(delta: float) -> void:
	var target_db := GRIND_VOLUME_DB if _grind_hold > 0.0 else GRIND_SILENT_DB
	_grind_sfx.volume_db = move_toward(_grind_sfx.volume_db, target_db, GRIND_FADE_DB_PER_SEC * delta)
	if _grind_hold > 0.0 and not _grind_sfx.playing:
		_grind_sfx.play()
	if _grind_hold <= 0.0 and _grind_sfx.volume_db <= GRIND_SILENT_DB and _grind_sfx.playing:
		_grind_sfx.stop()


func _on_grind_sfx_finished() -> void:
	if _grind_hold <= 0.0:
		return
	_grind_sfx.play()


func _try_grind_tick() -> void:
	if _grind_hold <= 0.0 or _grind_tick_cooldown > 0.0:
		return
	_grind_tick_cooldown = GRIND_TICK_SEC
	_spawn_sparks(GRIND_TICK_SPARK_DENSITY)
	var feedback := _get_carry_feedback()
	if feedback == null:
		return
	feedback.play_saw_grind_tick()


func _spawn_sparks(density: float) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var sparks := SPARKS_SCENE.instantiate() as GPUParticles3D
	sparks.amount_ratio = density
	scene_root.add_child(sparks)
	sparks.global_position = _contact_point
	sparks.emitting = true


func _get_carry_feedback() -> CarryFeedback:
	return CarryFeedback.from_weapon(get_parent())
