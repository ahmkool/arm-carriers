class_name PlayerLocal
extends CharacterBody3D

@export var device_id: int
@export var player_id: int
@export var damage_invulnerability_seconds := 1.0

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

## Matches `LocomotionBlend` (AnimationNodeBlend2) in mannequin_medium.tscn: input 0 = idle, 1 = run.
const ANIM_PARAM_LOCOMOTION_BLEND := &"parameters/LocomotionBlend/blend_amount"
const ANIM_PARAM_DEAD_BLEND := &"parameters/DeadBlend/blend_amount"
const ANIM_PARAM_DEAD_ONESHOT_REQUEST := &"parameters/DeadOneShot/request"

@onready var animation_tree: AnimationTree = $Mannequin_Medium/AnimationTree
@onready var animation_player: AnimationPlayer = $Mannequin_Medium/AnimationPlayer
@onready var carrying_weapon_data: CarryingWeaponData = $CarryingWeaponData
@onready var weapon_carrier_pin_joint = $WeaponCarrierPinJoint
@onready var footsteps_particles: GPUParticles3D = $FootstepsParticles
@onready var footsteps_sound: AudioStreamPlayer3D = $FootstepsSound

var action_left: String
var action_right: String
var action_up: String
var action_down: String
var action_jump: String
var action_accept: String
var action_action: String
var action_shoot: String
var action_dash: String
var _animate_on_dead_enter: bool = true
var _resume_state_after_hit := &"idle"
var _damage_source_position := Vector3.ZERO
var _has_damage_source_position := false
var _hit_flash: HitFlash3D
var is_dead: bool:
	get:
		return is_in_dead_state()

@onready var player_state_machine: PlayerStateMachine = $PlayerStateMachine
@onready var health: Health = $Health

const TWINSTICK_ACTIVE = true

