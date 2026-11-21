class_name MirrorSurface
extends Area3D
## The reflective pane of the carried Mirror weapon.
## Sits on `BoltMirror.LAYER` so map lasers raycast against it cleanly, and monitors enemy
## projectiles (`Fireball` areas on layer 4) to absorb them into the mirror pane.
## Both broad faces (±local X) reflect lasers and absorb projectiles according to the 3D tilt.

signal fireball_absorbed(point: Vector3, face_sign: float)
signal laser_reflected(point: Vector3)

## Layer 4 ("weapons"): Fireball / NinjaShuriken / LaserBolt Area3Ds live here.
const ENEMY_PROJECTILE_LAYER := 8
## Rays nearly parallel to the mirror pane (e.g. horizontal beam against a flat 90° mirror) graze past.
const GRAZE_DOT_THRESHOLD := 0.12


func _ready() -> void:
	collision_layer = BoltMirror.LAYER
	collision_mask = ENEMY_PROJECTILE_LAYER
	monitoring = true
	monitorable = true
	area_entered.connect(_on_area_entered)


## The broad-face normal opposing `incoming_dir`, so both sides of the mirror reflect cleanly.
func get_reflection_normal(incoming_dir: Vector3) -> Vector3:
	var normal := global_basis.x.normalized()
	if incoming_dir.length_squared() > 0.0001 and incoming_dir.dot(normal) > 0.0:
		normal = -normal
	return normal


## +1.0 when `incoming_dir` enters the +local X face, -1.0 when it enters the -local X face.
func get_entry_face_sign(incoming_dir: Vector3) -> float:
	var face_x := global_basis.x.normalized()
	if incoming_dir.dot(face_x) > 0.0:
		return -1.0
	return 1.0


## True when `incoming_dir` runs almost parallel to the glass face (grazing the edge).
func is_grazing(incoming_dir: Vector3) -> bool:
	if incoming_dir.length_squared() < 0.0001:
		return true
	var face_normal := global_basis.x.normalized()
	return absf(incoming_dir.normalized().dot(face_normal)) < GRAZE_DOT_THRESHOLD


func notify_laser_reflect(point: Vector3) -> void:
	laser_reflected.emit(point)


func _on_area_entered(area: Area3D) -> void:
	var fireball := area.get_parent() as Fireball
	if fireball == null:
		return
	if fireball.velocity.length_squared() < 0.0001:
		return
	var incoming := fireball.velocity.normalized()
	if is_grazing(incoming):
		return
	var hit_point := fireball.global_position
	var face_sign := get_entry_face_sign(incoming)
	if not fireball.absorb():
		return
	fireball_absorbed.emit(hit_point, face_sign)
