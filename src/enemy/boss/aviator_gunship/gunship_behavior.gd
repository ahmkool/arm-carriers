class_name AviatorGunshipBehavior
extends EnemyBehavior
## The aviator's gunship: hovers off one edge of a square arena, facing across it, and drifts along that edge to
## stay level with the carriers. From there it fires gatling bursts, rocket salvos and its nose laser, which sweeps
## straight across the arena while the gunship slides slowly towards the carriers. Every `side_seconds_min` to
## `side_seconds_max` it flies round the arena to another edge (north, south, east or west).
## Below half health it enrages: shorter gaps between moves and a laser that tracks faster.
##
## The states in this folder do the flying; this node decides what happens next and answers where the gunship
## should be. Sides are numbered by `SIDES`.

const MOVE_GUNS := &"guns"
const MOVE_ROCKETS := &"rockets"
const MOVE_LASER := &"laser"
## Outward normals of the arena's edges, in world space. The gunship hovers past the edge, facing back across.
const SIDES: Array[Vector3] = [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
const SIDE_NAMES: Array[String] = ["north", "east", "south", "west"]
const FLOOR_MASK := 4

@export_group("Arena")
## Centre of the arena's floor, flat. Its height is found with a ray when the fight starts.
@export var arena_center := Vector3.ZERO
## Half the arena's width, from the centre to an edge.
@export var arena_half_extent := 10.5
## How far past the edge the gunship hovers, measured to its centre.
@export var standoff := 5.5
## The standoff on the camera's side (south, +z). The camera sits south looking north, so a gunship as far out
## there as elsewhere ends up under the boss health bar at the bottom of the screen.
@export var camera_side_standoff := 3.5
## How far behind the hull the camera's focal point sits, so the whole craft fits on screen. On the camera's
## side the camera looks down steeply onto it, so the point goes further out to slide the view south.
@export var camera_anchor_distance := 5.0
@export var camera_side_anchor_distance := 10.0
## Height of the gunship's origin (and its laser) above the arena floor. The beam must cross the carriers' bodies.
@export var hover_height := 1.0
## The side it holds when the fight starts (index into SIDES: 0 north, 1 east, 2 south, 3 west).
@export_range(0, 3) var first_side := 0

@export_group("Flight")
## Drift speed along its edge while keeping level with the carriers.
@export var strafe_speed := 3.2
## How far from the edge's ends it stays, so it never drifts past a corner.
@export var strafe_margin := 2.0
@export var side_seconds_min := 10.0
@export var side_seconds_max := 20.0
## Speed along the arc while flying round to another side.
@export var relocate_speed := 11.0
## How high it climbs mid-arc, for a readable swoop.
@export var relocate_lift := 2.5
@export var bob_amplitude := 0.2
@export var bob_speed := 1.6

@export_group("Moves")
@export var first_move_delay := 2.0
@export var gap_between_moves := 1.4
@export var enraged_gap_between_moves := 0.9
@export var guns_cooldown := 2.5
@export var rockets_cooldown := 6.0
@export var enraged_rockets_cooldown := 4.5
@export var laser_cooldown := 10.0
@export var enraged_laser_cooldown := 7.0
## Delay before the first laser after arriving on a side, so each side opens with it soon.
@export var laser_after_arrival := 2.5
## How fast the gunship slides along its edge towards the carriers while the laser fires.
@export var laser_track_speed := 1.5
@export var enraged_laser_track_speed := 2.4

## The side being held, or flown to while relocating.
var side := 0
var _side_time_left := 0.0
var _gap_remaining := 0.0
var _guns_remaining := 0.0
var _rockets_remaining := 0.0
var _laser_remaining := 0.0
var _was_offensive := false
var _bob_time := 0.0
var _floor_y := 0.0
var _has_floor_y := false
var _phase_controller: BossPhaseController


func _ready() -> void:
	super._ready()
	side = first_side
	_phase_controller = BossPhaseController.from_enemy(enemy)


func is_enraged() -> bool:
	if _phase_controller == null:
		return false
	return _phase_controller.is_phase_at_least(2)


# ---- Where the gunship should be: read by the states. ----

func side_normal() -> Vector3:
	return SIDES[side]


## Along the held edge, left to right as seen from the arena.
func lateral_axis() -> Vector3:
	var n := side_normal()
	return Vector3(-n.z, 0.0, n.x)


## The way the gunship faces while on its side: back across the arena. The laser fires along it.
func facing() -> Vector3:
	return -side_normal()


func station_distance() -> float:
	var out := camera_side_standoff if side_normal().z > 0.5 else standoff
	return arena_half_extent + out


func station_point(lateral: float) -> Vector3:
	var flat := arena_center + side_normal() * station_distance() + lateral_axis() * lateral
	return Vector3(flat.x, altitude(), flat.z)


func altitude() -> float:
	return _get_floor_y() + hover_height + sin(_bob_time * bob_speed) * bob_amplitude


## The carriers' middle, measured along the held edge and kept off its ends.
func players_lateral() -> float:
	var limit := arena_half_extent - strafe_margin
	var centre: Variant = _players_centre()
	if centre == null:
		return 0.0
	return clampf(((centre as Vector3) - arena_center).dot(lateral_axis()), -limit, limit)


func current_lateral() -> float:
	return (enemy.global_position - arena_center).dot(lateral_axis())


func laser_slide_speed() -> float:
	return enraged_laser_track_speed if is_enraged() else laser_track_speed


## Angle round the arena's centre: 0 is south, PI/2 east.
static func angle_of(offset: Vector3) -> float:
	return atan2(offset.x, offset.z)


func side_angle(index: int) -> float:
	return angle_of(SIDES[index])


## Called by the relocating state once it reaches the new side.
func finish_relocation() -> void:
	_side_time_left = randf_range(side_seconds_min, side_seconds_max)
	_laser_remaining = minf(_laser_remaining, laser_after_arrival)
	_gap_remaining = maxf(_gap_remaining, 0.8)


# ---- Decisions. ----

func _think(delta: float) -> void:
	if enemy == null:
		return
	_bob_time += delta
	_place_camera_anchor()
	if not enemy.is_offensive:
		_was_offensive = false
		return
	_on_wake_up()
	# Timers run during moves and flights too, so cooldowns and side stints are measured in real time.
	_tick_timers(delta)
	if _is_busy():
		return
	enemy.update_target_player()
	if not _has_valid_target():
		return
	if _side_time_left <= 0.0:
		_start_relocation()
		return
	var move := _pick_move()
	if move.is_empty():
		return
	_start_move(move)


func _is_busy() -> bool:
	var machine := enemy.enemy_state_machine
	if machine == null:
		return true
	return machine.is_in_state("dead") or machine.is_in_state("attacking") or machine.is_in_state("relocating")


func _on_wake_up() -> void:
	if _was_offensive:
		return
	_was_offensive = true
	_side_time_left = randf_range(side_seconds_min, side_seconds_max)
	_gap_remaining = first_move_delay
	_laser_remaining = laser_after_arrival + first_move_delay
	_rockets_remaining = 3.0
	_guns_remaining = 0.0
	_frame_with_camera()


func _tick_timers(delta: float) -> void:
	_side_time_left -= delta
	_gap_remaining = maxf(_gap_remaining - delta, 0.0)
	_guns_remaining = maxf(_guns_remaining - delta, 0.0)
	_rockets_remaining = maxf(_rockets_remaining - delta, 0.0)
	_laser_remaining = maxf(_laser_remaining - delta, 0.0)


func _has_valid_target() -> bool:
	if not is_instance_valid(enemy.target_player):
		return false
	return not enemy.target_player.is_dead


func _pick_move() -> StringName:
	if _gap_remaining > 0.0:
		return &""
	if _laser_remaining <= 0.0:
		return MOVE_LASER
	if _rockets_remaining <= 0.0:
		return MOVE_ROCKETS
	if _guns_remaining <= 0.0:
		return MOVE_GUNS
	return &""


func _start_move(move: StringName) -> void:
	intent.requested_attack = move
	intent.requested_locomotion = &"attacking"
	_gap_remaining = enraged_gap_between_moves if is_enraged() else gap_between_moves
	match move:
		MOVE_GUNS:
			_guns_remaining = guns_cooldown
		MOVE_ROCKETS:
			_rockets_remaining = enraged_rockets_cooldown if is_enraged() else rockets_cooldown
		MOVE_LASER:
			_laser_remaining = enraged_laser_cooldown if is_enraged() else laser_cooldown


## Picks another side at random and hands over to the relocating state, which flies the arc.
func _start_relocation() -> void:
	var others: Array[int] = []
	for index in SIDES.size():
		if index != side:
			others.append(index)
	side = others.pick_random()
	intent.requested_locomotion = &"relocating"


# ---- Helpers. ----

func _get_floor_y() -> float:
	if _has_floor_y:
		return _floor_y
	if not enemy.is_inside_tree():
		return arena_center.y
	var from := arena_center + Vector3.UP * 20.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 60.0, FLOOR_MASK)
	var hit := enemy.get_world_3d().direct_space_state.intersect_ray(query)
	_has_floor_y = true
	_floor_y = arena_center.y if hit.is_empty() else (hit.position as Vector3).y
	return _floor_y


