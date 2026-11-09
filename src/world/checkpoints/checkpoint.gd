class_name Checkpoint
extends Node3D

@onready var position_direction_setter = $PositionDirectionSetter
@onready var position_shooter = $PositionShooter

## Physics layer 3 ("level"): floors and bridges.
const LEVEL_COLLISION_LAYER := 4
## Checkpoints can sit a few metres above the floor they spawn on.
const FLOOR_PROBE_UP := 1.5
const FLOOR_PROBE_DOWN := 12.0
const FLOOR_HEIGHT_TOLERANCE := 0.6

@export var checkpoint_id: String = ""
@export var order: int = 0
@export var is_carrying_weapon: bool = true
@export var events_completed: Array[LevelEvent]
@export var enemy_groups_reset: Array[EnemyGroup]
@export var enemy_groups_defeated: Array[EnemyGroup]
@export var areas_to_reactivate: Array[EventAreaTrigger]
@export var areas_already_activated: Array[EventAreaTrigger]

# Called when the node enters the scene tree for the first time.
func _ready():
	var manager := get_parent() as Node
	if manager != null and manager.has_method("register_checkpoint"):
		manager.call("register_checkpoint", self)

func get_save_id() -> String:
	if not checkpoint_id.is_empty():
		return checkpoint_id
	return name


func get_spawn_transform() -> Transform3D:
	if is_instance_valid(position_direction_setter) and position_direction_setter is Node3D:
		return (position_direction_setter as Node3D).global_transform
	return global_transform

func set_world_at_checkpoint_state():
	_clear_camera_focal_points()
	for event in events_completed:
		event._complete_event()
	for enemy_group in enemy_groups_defeated:
		enemy_group.mark_as_defeated()
	for enemy_group in enemy_groups_reset:
		enemy_group.reset()
	for area in areas_to_reactivate:
		area._reset()
	for area in areas_already_activated:
		area._mark_area_as_inactive()
	# Level pieces that always go back to their start on any respawn, such as SpikeTrap.
	get_tree().call_group(&"checkpoint_resettable", "reset_to_checkpoint")
	if not is_carrying_weapon:
		var players: Node = get_parent().get_parent().get_node("Players")
		if players != null:
			for player in players.get_children():
				var player_local: PlayerLocal = player as PlayerLocal
				if player_local != null:
					player_local.carrying_weapon_data.can_carry_status = CarryingWeaponData.CanCarryStatus.NO_WEAPON_AVAILABLE

func get_shooter_transform() -> Transform3D:
	if is_instance_valid(position_shooter) and position_shooter is Node3D:
		return (position_shooter as Node3D).global_transform
	return global_transform


## Where the direction setter stands when the level is played with a swapped-in weapon.
func get_weapon_spawn_transform(weapon_id: String) -> Transform3D:
	return _weapon_marker_transform(weapon_id, "PositionDirectionSetter", 0)


## Where the shooter stands when the level is played with a swapped-in weapon.
func get_weapon_shooter_transform(weapon_id: String) -> Transform3D:
	return _weapon_marker_transform(weapon_id, "PositionShooter", 1)


## Markers under WeaponSpawns/<weapon_id> win; otherwise the weapon's spawn offsets from here.
func _weapon_marker_transform(weapon_id: String, marker_name: String, offset_index: int) -> Transform3D:
	var marker := get_node_or_null("WeaponSpawns/%s/%s" % [weapon_id, marker_name]) as Node3D
	if marker != null:
		return marker.global_transform
	var offsets := _weapon_spawn_offsets(weapon_id)
	if offsets.is_empty():
		return global_transform
	return global_transform.translated_local(offsets[offset_index])


## [setter, shooter]. The catalog offsets when both carriers have floor there; otherwise the same
## gap front and back, centred, then moved back. "Floor" means ground at the height under this
## checkpoint's own setter marker, so a sunk bridge or a lower level doesn't count.
func _weapon_spawn_offsets(weapon_id: String) -> Array[Vector3]:
	var weapon := WeaponCatalog.find(weapon_id)
	if weapon.is_empty():
		return []
	var catalog: Array[Vector3] = [weapon["setter_offset"], weapon["shooter_offset"]]
	var reference: Variant = _floor_y_at(get_spawn_transform().origin)
	if reference == null:
		return catalog
	for candidate in _spawn_candidates(catalog):
		if _has_floor_under(candidate, reference):
			return candidate
	return catalog


func _spawn_candidates(catalog: Array[Vector3]) -> Array:
	var half_gap := catalog[0].distance_to(catalog[1]) * 0.5
	var in_line: Array[Vector3] = [Vector3(0.0, 0.0, -half_gap), Vector3(0.0, 0.0, half_gap)]
	var moved_back: Array[Vector3] = [Vector3.ZERO, Vector3(0.0, 0.0, half_gap * 2.0)]
	return [catalog, in_line, moved_back]


func _has_floor_under(offsets: Array[Vector3], reference_y: float) -> bool:
	for offset in offsets:
		var floor_y: Variant = _floor_y_at(global_transform * offset)
		if floor_y == null:
			return false
		if absf(floor_y - reference_y) > FLOOR_HEIGHT_TOLERANCE:
			return false
	return true


## Height of the level floor below the point, or null when there is none within reach.
func _floor_y_at(point: Vector3) -> Variant:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * FLOOR_PROBE_UP, point + Vector3.DOWN * FLOOR_PROBE_DOWN, LEVEL_COLLISION_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit["position"].y


func _trigger_checkpoint() -> void:
	var checkpoint_manager: CheckpointManager = get_parent() as CheckpointManager
	checkpoint_manager.set_current_checkpoint(self)


func _clear_camera_focal_points() -> void:
	var world := get_parent().get_parent() as WorldLocal
	if world == null:
		return
	var rig := world.get_node_or_null("CameraFollowRig") as CameraFollowRig
	if rig == null:
		return
	rig.clear_focal_points()
