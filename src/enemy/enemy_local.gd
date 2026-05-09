class_name EnemyLocal
extends CharacterBody3D

@export var speed := 2.0
@export var is_offensive := true
const DEATH_FREE_DELAY_SECONDS := 10.0
const ANIM_PARAM_LOCOMOTION_BLEND := &"parameters/BlendIdleRun/blend_amount"
const ANIM_PARAM_DEAD_BLEND := &"parameters/DeadBlend/blend_amount"

var target_player: PlayerLocal
var is_dead := false

@onready var animation_tree: AnimationTree = $Skeleton_Warrior/AnimationTree
@onready var enemy_state_machine: EnemyStateMachine = $EnemyStateMachine
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var footsteps_particles: GPUParticles3D = $FootstepsParticles

func _ready() -> void:
	if animation_tree:
		animation_tree.active = true
		animation_tree.set(ANIM_PARAM_DEAD_BLEND, 0.0)
	if navigation_agent:
		navigation_agent.target_position = global_position
	if not is_offensive:
		var hit_box := get_node_or_null("HitBox") as Area3D
		if hit_box != null:
			hit_box.set_deferred("monitoring", false)
			hit_box.set_deferred("monitorable", false)
	_update_target_player()

func _process(_delta: float) -> void:
	if not is_offensive:
		return
	if not is_instance_valid(target_player):
		_update_target_player()

func _update_target_player() -> void:
	var players_node := get_node_or_null("../../Players")
	if players_node == null:
		target_player = null
		return

	var closest_player: PlayerLocal = null
	var closest_distance_sq := INF
	for child in players_node.get_children():
		var player := child as PlayerLocal
		if player == null:
			continue
		if player.is_dead:
			continue
		var distance_sq := global_position.distance_squared_to(player.global_position)
		if distance_sq < closest_distance_sq:
			closest_distance_sq = distance_sq
			closest_player = player
	target_player = closest_player

func get_target_direction() -> Vector3:
	if not is_offensive:
		return Vector3.ZERO
	if not is_instance_valid(target_player):
		_update_target_player()
	if is_instance_valid(target_player) and target_player.is_dead:
		_update_target_player()
	if not is_instance_valid(target_player):
		return Vector3.ZERO
	if navigation_agent == null:
		return _get_direct_target_direction()
	navigation_agent.target_position = target_player.global_position
	if navigation_agent.is_navigation_finished():
		return _get_direct_target_direction()
	var next_pos := navigation_agent.get_next_path_position()
	var direction := Vector3(next_pos.x - global_position.x, 0.0, next_pos.z - global_position.z)
	if direction.length_squared() > 0.0001:
		return direction.normalized()
	return _get_direct_target_direction()

func _get_direct_target_direction() -> Vector3:
	var to_target := target_player.global_position - global_position
	var direction := Vector3(to_target.x, 0.0, to_target.z)
	if direction.length_squared() > 0.0001:
		return direction.normalized()
	return Vector3.ZERO

func play_dead_animation() -> void:
	if not animation_tree:
		return
	animation_tree.set(ANIM_PARAM_DEAD_BLEND, 1.0)

func die() -> void:
	if is_dead:
		return
	is_dead = true
	velocity = Vector3.ZERO
	enemy_state_machine.transition_to("dead")


func _on_hit_box_body_entered(body):
	if not is_offensive:
		return
	if body is not PlayerLocal:
		return
	var player := body as PlayerLocal
	if player == null:
		return
	player.die()


func update_locomotion_blend() -> void:
	if not animation_tree or not animation_tree.active:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var blend := clampf(horizontal_speed / speed, 0.0, 1.0)
	animation_tree.set(ANIM_PARAM_LOCOMOTION_BLEND, blend)
