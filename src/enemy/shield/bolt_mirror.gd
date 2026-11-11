class_name BoltMirror
extends Area3D
## A surface that pulse bolts bounce off like a mirror, used by enemy shields and flat shields.
## It sits alone on its own physics layer, so only bolts look for it: enemy shots, bodies and
## blasts pass straight through.

signal deflected(point: Vector3)

## Layer 6, "bolt_mirror".
const LAYER := 32


static func create(shape: Shape3D) -> BoltMirror:
	var mirror := BoltMirror.new()
	mirror.collision_layer = LAYER
	mirror.collision_mask = 0
	mirror.monitoring = false
	var collision := CollisionShape3D.new()
	collision.shape = shape
	mirror.add_child(collision)
	return mirror


## The direction a bolt flying along `direction` leaves in after striking a surface with `normal`.
## The normal is kept level, so a bolt glancing off the top of a bubble stays at carry height.
static func reflect(direction: Vector3, normal: Vector3) -> Vector3:
	var flat := Vector3(normal.x, 0.0, normal.z)
	if flat.length_squared() < 0.0001:
		return direction
	return direction.bounce(flat.normalized()).normalized()


func is_active() -> bool:
	return collision_layer != 0


## Stops bouncing bolts, for a shield that has broken or dropped.
func deactivate() -> void:
	collision_layer = 0


## Called by the bolt that bounced off at `point`, so the owner can flash and ping.
func deflect(point: Vector3) -> void:
	deflected.emit(point)