func _players_centre() -> Variant:
	var players_node := enemy._get_players_node()
	if players_node == null:
		return null
	var sum := Vector3.ZERO
	var count := 0
	for child in players_node.get_children():
		var player := child as PlayerLocal
		if player == null or player.is_dead:
			continue
		sum += player.global_position
		count += 1
	if count == 0:
		return null
	return sum / count


## The anchor rides behind the hull (local +z, away from the arena), further out on the camera's side.
func _place_camera_anchor() -> void:
	var anchor := enemy.get_node_or_null(^"CameraAnchor") as Node3D
	if anchor == null:
		return
	var on_camera_side := enemy.global_basis.z.z > 0.5
	anchor.position = Vector3(0.0, 0.0, camera_side_anchor_distance if on_camera_side else camera_anchor_distance)


## The gunship hovers off the deck, out of walking reach, so the camera keeps it in frame for the whole fight.
## It frames a marker behind the hull, so the whole craft fits and not just its middle.
func _frame_with_camera() -> void:
	var rig := get_tree().current_scene.get_node_or_null(^"CameraFollowRig") as CameraFollowRig
	if rig == null:
		return
	var anchor := enemy.get_node_or_null(^"CameraAnchor") as Node3D
	rig.add_focal_point(anchor if anchor != null else enemy)
