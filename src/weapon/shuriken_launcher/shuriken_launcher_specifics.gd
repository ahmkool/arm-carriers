class_name ShurikenLauncherSpecifics
extends Node3D
## A launch rail with a giant throwing star lying on its deck. The back carrier presses shoot to
## fling the star: it flies flat and spinning, slicing through every enemy in its path, then hangs
## at the end of its range for a moment and pops.
##
## A kunai rides in each of the star's four blades. While the star is out, the front carrier
## holds shoot to slow it down: it drifts and turns in slow motion, with lines along the blades
## showing where the kunai would go. Letting go scatters them: all four fly out along the blades at
## once. A quick tap scatters them almost straight away. So the back carrier aims the line, and the
## front carrier picks where along it the star bursts and which way its blades point.

signal shuriken_launched(shuriken: Shuriken)
signal kunais_scattered(kunais: Array[Kunai])

const SHURIKEN_SPEED := 15.0
const SHURIKEN_RANGE := 9.0
const SHURIKEN_DAMAGE := 2
## Counted from the launch, so a star can still be out when the next one is ready.
const RELOAD_SEC := 1.2
## Turns per second of the star waiting on the deck: a slow idle spin that says "loaded".
const IDLE_SPIN_HZ := 0.25
const SCATTER_WORD := "SCATTER"
## A hold this long scatters the kunai by itself, so a held button can't keep a star out forever.
const MAX_HOLD_SEC := 2.5
## The camera frames a point this far past a star in flight, so the front carrier can see where it
## is when they scatter its kunai, and both can see where they fly.
const CAMERA_LEAD := 6.0
const LAUNCH_SOUND := preload("res://assets/sounds/slash_1.wav")

@export var pick_and_drop_handler: PickAndDropHandler

## Where the star leaves the deck. Named `muzzle` like the guns', for code that aims along the gun.
@onready var muzzle: Marker3D = $ShurikenMuzzle
@onready var _loaded: ShurikenVisual = $ShurikenMuzzle/LoadedShuriken
@onready var _camera_target: Marker3D = $CameraAddons/Marker3D

var _reload := 0.0
var _in_flight: Array[Shuriken] = []
var _scatter_prompt: FrontCarrierPrompt
var _camera_target_rest := Vector3.ZERO
## The stars the front carrier is slowing with a held button; empty when they aren't holding.
var _held: Array[Shuriken] = []
var _hold_sec := 0.0


func _ready() -> void:
	_camera_target_rest = _camera_target.position
	_scatter_prompt = FrontCarrierPrompt.new(SCATTER_WORD)
	add_child(_scatter_prompt)


func _physics_process(delta: float) -> void:
	_reload = maxf(0.0, _reload - delta)
	_loaded.visible = is_loaded()
	_loaded.rotation.y = wrapf(_loaded.rotation.y + IDLE_SPIN_HZ * TAU * delta, 0.0, TAU)
	_forget_spent_shurikens()
	_update_camera_target()
	var carry_info := pick_and_drop_handler.get_carry_info()
	if not _is_carried_by_both(carry_info):
		_scatter_prompt.hide_prompt()
		_release_hold()
		return
	var can_scatter := _has_scatterable()
	_scatter_prompt.update_prompt(carry_info.secondary_carrier, can_scatter, _is_any_hovering(), delta)
	_try_launch(carry_info.main_carrier)
	_try_start_hold(carry_info.secondary_carrier)
	_update_hold(carry_info.secondary_carrier, delta)


func is_loaded() -> bool:
	return _reload <= 0.0


## Stars still flying with their kunai, oldest first.
func get_scatterable() -> Array[Shuriken]:
	var scatterable: Array[Shuriken] = []
	scatterable.assign(_in_flight.filter(_can_scatter))
	return scatterable


## Flings a star straight away, ignoring input and the reload. Used by test drivers.
func launch_shuriken() -> Shuriken:
	var shuriken := Shuriken.new()
	get_tree().current_scene.add_child(shuriken)
	shuriken.launch(muzzle.global_position, muzzle.global_basis.z, SHURIKEN_SPEED, SHURIKEN_RANGE, SHURIKEN_DAMAGE, _loaded.global_rotation.y)
	_in_flight.append(shuriken)
	_reload = RELOAD_SEC
	_loaded.visible = false
	_play_launch_feedback()
	shuriken_launched.emit(shuriken)
	return shuriken


