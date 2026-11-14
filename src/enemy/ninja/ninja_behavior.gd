class_name NinjaBehavior
extends EnemyBehavior
## A ninja runs circles around the nearer carrier at a distance, stopping now and then to throw a
## shuriken (`ninja_throwing.gd`). It never closes in: it steers for a point a little further round
## a circle of `orbit_radius` about the target, so it backs off when the carriers walk at it and
## closes in when they walk away. It turns back the other way at random, and whenever the way round
## runs off the navmesh, such as at a roof's edge.
##
## Once per life it dodges the carriers' big shuriken: when one flies at it, it dashes to the side
## (`ninja_dodging.gd`), to whichever side keeps it on the navmesh.

## Distance it circles the target at, flat.
@export var orbit_radius := 7.0
## How far round the circle, ahead of where it is, it steers for. Bigger runs rounder and faster.
@export var orbit_step_degrees := 35.0
@export var flip_interval_min := 3.0
@export var flip_interval_max := 6.0
## Throws only at a target within this flat distance.
@export var throw_max_distance := 11.0
@export var first_throw_delay := 1.2
@export var throw_cooldown_min := 1.8
@export var throw_cooldown_max := 3.0
## A big shuriken this far off or nearer, flying at it, sets off the dodge.
@export var dodge_warning_distance := 5.0
## How far to the side of the shuriken's line counts as "at it": its blades plus the ninja's body.
@export var dodge_threat_width := 2.0
## How far the dodge carries it sideways.
@export var dodge_distance := 2.8

## A goal this far from the navmesh is off it.
const NAV_TOLERANCE := 1.0
## After turning back, it keeps the new way round at least this long, so it can't jitter at an edge.
const MIN_FLIP_GAP_SEC := 0.8

var has_dodged := false
var _orbit_sign := 1.0
var _flip_left := 0.0
var _since_flip := 0.0
var _throw_cooldown := 0.0
var _was_offensive := false
var _pending_dodge := Vector3.ZERO


func _ready() -> void:
	super()
	_orbit_sign = [-1.0, 1.0].pick_random()
	_flip_left = randf_range(flip_interval_min, flip_interval_max)


## The direction of the dodge to start, once; zero when there is none. Read by the Dodging state.
func take_dodge_direction() -> Vector3:
	var direction := _pending_dodge
	_pending_dodge = Vector3.ZERO
	return direction


func _think(delta: float) -> void:
	if enemy == null or _is_busy():
		return
	if not enemy.is_offensive:
		_was_offensive = false
		return
	_on_wake_up()
	_throw_cooldown = maxf(_throw_cooldown - delta, 0.0)
	_since_flip += delta
	if _try_dodge():
		return
	enemy.update_target_player()
	if not is_instance_valid(enemy.target_player):
		return
	var to_target := enemy.target_player.global_position - enemy.global_position
	to_target.y = 0.0
	if _try_throw(to_target):
		return
	_circle(delta, to_target)


func _is_busy() -> bool:
	var machine := enemy.enemy_state_machine
	if machine == null:
		return true
	if machine.is_in_state("dead"):
		return true
	if machine.is_in_state("throwing"):
		return true
	return machine.is_in_state("dodging")


func _on_wake_up() -> void:
	if _was_offensive:
		return
	_was_offensive = true
	_throw_cooldown = first_throw_delay


func _try_throw(to_target: Vector3) -> bool:
	if _throw_cooldown > 0.0:
		return false
	if to_target.length() > throw_max_distance:
		return false
	_throw_cooldown = randf_range(throw_cooldown_min, throw_cooldown_max)
	intent.face_direction = to_target
	intent.requested_locomotion = &"throwing"
	return true


func _circle(delta: float, to_target: Vector3) -> void:
	_flip_left -= delta
	if _flip_left <= 0.0:
		_flip()
	var goal := _orbit_goal()
	if not _is_on_navmesh(goal):
		_flip()
		goal = _orbit_goal()
	intent.move_direction = enemy.get_path_direction_to(goal)
	intent.face_direction = intent.move_direction
	if intent.move_direction.length_squared() < 0.0001:
		intent.face_direction = to_target


## A point on the circle about the target, a step further round from the ninja.
func _orbit_goal() -> Vector3:
	var target := enemy.target_player.global_position
	var from_target := enemy.global_position - target
	from_target.y = 0.0
	if from_target.length_squared() < 0.0001:
		from_target = Vector3.FORWARD
	var angle := deg_to_rad(orbit_step_degrees) * _orbit_sign
	var out := from_target.normalized().rotated(Vector3.UP, angle)
	return target + out * orbit_radius


func _flip() -> void:
	_flip_left = randf_range(flip_interval_min, flip_interval_max)
	if _since_flip < MIN_FLIP_GAP_SEC:
		return
	_since_flip = 0.0
	_orbit_sign = -_orbit_sign


func _try_dodge() -> bool:
	if has_dodged:
		return false
	var threat := _incoming_shuriken()
	if threat == null:
		return false
	var direction := _dodge_direction(threat)
	if direction.length_squared() < 0.0001:
		return false
	has_dodged = true
	_pending_dodge = direction
	intent.requested_locomotion = &"dodging"
	return true


## The nearest big shuriken flying at the ninja, within warning distance, or null.
func _incoming_shuriken() -> Shuriken:
	var nearest: Shuriken = null
	var nearest_distance := INF
	for node in get_tree().get_nodes_in_group(Shuriken.GROUP):
		var shuriken := node as Shuriken
		var distance := _approach_distance(shuriken)
		if distance < nearest_distance:
			nearest = shuriken
			nearest_distance = distance
	return nearest


## How far the shuriken has to fly to reach the ninja, or INF if it isn't coming at it.
func _approach_distance(shuriken: Shuriken) -> float:
	if shuriken == null or not shuriken.is_flying():
		return INF
	var offset := enemy.global_position - shuriken.global_position
	offset.y = 0.0
	var heading := shuriken.get_direction()
	var along := offset.dot(heading)
	if along < 0.0 or along > dodge_warning_distance:
		return INF
	var aside := (offset - heading * along).length()
	if aside > dodge_threat_width:
		return INF
	return along


## Sideways off the shuriken's line, to the side the ninja already leans to; the other side if that
## one leaves the navmesh; zero if neither is safe.
func _dodge_direction(shuriken: Shuriken) -> Vector3:
	var heading := shuriken.get_direction()
	var side := heading.cross(Vector3.UP).normalized()
	var offset := enemy.global_position - shuriken.global_position
	if offset.dot(side) < 0.0:
		side = -side
	if _is_on_navmesh(enemy.global_position + side * dodge_distance):
		return side
	if _is_on_navmesh(enemy.global_position - side * dodge_distance):
		return -side
	return Vector3.ZERO


func _is_on_navmesh(point: Vector3) -> bool:
	var map := enemy.navigation_agent.get_navigation_map()
	if not map.is_valid():
		return true
	var closest := NavigationServer3D.map_get_closest_point(map, point)
	return Vector2(closest.x - point.x, closest.z - point.z).length() <= NAV_TOLERANCE
