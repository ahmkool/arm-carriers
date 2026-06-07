class_name BazookaSpecifics
extends Node3D

@export var pick_and_drop_handler: PickAndDropHandler
@onready var muzzle: Marker3D = $Muzzle

var _bazooka_bullet_scene: PackedScene = preload("res://src/weapon/bazooka_bullet_local.tscn")

const FIRE_COOLDOWN_SEC := 0.75
var _fire_cooldown_remaining := 0.0


func _physics_process(delta: float) -> void:
	_fire_cooldown_remaining = maxf(0.0, _fire_cooldown_remaining - delta)
	if pick_and_drop_handler == null:
		return

	var carry_info: CarryInfo = pick_and_drop_handler.get_carry_info()
	if not is_instance_valid(carry_info.main_carrier):
		return
	if not is_instance_valid(carry_info.secondary_carrier):
		return
	_check_firing_bullet(carry_info)


func _check_firing_bullet(carry_info: CarryInfo) -> void:
	if GameplayInput.is_locked():
		return
	if not Input.is_action_just_pressed(carry_info.main_carrier.action_shoot):
		return
	if _fire_cooldown_remaining > 0.0:
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
	CameraFeedback.add_trauma_shot()