func _ready():
	print("PlayerLocal ready, device_id: ", device_id)
	_bind_health()
	_hit_flash = _get_or_create_hit_flash()
	if animation_tree:
		animation_tree.active = true
		animation_tree.set(ANIM_PARAM_DEAD_BLEND, 0.0)
		animation_tree.set(ANIM_PARAM_DEAD_ONESHOT_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	action_left = "p%s_left" % device_id
	action_right = "p%s_right" % device_id
	action_up = "p%s_up" % device_id
	action_down = "p%s_down" % device_id
	action_jump = "p%s_jump" % device_id
	action_accept = "p%s_accept" % device_id
	action_action = "p%s_action" % device_id
	action_shoot = "p%s_shoot" % device_id
	action_dash = "p%s_dash" % device_id
	player_id = device_id


func _bind_health() -> void:
	if health == null:
		return
	health.damaged.connect(_on_health_damaged)
	health.died.connect(_on_health_died)


func _on_health_damaged(_amount: int, remaining: int, source_position: Vector3) -> void:
	if remaining <= 0:
		return
	if is_in_dead_state():
		return
	_store_damage_source_position(source_position)
	if health != null:
		health.grant_invulnerability(damage_invulnerability_seconds)
	if _hit_flash == null:
		_hit_flash = _get_or_create_hit_flash()
	_hit_flash.trigger()
	_request_taking_damage_state()


func _on_health_died(_source_position: Vector3 = Vector3.ZERO) -> void:
	die(_animate_on_dead_enter)


func _request_taking_damage_state() -> void:
	if player_state_machine == null:
		return
	if is_in_dead_state():
		return
	if _is_in_taking_damage_state():
		var current := player_state_machine.current_state
		if current != null and current.has_method("refresh_hit"):
			current.call("refresh_hit")
		return
	if player_state_machine.current_state != null:
		var prior_state := player_state_machine.current_state.name.to_lower()
		if _can_resume_after_hit(prior_state):
			_resume_state_after_hit = StringName(prior_state)
	player_state_machine.transition_to("takingdamage")


func _can_resume_after_hit(state_name: String) -> bool:
	if state_name == "dead":
		return false
	if state_name == "takingdamage":
		return false
	if state_name == "dashing":
		return false
	return true


func _is_in_taking_damage_state() -> bool:
	if player_state_machine == null:
		return false
	if player_state_machine.current_state == null:
		return false
	return player_state_machine.current_state.name.to_lower() == "takingdamage"


func resume_state_after_hit() -> void:
	if not is_on_floor():
		player_state_machine.transition_to("falling")
		return
	var resume := String(_resume_state_after_hit)
	if not resume.is_empty() and resume != "takingdamage" and player_state_machine.states.has(resume):
		if resume == "running" and get_move_direction().length_squared() < 0.0001:
			player_state_machine.transition_to("idle")
			return
		player_state_machine.transition_to(resume)
		return
	_resolve_locomotion_after_hit()


func _resolve_locomotion_after_hit() -> void:
	if not is_on_floor():
		player_state_machine.transition_to("falling")
		return
	if get_move_direction().length_squared() > 0.0001:
		player_state_machine.transition_to("running")
		return
	player_state_machine.transition_to("idle")


func get_hit_knockback_direction() -> Vector3:
	if not _has_damage_source_position:
		return Vector3.ZERO
	var away := global_position - _damage_source_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return Vector3.ZERO
	return away.normalized()


func _store_damage_source_position(damage_source_position: Variant) -> void:
	_has_damage_source_position = damage_source_position is Vector3
	if not _has_damage_source_position:
		return
	_damage_source_position = damage_source_position as Vector3


func play_hit_animation() -> void:
	if animation_player == null:
		return
	var candidates: Array[StringName] = [
		&"Player/Hit_A",
		&"Player/Hit_B",
		&"Hit_A",
		&"Hit_B",
	]
	for anim_name in candidates:
		if animation_player.has_animation(anim_name):
			animation_player.play(anim_name)
			return


func _get_or_create_hit_flash() -> HitFlash3D:
	var existing := get_node_or_null("HitFlash3D")
	if existing is HitFlash3D:
		return existing as HitFlash3D
	var flash := HitFlash3D.new()
	flash.name = "HitFlash3D"
	add_child(flash)
	return flash


## Drives blend tree: 0 = idle, 1 = full run, from horizontal speed / SPEED.
func update_locomotion_blend() -> void:
	if is_in_dead_state():
		return
	if _is_in_taking_damage_state():
		return
	if not animation_tree or not animation_tree.active:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var blend := clampf(horizontal_speed / SPEED, 0.0, 1.0)
	animation_tree.set(ANIM_PARAM_LOCOMOTION_BLEND, blend)


func get_move_direction() -> Vector3:
	if GameplayInput.is_locked():
		return Vector3.ZERO
	var input_dir = Input.get_vector(action_left, action_right, action_up, action_down)
	var direction := Vector3(input_dir.x, 0.0, input_dir.y)
	if direction.length_squared() > 0.0001:
		return direction.normalized()
	return Vector3.ZERO


func is_dashing() -> bool:
	if player_state_machine == null:
		return false
	if player_state_machine.current_state == null:
		return false
	return player_state_machine.current_state.name.to_lower() == "dashing"


func die(animate_death: bool = true) -> void:
	if is_in_dead_state():
		return
	_animate_on_dead_enter = animate_death
	velocity = Vector3.ZERO
	carrying_weapon_data.can_carry_status = CarryingWeaponData.CanCarryStatus.NO_WEAPON_AVAILABLE
	weapon_carrier_pin_joint.set_node_b("")
	if has_node("UI"):
		$UI.hide()
	player_state_machine.transition_to("dead")

func is_in_dead_state() -> bool:
	if not player_state_machine:
		return false
	return player_state_machine.current_state.name.to_lower() == "dead"

func revive() -> void:
	if health != null:
		health.reset_to_full()
	_animate_on_dead_enter = true
	velocity = Vector3.ZERO
	carrying_weapon_data.can_carry_status = CarryingWeaponData.CanCarryStatus.NO_WEAPON_AVAILABLE
	weapon_carrier_pin_joint.set_node_b("")
	if animation_tree:
		animation_tree.active = true
		animation_tree.set(ANIM_PARAM_DEAD_BLEND, 0.0)
		animation_tree.set(ANIM_PARAM_LOCOMOTION_BLEND, 0.0)
		animation_tree.set(ANIM_PARAM_DEAD_ONESHOT_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	if has_node("UI"):
		$UI.show()
	player_state_machine.transition_to("idle")


func play_dead_animation() -> void:
	if not animation_tree or not animation_tree.active:
		return
	animation_tree.set(ANIM_PARAM_DEAD_ONESHOT_REQUEST, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	animation_tree.set(ANIM_PARAM_DEAD_BLEND, 1.0)
