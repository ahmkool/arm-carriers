class_name GunshipRocket
extends Node3D
## A rocket from the gunship's wing pods. It arcs from the tube onto a spot on the floor that a red ring marks
## from the moment of launch, then explodes: carriers inside the ring take `damage`. Enemies are not hurt.
## A target over open air explodes at the target's height.

const FLOOR_MASK := 4
const EXPLOSION_SCENE := preload("res://src/vfx/explosion.tscn")

@export var blast_radius := 2.2
@export var damage := 3
## Peak height of the arc above the straight line from the tube to the landing spot.
@export var arc_height := 3.5

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _seconds := 1.0
var _elapsed := 0.0
var _launched := false

@onready var _ring: Node3D = $WarningRing
@onready var _ring_material: StandardMaterial3D = ($WarningRing/Edge as MeshInstance3D).get_active_material(0) as StandardMaterial3D


func launch(from: Vector3, target: Vector3, seconds: float) -> void:
	_from = from
	_to = _onto_floor(target)
	_seconds = maxf(seconds, 0.2)
	_elapsed = 0.0
	_launched = true
	global_position = from
	_ring.global_position = _to + Vector3.UP * 0.05
	_ring.scale = Vector3(blast_radius, 1.0, blast_radius)
	_ring.visible = true


func landing_point() -> Vector3:
	return _to


func _physics_process(delta: float) -> void:
	if not _launched:
		return
	_elapsed += delta
	var t := clampf(_elapsed / _seconds, 0.0, 1.0)
	var previous := global_position
	global_position = _point_at(t)
	_face(global_position - previous)
	_ring_material.albedo_color.a = lerpf(0.35, 0.9, t) * (0.8 + 0.2 * sin(_elapsed * 30.0))
	if t < 1.0:
		return
	_explode()


func _point_at(t: float) -> Vector3:
	return _from.lerp(_to, t) + Vector3.UP * arc_height * 4.0 * t * (1.0 - t)


## The rocket model points along +Z, so +Z follows the flight.
func _face(step: Vector3) -> void:
	if step.length_squared() < 0.000001:
		return
	var direction := step.normalized()
	if absf(direction.dot(Vector3.UP)) > 0.99:
		return
	global_basis = Basis.looking_at(-direction, Vector3.UP)


func _onto_floor(target: Vector3) -> Vector3:
	var from := target + Vector3.UP * 4.0
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 10.0, FLOOR_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return target
	return hit.position as Vector3


func _explode() -> void:
	_launched = false
	var scene_root := get_tree().current_scene
	_hurt_carriers(scene_root)
	var blast := EXPLOSION_SCENE.instantiate()
	blast.set("hurts_enemies", false)
	blast.set("damage_radius", blast_radius)
	scene_root.add_child(blast)
	blast.global_position = _to
	queue_free()


func _hurt_carriers(scene_root: Node) -> void:
	var players := scene_root.get_node_or_null(^"Players")
	if players == null:
		return
	for child in players.get_children():
		var player := child as PlayerLocal
		if player == null or player.is_dead:
			continue
		if not _in_blast(player):
			continue
		if Health.apply_damage(player, damage, _to):
			CameraFeedback.add_trauma_hurt()


## Flat distance, so a carrier's height doesn't matter, but not across floors far above or below.
func _in_blast(player: PlayerLocal) -> bool:
	var offset := player.global_position - _to
	if absf(offset.y) > 2.5:
		return false
	return Vector2(offset.x, offset.z).length() <= blast_radius
