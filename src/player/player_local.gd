class_name PlayerLocal
extends CharacterBody3D

@export var device_id: int
@export var player_id: int

const SPEED = 5.0
const JUMP_VELOCITY = 4.5

## Matches `LocomotionBlend` (AnimationNodeBlend2) in mannequin_medium.tscn: input 0 = idle, 1 = run.
const ANIM_PARAM_LOCOMOTION_BLEND := &"parameters/LocomotionBlend/blend_amount"
const ANIM_PARAM_DEAD_BLEND := &"parameters/DeadBlend/blend_amount"

@onready var animation_tree: AnimationTree = $Mannequin_Medium/AnimationTree
@onready var carrying_weapon_data: CarryingWeaponData = $CarryingWeaponData
@onready var weapon_carrier_pin_joint = $WeaponCarrierPinJoint
@onready var footsteps_particles: GPUParticles3D = $FootstepsParticles

var action_left: String
var action_right: String
var action_up: String
var action_down: String
var action_jump: String
var action_accept: String
var action_action: String
var action_shoot: String
var action_dash: String
var is_dead := false

@onready var player_state_machine: PlayerStateMachine = $PlayerStateMachine

func _ready():
	print("PlayerLocal ready, device_id: ", device_id)
	if animation_tree:
		animation_tree.active = true
		animation_tree.set(ANIM_PARAM_DEAD_BLEND, 0.0)
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


## Drives blend tree: 0 = idle, 1 = full run, from horizontal speed / SPEED.
func update_locomotion_blend() -> void:
	if not animation_tree or not animation_tree.active:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var blend := clampf(horizontal_speed / SPEED, 0.0, 1.0)
	animation_tree.set(ANIM_PARAM_LOCOMOTION_BLEND, blend)


func get_move_direction() -> Vector3:
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


func die() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector3.ZERO
	carrying_weapon_data.can_carry_status = CarryingWeaponData.CanCarryStatus.NO_WEAPON_AVAILABLE
	weapon_carrier_pin_joint.set_node_b("")
	if has_node("UI"):
		$UI.hide()
	player_state_machine.transition_to("dead")


func revive() -> void:
	is_dead = false
	velocity = Vector3.ZERO
	carrying_weapon_data.can_carry_status = CarryingWeaponData.CanCarryStatus.NO_WEAPON_AVAILABLE
	weapon_carrier_pin_joint.set_node_b("")
	if animation_tree:
		animation_tree.active = true
		animation_tree.set(ANIM_PARAM_DEAD_BLEND, 0.0)
		animation_tree.set(ANIM_PARAM_LOCOMOTION_BLEND, 0.0)
	if has_node("UI"):
		$UI.show()
	player_state_machine.transition_to("idle")


func play_dead_animation() -> void:
	if not animation_tree or not animation_tree.active:
		return
	animation_tree.set(ANIM_PARAM_DEAD_BLEND, 1.0)
