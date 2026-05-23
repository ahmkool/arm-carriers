class_name EnemyLocal
extends CharacterBody3D

@export var speed := 2.0

var _is_offensive := true

@export var is_offensive: bool = true:
	get:
		return _is_offensive
	set(value):
		if _is_offensive == value:
			return
		_is_offensive = value
		_sync_hit_box_to_offensive_state()

const DEATH_FREE_DELAY_SECONDS := 10.0
## Higher = faster turn toward a facing direction (roughly “how many times per second” to ease toward the target).
const ROTATION_SMOOTH_LAMBDA := 12.0
const ANIM_PARAM_LOCOMOTION_BLEND := &"parameters/BlendIdleRun/blend_amount"
const ANIM_PARAM_DEAD_BLEND := &"parameters/DeadBlend/blend_amount"
const ANIM_PARAM_CASTING_BLEND := &"parameters/ThrowBlend/blend_amount"
const ANIM_PARAM_CAST_ONESHOT := &"parameters/OneShot 2/request"
const ANIM_PARAM_CAST_ONESHOT_ACTIVE := &"parameters/OneShot 2/internal_active"
const ANIM_PARAM_SPAWN_ONESHOT := &"parameters/OneShotSpawn/request"
const ANIM_PARAM_SPAWN_ONESHOT_ACTIVE := &"parameters/OneShotSpawn/internal_active"

var target_player: PlayerLocal

@onready var enemy_state_machine: EnemyStateMachine = $EnemyStateMachine
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var footsteps_particles: GPUParticles3D = $FootstepsParticles

var behavior: EnemyBehavior
@onready var animation_tree: AnimationTree = _find_animation_tree()
@onready var animation_player: AnimationPlayer = _find_animation_player()

signal died

func _ready() -> void:
	behavior = _find_behavior()
	if animation_tree:
		animation_tree.active = true
		animation_tree.set(ANIM_PARAM_DEAD_BLEND, 0.0)
	if navigation_agent:
		navigation_agent.target_position = global_position
	_sync_hit_box_to_offensive_state()
	update_target_player()

func _process(_delta: float) -> void:
	if not is_offensive:
		return
	if not is_instance_valid(target_player):
		update_target_player()

func _get_players_node() -> Node:
	var n: Node = get_parent()
	while n != null:
		var players := n.get_node_or_null("Players")
		if players != null:
			return players
		n = n.get_parent()
	return null


func _find_behavior() -> EnemyBehavior:
	for child in get_children():
		if child is EnemyBehavior:
			return child as EnemyBehavior
	return null


func _find_animation_tree() -> AnimationTree:
	for node in find_children("*", "AnimationTree", true, false):
		return node as AnimationTree
	return null


func _find_animation_player() -> AnimationPlayer:
	for node in find_children("*", "AnimationPlayer", true, false):
		return node as AnimationPlayer
	return null


func get_move_direction() -> Vector3:
	if behavior == null:
		return Vector3.ZERO
	return behavior.get_move_direction()


func get_face_direction() -> Vector3:
	if behavior == null:
		return Vector3.ZERO
	return behavior.get_face_direction()


func smooth_rotate_toward(flat_direction: Vector3, delta: float) -> void:
	if flat_direction.length_squared() < 0.0001:
		return
	var target_basis := Basis.looking_at(flat_direction.normalized(), Vector3.UP)
	var w := 1.0 - exp(-ROTATION_SMOOTH_LAMBDA * delta)
	global_basis = global_basis.slerp(target_basis, w).orthonormalized()


func update_target_player() -> void:
	var players_node := _get_players_node()
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

func get_path_direction_to(target_global_position: Vector3) -> Vector3:
	if navigation_agent == null:
		return _get_direct_path_direction_to(target_global_position)
	navigation_agent.target_position = target_global_position
	if navigation_agent.is_navigation_finished():
		return _get_direct_path_direction_to(target_global_position)
	var next_pos := navigation_agent.get_next_path_position()
	var direction := Vector3(next_pos.x - global_position.x, 0.0, next_pos.z - global_position.z)
	if direction.length_squared() > 0.0001:
		return direction.normalized()
	return _get_direct_path_direction_to(target_global_position)


func get_flee_path_direction_from(threat_global_position: Vector3, retreat_distance: float) -> Vector3:
	var away := global_position - threat_global_position
	var flat := Vector3(away.x, 0.0, away.z)
	if flat.length_squared() < 0.0001:
		return Vector3.ZERO
	var flee_target := global_position + flat.normalized() * retreat_distance
	if navigation_agent != null:
		var map_rid := navigation_agent.get_navigation_map()
		flee_target = NavigationServer3D.map_get_closest_point(map_rid, flee_target)
	return get_path_direction_to(flee_target)


func _get_direct_path_direction_to(target_global_position: Vector3) -> Vector3:
	var to_target := target_global_position - global_position
	var direction := Vector3(to_target.x, 0.0, to_target.z)
	if direction.length_squared() > 0.0001:
		return direction.normalized()
	return Vector3.ZERO

func play_dead_animation() -> void:
	if animation_tree:
		animation_tree.set(ANIM_PARAM_DEAD_BLEND, 1.0)
		return
	if animation_player and animation_player.has_animation(&"dead"):
		animation_player.play(&"dead")


func play_cast_animation() -> void:
	if not animation_tree:
		return
	animation_tree.set(ANIM_PARAM_CAST_ONESHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func is_cast_animation_playing() -> bool:
	if not animation_tree:
		return false
	return animation_tree.get(ANIM_PARAM_CAST_ONESHOT_ACTIVE)


func play_spawn_animation() -> void:
	if not animation_tree:
		return
	animation_tree.set(ANIM_PARAM_SPAWN_ONESHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func is_spawn_animation_playing() -> bool:
	if not animation_tree:
		return false
	return animation_tree.get(ANIM_PARAM_SPAWN_ONESHOT_ACTIVE)


func is_alive() -> bool:
	if enemy_state_machine == null:
		return false
	return not enemy_state_machine.is_in_state("dead")

func die() -> void:
	if not is_alive():
		return
	velocity = Vector3.ZERO
	enemy_state_machine.transition_to("dead")

func _sync_hit_box_to_offensive_state() -> void:
	var hit_box := get_node_or_null("HitBox") as Area3D
	if hit_box == null:
		return
	if _is_offensive:
		hit_box.set_deferred("monitoring", true)
		hit_box.set_deferred("monitorable", true)
	else:
		hit_box.set_deferred("monitoring", false)
		hit_box.set_deferred("monitorable", false)


func _on_hit_box_body_entered(body):
	if not is_offensive:
		return
	if body is not PlayerLocal:
		return
	var player := body as PlayerLocal
	if player == null:
		return
	CameraFeedback.add_trauma_hurt()
	player.die()


func update_locomotion_blend() -> void:
	if enemy_state_machine != null and enemy_state_machine.is_in_state("casting"):
		return
	if enemy_state_machine != null and enemy_state_machine.is_in_state("spawning"):
		return
	if not animation_tree or not animation_tree.active:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var blend := clampf(horizontal_speed / speed, 0.0, 1.0)
	animation_tree.set(ANIM_PARAM_LOCOMOTION_BLEND, blend)
