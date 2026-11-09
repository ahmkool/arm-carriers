class_name ForkMissile
extends BazookaBulletLocal
## The fork cannon's missile: a bazooka rocket that leaves the tube slow, speeds up, and steers
## towards the enemy the bolts locked on to. Without a lock, or once its target dies, it flies
## straight on like a bazooka rocket. It blows up on the same things a rocket does.

const LAUNCH_SPEED := 7.0
const TOP_SPEED := 17.0
const ACCELERATION := 14.0
## Radians per second. Tight enough to catch a circling mech, loose enough to miss one that
## dashes across its nose at close range.
const TURN_RATE := 3.2
## Steering starts after this long, so the missile first clears the barrel in a straight line.
const STEER_DELAY_SEC := 0.12
## A missile still chasing after this long gives up with the rocket's harmless pop.
const MAX_FLIGHT_SEC := 4.5
## Aims at the middle of the target, not its feet.
const TARGET_HEIGHT := 0.8

var target: EnemyLocal
var _flight_sec := 0.0


func launch(origin: Vector3, direction: Vector3, homing_target: EnemyLocal) -> void:
	global_position = origin
	target = homing_target
	velocity = direction.normalized() * LAUNCH_SPEED
	_face_velocity()


func has_target() -> bool:
	if not is_instance_valid(target):
		return false
	return target.is_alive()


func _physics_process(delta: float) -> void:
	if is_spent():
		return
	_flight_sec += delta
	if _flight_sec >= MAX_FLIGHT_SEC:
		_fizzle()
		return
	var speed := minf(TOP_SPEED, velocity.length() + ACCELERATION * delta)
	velocity = _steered_direction(delta) * speed
	_face_velocity()
	super(delta)


func _steered_direction(delta: float) -> Vector3:
	var heading := velocity.normalized()
	if _flight_sec < STEER_DELAY_SEC:
		return heading
	if not has_target():
		return heading
	var wanted := (target.global_position + Vector3.UP * TARGET_HEIGHT - global_position).normalized()
	var angle := heading.angle_to(wanted)
	if angle < 0.001:
		return wanted
	return heading.slerp(wanted, minf(1.0, TURN_RATE * delta / angle)).normalized()


## The rocket model points along +Z, so +Z follows the flight.
func _face_velocity() -> void:
	if velocity.length_squared() < 0.0001:
		return
	var direction: Vector3 = velocity.normalized()
	if absf(direction.dot(Vector3.UP)) > 0.99:
		return
	global_basis = Basis.looking_at(-direction, Vector3.UP)