func is_holding() -> bool:
	return not _held.is_empty()


## Slows every star still carrying kunai, as the front carrier's held button does. Used by test drivers.
func start_hold() -> void:
	_held = get_scatterable()
	_hold_sec = 0.0
	for shuriken: Variant in _held:
		shuriken.set_slowed(true)


## Scatters the kunai of every star still carrying them. Returns all the kunai thrown.
func scatter_kunais() -> Array[Kunai]:
	_release_hold()
	var thrown: Array[Kunai] = []
	for shuriken in get_scatterable():
		thrown.append_array(shuriken.scatter())
	if thrown.is_empty():
		return thrown
	FrontCarrierPrompt.note_use(SCATTER_WORD)
	CameraFeedback.add_trauma(0.15)
	kunais_scattered.emit(thrown)
	return thrown


func _is_carried_by_both(carry_info: CarryInfo) -> bool:
	return is_instance_valid(carry_info.main_carrier) and is_instance_valid(carry_info.secondary_carrier)


func _try_launch(back_carrier: PlayerLocal) -> void:
	if GameplayInput.is_locked():
		return
	if not Input.is_action_just_pressed(back_carrier.action_shoot):
		return
	if not is_loaded():
		_play_dry_click(back_carrier, muzzle.global_position)
		return
	launch_shuriken()


func _try_start_hold(front_carrier: PlayerLocal) -> void:
	if GameplayInput.is_locked():
		return
	if not Input.is_action_just_pressed(front_carrier.action_shoot):
		return
	if not _has_scatterable():
		_play_dry_click(front_carrier, front_carrier.global_position)
		return
	start_hold()


## Letting go, or holding too long, scatters the held stars' kunai.
func _update_hold(front_carrier: PlayerLocal, delta: float) -> void:
	if not is_holding():
		return
	_hold_sec += delta
	if _is_still_holding(front_carrier):
		return
	scatter_kunais()


func _is_still_holding(front_carrier: PlayerLocal) -> bool:
	if _hold_sec >= MAX_HOLD_SEC:
		return false
	if GameplayInput.is_locked():
		return false
	return Input.is_action_pressed(front_carrier.action_shoot)


## Lets the held stars speed up again without scattering, such as when the carriers drop the launcher.
func _release_hold() -> void:
	for shuriken: Variant in _held:
		if is_instance_valid(shuriken):
			shuriken.set_slowed(false)
	_held.clear()


func _has_scatterable() -> bool:
	return not get_scatterable().is_empty()


func _is_any_hovering() -> bool:
	return get_scatterable().any(func(s: Shuriken): return s.is_hovering())


func _can_scatter(shuriken) -> bool:
	if not is_instance_valid(shuriken):
		return false
	return shuriken.has_kunais()


## Follows the newest star in flight, otherwise rests ahead of the launcher.
func _update_camera_target() -> void:
	if _in_flight.is_empty():
		_camera_target.position = _camera_target_rest
		return
	var forward := muzzle.global_basis.z
	forward.y = 0.0
	_camera_target.global_position = _in_flight.back().global_position + forward.normalized() * CAMERA_LEAD


func _forget_spent_shurikens() -> void:
	# Untyped: a freed star can't be passed as a Shuriken.
	_in_flight.assign(_in_flight.filter(func(s): return is_instance_valid(s) and not s.is_spent()))


func _play_launch_feedback() -> void:
	ImpactFeedback.play_sfx(LAUNCH_SOUND, muzzle.global_position, randf_range(0.7, 0.8), 0.0)
	CameraFeedback.add_trauma_shot()
	var feedback := _get_carry_feedback()
	if feedback == null:
		return
	feedback.play_recoil(muzzle.global_basis.z, muzzle.global_position)


func _play_dry_click(carrier: PlayerLocal, at_position: Vector3) -> void:
	var feedback := _get_carry_feedback()
	if feedback == null:
		return
	feedback.play_dry_click(carrier, at_position)


func _get_carry_feedback() -> CarryFeedback:
	return CarryFeedback.from_weapon(get_parent())
