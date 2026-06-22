extends Node3D

const IMPACT_SCENE := preload("res://src/vfx/enemy/skeleton_boss/axe_slam_impact.tscn")
const FAR_IMPACT_SCENE := preload("res://src/vfx/enemy/skeleton_boss/axe_slam_impact_far.tscn")

const PICK_ATTEMPTS := 10
const INVALID_NAV_POINT := Vector3(INF, INF, INF)

@export var far_burst_count_min := 2
@export var far_burst_count_max := 3
@export var far_burst_min_radius := 4.0
@export var far_burst_max_radius := 10.0
@export var far_burst_delay_min := 0.15
@export var far_burst_delay_max := 0.45
@export var far_burst_max_snap_distance := 2.0


func instantiate_impact() -> void:
	_spawn_impact_at(global_position, IMPACT_SCENE)
	_spawn_far_burst()


func _spawn_far_burst() -> void:
	var boss := get_parent() as Node3D
	if boss == null:
		return
	var map_rid := _get_navigation_map_rid(boss)
	if map_rid == RID():
		return
	var origin := boss.global_position
	var count := randi_range(far_burst_count_min, far_burst_count_max)
	for _i in count:
		var point: Vector3 = _pick_nav_point_in_ring(origin, map_rid)
		if not point.is_finite():
			continue
		var delay := randf_range(far_burst_delay_min, far_burst_delay_max)
		_schedule_far_impact(point, delay)


func _get_navigation_map_rid(boss: Node3D) -> RID:
	var agent := boss.get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if agent == null:
		return RID()
	return agent.get_navigation_map()


func _pick_nav_point_in_ring(origin: Vector3, map_rid: RID) -> Vector3:
	for _attempt in PICK_ATTEMPTS:
		var point: Vector3 = _try_nav_point_in_ring(origin, map_rid)
		if point.is_finite():
			return point
	return INVALID_NAV_POINT


func _try_nav_point_in_ring(origin: Vector3, map_rid: RID) -> Vector3:
	var angle := randf() * TAU
	var distance := randf_range(far_burst_min_radius, far_burst_max_radius)
	var candidate := origin + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	var nav_point := NavigationServer3D.map_get_closest_point(map_rid, candidate)
	if nav_point.distance_to(candidate) > far_burst_max_snap_distance:
		return INVALID_NAV_POINT
	var flat_distance := Vector2(nav_point.x - origin.x, nav_point.z - origin.z).length()
	if flat_distance < far_burst_min_radius * 0.75:
		return INVALID_NAV_POINT
	return nav_point


func _schedule_far_impact(world_position: Vector3, delay: float) -> void:
	get_tree().create_timer(delay).timeout.connect(
		func() -> void: _spawn_impact_at(world_position, FAR_IMPACT_SCENE),
		CONNECT_ONE_SHOT
	)


func _spawn_impact_at(world_position: Vector3, scene: PackedScene) -> void:
	print("spawn_impact_at: ", world_position)
	var impact := scene.instantiate() as Node3D
	if impact == null:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		impact.queue_free()
		return
	scene_root.add_child(impact)
	impact.global_position = world_position
