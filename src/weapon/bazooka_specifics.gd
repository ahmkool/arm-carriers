class_name BazookaSpecifics
extends Node3D
## The back carrier's shoot button fires a slow rocket. While rockets fly, the front carrier's
## shoot button detonates the oldest one mid-air, to catch enemies the rocket would miss.

signal fired(rocket: BazookaBulletLocal)
signal detonated(rocket: BazookaBulletLocal)

@export var pick_and_drop_handler: PickAndDropHandler
@onready var muzzle: Marker3D = $Muzzle
## The warhead tip showing in the muzzle; hidden while the next rocket reloads.
@onready var _loaded_rocket: Node3D = get_node_or_null("Model/LoadedRocket")

var _bazooka_bullet_scene: PackedScene = preload("res://src/weapon/bazooka_bullet_local.tscn")

const FIRE_COOLDOWN_SEC := 0.75
const DETONATE_WORD := "DETONATE"
const DETONATE_SOUND := preload("res://assets/sounds/ammo/reload.wav")
var _fire_cooldown_remaining := 0.0
## Rockets fired by this bazooka that are still flying, oldest first.
var _rockets_in_flight: Array[BazookaBulletLocal] = []
var _detonate_prompt: FrontCarrierPrompt


func _ready() -> void:
	_detonate_prompt = FrontCarrierPrompt.new(DETONATE_WORD)
	add_child(_detonate_prompt)


func _physics_process(delta: float) -> void:
	_fire_cooldown_remaining = maxf(0.0, _fire_cooldown_remaining - delta)
	_update_loaded_rocket()
	_prune_rockets()
	if pick_and_drop_handler == null:
		return

	var carry_info: CarryInfo = pick_and_drop_handler.get_carry_info()
	if not _is_carried_by_both(carry_info):
		_detonate_prompt.hide_prompt()
		return
	_check_detonating(carry_info.secondary_carrier)
	_check_firing_bullet(carry_info)
	var in_flight := get_oldest_rocket() != null
	_detonate_prompt.update_prompt(carry_info.secondary_carrier, in_flight, in_flight, delta)


func get_oldest_rocket() -> BazookaBulletLocal:
	_prune_rockets()
	if _rockets_in_flight.is_empty():
		return null
	return _rockets_in_flight[0]


## Blows up the oldest rocket in flight straight away. Used by `_check_detonating` and test
## drivers. Returns the rocket, or null when none was flying.
func detonate_oldest() -> BazookaBulletLocal:
	var rocket := get_oldest_rocket()
	if rocket == null:
		return null
	_rockets_in_flight.erase(rocket)
	rocket.detonate()
	FrontCarrierPrompt.note_use(DETONATE_WORD)
	_play_detonate_feedback()
	detonated.emit(rocket)
	return rocket


func _is_carried_by_both(carry_info: CarryInfo) -> bool:
	return is_instance_valid(carry_info.main_carrier) and is_instance_valid(carry_info.secondary_carrier)


func _check_detonating(front_carrier: PlayerLocal) -> void:
	if GameplayInput.is_locked():
		return
	if not Input.is_action_just_pressed(front_carrier.action_shoot):
		return
	if get_oldest_rocket() == null:
		_play_dry_click(front_carrier)
		return
	detonate_oldest()


## Drops rockets that hit something, fizzled out or were freed.
func _prune_rockets() -> void:
	_rockets_in_flight.assign(_rockets_in_flight.filter(func(r): return is_instance_valid(r) and not r.is_spent()))


func _check_firing_bullet(carry_info: CarryInfo) -> void:
	if GameplayInput.is_locked():
		return
	if not Input.is_action_just_pressed(carry_info.main_carrier.action_shoot):
		return
	if _fire_cooldown_remaining > 0.0:
		_play_dry_click(carry_info.main_carrier)
		return
	_request_fire_bullet()


func _request_fire_bullet() -> void:
	print("requesting to fire bullet")
	var bullet: BazookaBulletLocal = _bazooka_bullet_scene.instantiate() as BazookaBulletLocal
	if bullet == null:
		return
	get_tree().current_scene.add_child(bullet)
	bullet.global_position = muzzle.global_position
	bullet.global_rotation = global_rotation
	bullet.velocity = muzzle.global_transform.basis.z * 5.0
	_fire_cooldown_remaining = FIRE_COOLDOWN_SEC
	_rockets_in_flight.append(bullet)
	fired.emit(bullet)
	_update_loaded_rocket()
	CameraFeedback.add_trauma_shot()
	_play_recoil()


func _update_loaded_rocket() -> void:
	if _loaded_rocket == null:
		return
	_loaded_rocket.visible = _fire_cooldown_remaining <= 0.0


func _play_recoil() -> void:
	var feedback := CarryFeedback.from_weapon(get_parent())
	if feedback == null:
		return
	feedback.play_recoil(muzzle.global_transform.basis.z, muzzle.global_position)


## The explosion brings its own blast and shake; this is the trigger click in the front hands.
func _play_detonate_feedback() -> void:
	var front := pick_and_drop_handler.get_carry_info().secondary_carrier
	ImpactFeedback.play_sfx(DETONATE_SOUND, muzzle.global_position, 1.5, -6.0)
	if not is_instance_valid(front):
		return
	ImpactFeedback.rumble(front, 0.6, 0.5, 0.12)


func _play_dry_click(shooter: PlayerLocal) -> void:
	var feedback := CarryFeedback.from_weapon(get_parent())
	if feedback == null:
		return
	feedback.play_dry_click(shooter, muzzle.global_position)
