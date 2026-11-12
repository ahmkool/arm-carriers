extends GunshipState
## Flies round the arena to the side the behavior picked, along an arc at the hover distance, climbing a little
## mid-way and turning to face back across the arena. Hands back to hovering once there.

const ARRIVE_DISTANCE := 1.2

var _start_angle := 0.0
var _sweep := 0.0
var _seconds := 1.0
var _elapsed := 0.0
var _arc_radius := 1.0


func enter() -> void:
	super.enter()
	var behavior := gunship()
	var offset := enemy.global_position - behavior.arena_center
	_arc_radius = maxf(Vector2(offset.x, offset.z).length(), behavior.station_distance())
	_start_angle = AviatorGunshipBehavior.angle_of(offset)
	_sweep = wrapf(behavior.side_angle(behavior.side) - _start_angle, -PI, PI)
	_seconds = maxf(absf(_sweep) * _arc_radius / behavior.relocate_speed, 0.8)
	_elapsed = 0.0


func physics_update(delta: float) -> void:
	var behavior := gunship()
	_elapsed += delta
	var t := clampf(_elapsed / _seconds, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	var angle := _start_angle + _sweep * eased
	var radius := lerpf(_arc_radius, behavior.station_distance(), eased)
	var point := behavior.arena_center + Vector3(sin(angle), 0.0, cos(angle)) * radius
	point.y = behavior.altitude() + sin(t * PI) * behavior.relocate_lift
	_track(point, delta)
	face(behavior.arena_center - enemy.global_position, delta * 2.0)
	bank(delta)
	if not _is_done(t):
		return
	behavior.finish_relocation()
	enemy_state_machine.transition_to("hovering")


## Done once the arc is flown and the gunship has settled on its spot, or a moment after if it lags behind.
func _is_done(t: float) -> bool:
	if t < 1.0:
		return false
	if _elapsed > _seconds + 1.5:
		return true
	return enemy.global_position.distance_to(gunship().station_point(0.0)) <= ARRIVE_DISTANCE


## Follows the arc closely: the point moves, so steer on the position error with a generous cap.
func _track(point: Vector3, delta: float) -> void:
	var to_point := point - enemy.global_position
	var wanted := to_point / maxf(delta, 0.001)
	var cap := gunship().relocate_speed * 1.6
	var flat := Vector3(wanted.x, 0.0, wanted.z)
	if flat.length() > cap:
		flat = flat.normalized() * cap
	var w := 1.0 - exp(-ACCELERATION * 3.0 * delta)
	enemy.velocity.x = lerpf(enemy.velocity.x, flat.x, w)
	enemy.velocity.z = lerpf(enemy.velocity.z, flat.z, w)
	enemy.velocity.y = clampf(to_point.y * ALTITUDE_GAIN, -MAX_VERTICAL_SPEED, MAX_VERTICAL_SPEED)
