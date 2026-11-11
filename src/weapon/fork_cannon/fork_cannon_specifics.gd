class_name ForkCannonSpecifics
extends Node3D
## A gun that forks into two barrels, one per carrier. The back carrier holds the shoot button
## to stream bolts from the right prong, like the pulse rifle. The front carrier presses theirs
## to fire a missile from the left prong, which blows up like a bazooka rocket; holding it
## fires again each time the tube reloads.
##
## The barrels work together: bolts paint the enemy they hit, and a few hits on the same enemy
## lock it. A missile fired with a lock steers to that enemy, so the back carrier marks the
## target and the front carrier picks the moment. Without a lock the missile flies straight,
## the way a bazooka rocket does, so it still clears a bunched-up crowd in front of the gun.

signal bolt_fired(bolt: PulseBolt)
signal missile_fired(missile: ForkMissile)
signal locked(enemy: EnemyLocal)

const BOLT_INTERVAL_SEC := 0.12
const BOLT_DAMAGE := 1
const BOLT_SPEED := 42.0
const BOLT_RANGE := 30.0
const BOLT_SPREAD_DEG := 2.0
const BOLT_TRAUMA := 0.05
const BOLT_FLASH_COLOR := Color(0.45, 0.95, 1.0)
const FLASH_VISIBLE_SEC := 0.04

## Bolt hits on the same enemy that set a lock.
const HITS_TO_LOCK := 4
## A paint or lock with no fresh bolt hit for this long fades away.
const PAINT_HOLD_SEC := 3.0
## The missile tube reloads this long after a launch.
const MISSILE_RELOAD_SEC := 2.2
const LAUNCH_WORD := "LAUNCH"

const BOLT_SCENE := preload("res://src/weapon/pulse_rifle/pulse_bolt.tscn")
const MISSILE_SCENE := preload("res://src/weapon/fork_cannon/fork_missile.tscn")
const SHOT_SOUNDS: Array[AudioStream] = [
	preload("res://assets/sounds/gun/Gun 6-1.wav"),
	preload("res://assets/sounds/gun/Gun 6-2.wav"),
]
const LOCK_SOUND := preload("res://assets/sounds/ammo/reload.wav")

@export var pick_and_drop_handler: PickAndDropHandler

## The bolt barrel. Named `muzzle` like the other guns', for code that aims along the gun.
@onready var muzzle: Marker3D = $BoltMuzzle
@onready var missile_muzzle: Marker3D = $MissileMuzzle
@onready var _muzzle_flash: Node3D = $BoltMuzzle/MuzzleFlash
## The missile nose showing in the tube; hidden while it reloads.
@onready var _loaded_missile: Node3D = $MissileMuzzle/LoadedMissile

var _bolt_cooldown := 0.0
var _missile_reload := 0.0
var _flash_remaining := 0.0
var _paint_target: EnemyLocal
var _paint_hits := 0
var _paint_age := 0.0
var _reticle: LockReticle
var _launch_prompt: FrontCarrierPrompt


func _ready() -> void:
	_muzzle_flash.visible = false
	_reticle = LockReticle.new()
	add_child(_reticle)
	_launch_prompt = FrontCarrierPrompt.new(LAUNCH_WORD)
	add_child(_launch_prompt)


func _physics_process(delta: float) -> void:
	_bolt_cooldown = maxf(0.0, _bolt_cooldown - delta)
	_missile_reload = maxf(0.0, _missile_reload - delta)
	_loaded_missile.visible = is_missile_loaded()
	_update_muzzle_flash(delta)
	_update_paint(delta)
	var carry_info := pick_and_drop_handler.get_carry_info()
	if not _is_carried_by_both(carry_info):
		_launch_prompt.hide_prompt()
		return
	var ready_to_strike := is_missile_loaded() and get_locked_target() != null
	_launch_prompt.update_prompt(carry_info.secondary_carrier, ready_to_strike, ready_to_strike, delta)
	_try_launch(carry_info.secondary_carrier)
	_try_fire_bolt(carry_info.main_carrier)


func is_missile_loaded() -> bool:
	return _missile_reload <= 0.0


## The enemy a missile fired now would steer to, or null.
func get_locked_target() -> EnemyLocal:
	if not _has_live_paint():
		return null
	if _paint_hits < HITS_TO_LOCK:
		return null
	return _paint_target


## Fires one bolt straight away, ignoring input and the fire rate. Used by test drivers.
func fire_bolt() -> PulseBolt:
	var bolt := BOLT_SCENE.instantiate() as PulseBolt
	get_tree().current_scene.add_child(bolt)
	bolt.enemy_hit.connect(_on_bolt_hit_enemy)
	bolt.launch(muzzle.global_position, _get_bolt_direction(), BOLT_SPEED, BOLT_RANGE, BOLT_DAMAGE)
	_bolt_cooldown = BOLT_INTERVAL_SEC
	_play_bolt_feedback()
	bolt_fired.emit(bolt)
	return bolt


