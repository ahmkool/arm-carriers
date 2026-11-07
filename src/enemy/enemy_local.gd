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
@export var hitbox_damage: int = 1

const BODY_HIT_SOUND := preload("res://assets/sounds/punch/Punch 3_1.wav")
const DAMAGE_VFX_SCENE := preload("res://src/vfx/enemy_damage.tscn")
## How far off the navmesh a knockback step may land. The navmesh is inset from ledges,
## so a small margin lets enemies near its edge move without being pushed off a drop.
const KNOCKBACK_NAV_TOLERANCE := 0.25
## How far the end of a path may stop short of the target, flat, before the target counts as unreachable.
## Generous, because the navmesh stops about half a metre short of every edge.
const UNREACHABLE_TARGET_MARGIN := 1.5
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
const ANIM_PARAM_HIT_ONESHOT := &"parameters/OneShot/request"

var target_player: PlayerLocal
var _resume_state_after_hit := &"idle"

@onready var enemy_state_machine: EnemyStateMachine = $EnemyStateMachine
@onready var health: Health = $Health
@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D
@onready var footsteps_particles: GPUParticles3D = $FootstepsParticles

var behavior: EnemyBehavior
@onready var animation_tree: AnimationTree = _find_animation_tree()
@onready var animation_player: AnimationPlayer = _find_animation_player()

var _hit_flash: HitFlash3D
var _damage_source_position := Vector3.ZERO
var _has_damage_source_position := false
var _knockback_velocity := Vector3.ZERO
var _knockback_duration := 0.0
var _knockback_time_remaining := 0.0

signal died

func _ready() -> void:
	_bind_health()
	_hit_flash = _get_or_create_hit_flash()
	behavior = _find_behavior()
	if animation_tree:
		animation_tree.active = true
		animation_tree.set(ANIM_PARAM_DEAD_BLEND, 0.0)
	if navigation_agent:
		navigation_agent.target_position = global_position
	_sync_hit_box_to_offensive_state()
	update_target_player()


func _bind_health() -> void:
	if health == null:
		return
	health.damaged.connect(_on_health_damaged)
	health.died.connect(_on_health_died)


func _on_health_damaged(_amount: int, remaining: int, source_position: Vector3) -> void:
	if remaining <= 0:
		return
	if not is_alive():
		return
	if enemy_state_machine != null and enemy_state_machine.is_in_state("spawning"):
		return
	_store_damage_source_position(source_position)
	if _hit_flash == null:
		_hit_flash = _get_or_create_hit_flash()
	_hit_flash.trigger()
	spawn_damage_vfx()
	_request_taking_damage_state()


func _on_health_died(source_position: Vector3 = Vector3.ZERO) -> void:
	die(source_position)


func _request_taking_damage_state() -> void:
	if enemy_state_machine == null:
		return
	if enemy_state_machine.is_in_state("dead"):
		return
	var hit_state := _get_taking_damage_state_name()
	if hit_state.is_empty():
		return
	if _is_in_taking_damage_state():
		var current := enemy_state_machine.current_state
		if current != null and current.has_method("refresh_hit"):
			current.call("refresh_hit")
		return
	if enemy_state_machine.current_state != null:
		var prior_state := enemy_state_machine.current_state.name.to_lower()
		if _can_resume_after_hit(prior_state):
			_resume_state_after_hit = StringName(prior_state)
	enemy_state_machine.transition_to(hit_state)


func _can_resume_after_hit(state_name: String) -> bool:
	if state_name == "dead":
		return false
	if state_name == "spawning":
		return false
	if state_name == "takingdamage":
		return false
	if state_name == "takingdamageflying":
		return false
	if state_name == "attacking":
		return false
	return true


func _get_taking_damage_state_name() -> String:
	if enemy_state_machine.has_state("takingdamage"):
		return "takingdamage"
	if enemy_state_machine.has_state("takingdamageflying"):
		return "takingdamageflying"
	return ""


func _is_in_taking_damage_state() -> bool:
	if enemy_state_machine == null:
		return false
	return enemy_state_machine.is_in_state("takingdamage") \
		or enemy_state_machine.is_in_state("takingdamageflying")


func resume_state_after_hit() -> void:
	if enemy_state_machine == null:
		return
	if enemy_state_machine.has_state("flyingidle"):
		_resume_flying_after_hit()
		return
	_resume_ground_after_hit()


