class_name Kunai
extends Node3D
## One kunai thrown out of the shuriken's blade. Fast, so like the pulse bolt it casts a ray along
## each tick's path instead of using an overlap area. It flies through terrain, like the other
## carriers' shots, and stops at the first living enemy, or pops the first enemy fireball, it meets.
## The model points along +Z, so +Z follows the flight.

signal enemy_hit(enemy: EnemyLocal)

## Enemies (layer 2) and enemy projectiles such as fireballs (layer 4).
const HIT_MASK := 2 | 8
## Rays that keep finding non-targets, such as dead enemies, give up after this many.
const MAX_RAY_ATTEMPTS := 4
const SPARKS_SCENE := preload("res://src/vfx/saw_sparks.tscn")
const POP_SCENE := preload("res://src/vfx/small_explosion.tscn")
const HIT_SOUND := preload("res://assets/sounds/damage/161098__braqoon__arrow_damage.wav")
const MODEL := preload("res://assets/models/weapon/shuriken_launcher/kunai.glb")

var _direction := Vector3.FORWARD
var _speed := 0.0
var _range := 0.0
var _damage := 0
var _travelled := 0.0
var _is_spent := false


func _ready() -> void:
	add_child(MODEL.instantiate())


func launch(origin: Vector3, direction: Vector3, speed: float, flight_range: float, damage: int) -> void:
	global_position = origin
	_direction = direction.normalized()
	global_basis = Basis.looking_at(-_direction, Vector3.UP)
	_speed = speed
	_range = flight_range
	_damage = damage


func _physics_process(delta: float) -> void:
	if _is_spent:
		return
	var step := minf(_speed * delta, _range - _travelled)
	var from := global_position
	var hit := _find_hit(from, from + _direction * step)
	if not hit.is_empty():
		_resolve_hit(hit)
		return
	global_position = from + _direction * step
	_travelled += step
	if _travelled >= _range:
		_finish()


func _find_hit(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK)
	query.collide_with_areas = true
	var space := get_world_3d().direct_space_state
	for attempt in MAX_RAY_ATTEMPTS:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {}
		if _is_target(hit.collider):
			return hit
		var excluded := query.exclude
		excluded.append(hit.rid)
		query.exclude = excluded
	return {}


func _is_target(collider: Object) -> bool:
	if _as_fireball(collider) != null:
		return true
	var enemy := collider as EnemyLocal
	if enemy == null:
		return false
	return enemy.is_alive()


func _as_fireball(collider: Object) -> Fireball:
	var area := collider as Area3D
	if area == null:
		return null
	return area.get_parent() as Fireball


func _resolve_hit(hit: Dictionary) -> void:
	var hit_position: Vector3 = hit.position
	global_position = hit_position
	var fireball := _as_fireball(hit.collider)
	if fireball != null:
		_spawn_effect(POP_SCENE, fireball.global_position)
		fireball.queue_free()
		_finish()
		return
	var enemy := hit.collider as EnemyLocal
	# Damage comes from just behind the enemy, so knockback pushes along the flight.
	Health.apply_damage(enemy, _damage, enemy.global_position - _direction)
	enemy_hit.emit(enemy)
	ImpactFeedback.play_sfx(HIT_SOUND, hit_position, randf_range(1.3, 1.6), -8.0)
	var sparks := _spawn_effect(SPARKS_SCENE, hit_position) as GPUParticles3D
	sparks.amount_ratio = 0.35
	sparks.emitting = true
	_finish()


func _spawn_effect(scene: PackedScene, at_position: Vector3) -> Node3D:
	var effect := scene.instantiate() as Node3D
	get_tree().current_scene.add_child(effect)
	effect.global_position = at_position
	return effect


func _finish() -> void:
	if _is_spent:
		return
	_is_spent = true
	queue_free()