## Fires a missile straight away, at the locked enemy if there is one. Used by test drivers.
func launch_missile() -> ForkMissile:
	var missile := MISSILE_SCENE.instantiate() as ForkMissile
	get_tree().current_scene.add_child(missile)
	var homing_target := get_locked_target()
	missile.launch(missile_muzzle.global_position, missile_muzzle.global_basis.z, homing_target)
	_missile_reload = MISSILE_RELOAD_SEC
	_loaded_missile.visible = false
	if homing_target != null:
		FrontCarrierPrompt.note_use(LAUNCH_WORD)
	_play_missile_feedback()
	missile_fired.emit(missile)
	return missile


func _is_carried_by_both(carry_info: CarryInfo) -> bool:
	return is_instance_valid(carry_info.main_carrier) and is_instance_valid(carry_info.secondary_carrier)


func _try_fire_bolt(shooter: PlayerLocal) -> void:
	if GameplayInput.is_locked():
		return
	if not Input.is_action_pressed(shooter.action_shoot):
		return
	if _bolt_cooldown > 0.0:
		return
	fire_bolt()


func _try_launch(front_carrier: PlayerLocal) -> void:
	if GameplayInput.is_locked():
		return
	if not Input.is_action_pressed(front_carrier.action_shoot):
		return
	if is_missile_loaded():
		launch_missile()
		return
	# Holding the button waits for the reload and fires again; only a fresh press clicks dry.
	if Input.is_action_just_pressed(front_carrier.action_shoot):
		_play_dry_click(front_carrier, missile_muzzle.global_position)


## A hit on the painted enemy adds to its paint. A hit on another enemy moves the paint there,
## unless the painted one is already locked: a lock holds until it fades or its enemy dies.
func _on_bolt_hit_enemy(enemy: EnemyLocal) -> void:
	if not is_instance_valid(enemy) or not enemy.is_alive():
		return
	if enemy == _paint_target:
		_add_paint()
		return
	if get_locked_target() != null:
		return
	_paint_target = enemy
	_paint_hits = 0
	_add_paint()


func _add_paint() -> void:
	_paint_age = 0.0
	_paint_hits += 1
	if _paint_hits != HITS_TO_LOCK:
		return
	_play_lock_feedback()
	locked.emit(_paint_target)


func _update_paint(delta: float) -> void:
	_paint_age += delta
	if not _has_live_paint():
		_paint_target = null
		_paint_hits = 0
		_reticle.clear()
		return
	var progress := float(_paint_hits) / HITS_TO_LOCK
	_reticle.show_on(_paint_target, progress, _paint_hits >= HITS_TO_LOCK)


func _has_live_paint() -> bool:
	if not is_instance_valid(_paint_target):
		return false
	if not _paint_target.is_alive():
		return false
	return _paint_age < PAINT_HOLD_SEC


func _get_bolt_direction() -> Vector3:
	var forward := muzzle.global_basis.z
	forward.y = 0.0
	var angle := deg_to_rad(randf_range(-BOLT_SPREAD_DEG, BOLT_SPREAD_DEG))
	return forward.normalized().rotated(Vector3.UP, angle)


func _play_bolt_feedback() -> void:
	var sound: AudioStream = SHOT_SOUNDS.pick_random()
	ImpactFeedback.play_sfx(sound, muzzle.global_position, randf_range(1.0, 1.15), -9.0)
	CameraFeedback.add_trauma(BOLT_TRAUMA)
	_show_muzzle_flash()
	var feedback := _get_carry_feedback()
	if feedback == null:
		return
	feedback.play_light_recoil(muzzle.global_position, BOLT_FLASH_COLOR)


## The missile brings its own launch sound; this is the kick in both carriers' hands.
func _play_missile_feedback() -> void:
	CameraFeedback.add_trauma_shot()
	var feedback := _get_carry_feedback()
	if feedback == null:
		return
	feedback.play_recoil(missile_muzzle.global_basis.z, missile_muzzle.global_position)


## A rising click and a buzz for the front carrier: the missile now has somewhere to go.
func _play_lock_feedback() -> void:
	ImpactFeedback.play_sfx(LOCK_SOUND, missile_muzzle.global_position, 1.8, -6.0)
	var front := pick_and_drop_handler.get_carry_info().secondary_carrier
	if not is_instance_valid(front):
		return
	ImpactFeedback.rumble(front, 0.5, 0.3, 0.12)


func _play_dry_click(shooter: PlayerLocal, at_position: Vector3) -> void:
	var feedback := _get_carry_feedback()
	if feedback == null:
		return
	feedback.play_dry_click(shooter, at_position)


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