func _resume_flying_after_hit() -> void:
	if get_move_direction().length_squared() > 0.0001:
		enemy_state_machine.transition_to("flyingmoving")
		return
	enemy_state_machine.transition_to("flyingidle")


func _resume_ground_after_hit() -> void:
	if not is_on_floor():
		enemy_state_machine.transition_to("falling")
		return
	var resume := String(_resume_state_after_hit)
	if resume.is_empty() or not enemy_state_machine.has_state(resume):
		_resolve_ground_locomotion_after_hit()
		return
	if resume == "running" and get_move_direction().length_squared() < 0.0001:
		enemy_state_machine.transition_to("idle")
		return
	enemy_state_machine.transition_to(resume)


func _resolve_ground_locomotion_after_hit() -> void:
	if not is_on_floor():
		enemy_state_machine.transition_to("falling")
		return
	if get_move_direction().length_squared() > 0.0001:
		enemy_state_machine.transition_to("running")
		return
	enemy_state_machine.transition_to("idle")


func play_hit_animation() -> void:
	if animation_tree != null and animation_tree.active:
		animation_tree.set(ANIM_PARAM_HIT_ONESHOT, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		return
	_play_hit_animation_fallback()


func _play_hit_animation_fallback() -> void:
	if animation_player == null:
		return
	var candidates: Array[StringName] = [
		&"skeleton_warrior/Hit_A",
		&"animations/Hit_A",
		&"Hit_A",
	]
	for anim_name in candidates:
		if animation_player.has_animation(anim_name):
			animation_player.play(anim_name)
			return


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
	var current_basis := global_basis.orthonormalized()
	var target_basis := Basis.looking_at(flat_direction.normalized(), Vector3.UP)
	var w := 1.0 - exp(-ROTATION_SMOOTH_LAMBDA * delta)
	global_basis = current_basis.slerp(target_basis, w)


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
	var next_pos := _next_path_point_ahead()
	var finished := navigation_agent.is_navigation_finished() or _is_at_path_end()
	if finished and not _path_reaches(target_global_position):
		return Vector3.ZERO
	if finished:
		return _get_direct_path_direction_to(target_global_position)
	var direction := Vector3(next_pos.x - global_position.x, 0.0, next_pos.z - global_position.z)
	if direction.length_squared() > 0.0001:
		return direction.normalized()
	return _get_direct_path_direction_to(target_global_position)


## False when the path ends well short of the target: the target is somewhere the navmesh doesn't reach, such as a
## moving platform or across a gap. The enemy then waits at the end of its path instead of walking off the edge.
func _path_reaches(target_global_position: Vector3) -> bool:
	var path := navigation_agent.get_current_navigation_path()
	if path.is_empty():
		return true
	var end := path[path.size() - 1]
	return Vector2(end.x - target_global_position.x, end.z - target_global_position.z).length() <= UNREACHABLE_TARGET_MARGIN


## The agent's own "finished" is measured in 3D, so with the navmesh above the floor it may never come.
func _is_at_path_end() -> bool:
	var path := navigation_agent.get_current_navigation_path()
	if path.is_empty():
		return false
	var end := path[path.size() - 1]
	return Vector2(end.x - global_position.x, end.z - global_position.z).length() <= navigation_agent.target_desired_distance


## The agent only moves past a path point once it is within path_desired_distance of it in 3D. The navmesh is baked
## about 0.5 m above the floor, so an enemy whose feet sit a little lower never reaches its first point (its own spot)
## and steers at random, straight into holes. This skips points that are already reached when measured flat.
func _next_path_point_ahead() -> Vector3:
	var next_pos := navigation_agent.get_next_path_position()
	var path := navigation_agent.get_current_navigation_path()
	for i in range(navigation_agent.get_current_navigation_path_index(), path.size()):
		var point := path[i]
		if Vector2(point.x - global_position.x, point.z - global_position.z).length() > navigation_agent.path_desired_distance:
			return point
	return next_pos


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

func die(damage_source_position: Variant = null) -> void:
	if not is_alive():
		return
	_store_damage_source_position(damage_source_position)
	if _hit_flash == null:
		_hit_flash = _get_or_create_hit_flash()
	_hit_flash.trigger()
	velocity = Vector3.ZERO
	enemy_state_machine.transition_to("dead")


func spawn_damage_vfx() -> void:
	var world := get_tree().current_scene
	if world == null:
		return
	var fx := DAMAGE_VFX_SCENE.instantiate()
	if has_damage_source_position():
		fx.set_damage_source(get_damage_source_position())
	world.add_child(fx)
	fx.global_position = global_position


## Stretches the current hit reaction to `seconds`. Call it right after damaging the enemy.
func hold_stagger(seconds: float) -> void:
	if not _is_in_taking_damage_state():
		return
	var current := enemy_state_machine.current_state
	if not current.has_method("hold_hit"):
		return
	current.call("hold_hit", seconds)


func begin_knockback(knockback_speed: float, duration: float) -> void:
	_knockback_time_remaining = 0.0
	if knockback_speed <= 0.0 or duration <= 0.0:
		return
	var direction := _get_knockback_direction()
	if direction.length_squared() < 0.0001:
		return
	_knockback_velocity = direction * knockback_speed
	_knockback_duration = duration
	_knockback_time_remaining = duration


## Sets horizontal velocity for this physics tick, easing out to zero over the knockback.
func apply_knockback(delta: float, keep_on_navmesh: bool) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _knockback_time_remaining <= 0.0:
		return
	var step_velocity := _knockback_velocity * (_knockback_time_remaining / _knockback_duration)
	_knockback_time_remaining = maxf(0.0, _knockback_time_remaining - delta)
	if keep_on_navmesh and not _is_on_navmesh(global_position + step_velocity * delta):
		_knockback_time_remaining = 0.0
		return
	velocity.x = step_velocity.x
	velocity.z = step_velocity.z


func _get_knockback_direction() -> Vector3:
	if not _has_damage_source_position:
		return Vector3.ZERO
	var away := global_position - _damage_source_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		return Vector3.ZERO
	return away.normalized()


## Stops ground enemies leaving walkable space: one stranded off a ledge would stay alive
## forever and block survival groups from completing.
func _is_on_navmesh(world_position: Vector3) -> bool:
	if navigation_agent == null:
		return false
	var map_rid := navigation_agent.get_navigation_map()
	if not map_rid.is_valid():
		return false
	var closest := NavigationServer3D.map_get_closest_point(map_rid, world_position)
	var flat_offset := Vector2(closest.x - world_position.x, closest.z - world_position.z)
	return flat_offset.length() <= KNOCKBACK_NAV_TOLERANCE


func has_damage_source_position() -> bool:
	return _has_damage_source_position


func get_damage_source_position() -> Vector3:
	return _damage_source_position


func _store_damage_source_position(damage_source_position: Variant) -> void:
	_has_damage_source_position = damage_source_position is Vector3
	if not _has_damage_source_position:
		return
	_damage_source_position = damage_source_position as Vector3


func _get_or_create_hit_flash() -> HitFlash3D:
	var existing := get_node_or_null("HitFlash3D")
	if existing is HitFlash3D:
		return existing as HitFlash3D
	var flash := HitFlash3D.new()
	flash.name = "HitFlash3D"
	add_child(flash)
	return flash

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
	if not Health.apply_damage(player, hitbox_damage, global_position):
		return
	CameraFeedback.add_trauma_hurt()
	_play_body_hit_sfx()


func _play_body_hit_sfx() -> void:
	var sfx := AudioStreamPlayer3D.new()
	add_child(sfx)
	sfx.global_position = global_position
	sfx.bus = "SFX"
	sfx.stream = BODY_HIT_SOUND
	sfx.finished.connect(sfx.queue_free, CONNECT_ONE_SHOT)
	sfx.play()


func update_locomotion_blend() -> void:
	if _is_in_taking_damage_state():
		return
	if enemy_state_machine != null and enemy_state_machine.is_in_state("casting"):
		return
	if enemy_state_machine != null and enemy_state_machine.is_in_state("attacking"):
		return
	if enemy_state_machine != null and enemy_state_machine.is_in_state("spawning"):
		return
	if not animation_tree or not animation_tree.active:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var blend := clampf(horizontal_speed / speed, 0.0, 1.0)
	animation_tree.set(ANIM_PARAM_LOCOMOTION_BLEND, blend)

func set_weapon_hitbox_monitoring(monitoring: bool) -> void:
	var hit_box := get_node_or_null("Skeleton_Golem/Rig_Large/Skeleton3D/BoneAttachment3D/HitBox") as Area3D
	if hit_box == null:
		return
	print("Setting weapon hitbox monitoring to ", monitoring)
	hit_box.set_deferred("monitoring", monitoring)
	hit_box.set_deferred("monitorable", monitoring)
