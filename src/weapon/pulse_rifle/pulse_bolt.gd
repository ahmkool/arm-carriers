class_name PulseBolt
extends Node3D
## One pulse-rifle bolt. It is fast enough to skip past an enemy between physics ticks,
## so each tick casts a ray along its path instead of using an overlap area. It flies
## through terrain, like the bazooka's rockets, and stops at the first living enemy or
## plasma bolt it meets. Shields (`BoltMirror`) bounce it off like a mirror, so a shot banked off
## a flat shield can reach enemies hiding behind another. The origin is the bolt's head; the
## tracer trails behind it.

signal spent(hit_enemy: bool)
## Fired before `spent` when the bolt damages a living enemy, for weapons that track what they hit.
signal enemy_hit(enemy: EnemyLocal)

## Enemies (layer 2), enemy projectiles such as plasma bolts (layer 4) and shields (layer 6).
const HIT_MASK := 2 | 8 | BoltMirror.LAYER
## Rays that keep finding non-targets, such as dead enemies, give up after this many.
const MAX_RAY_ATTEMPTS := 4
const TRACER_LENGTH := 1.4
## Stops two facing mirrors from juggling a bolt for its whole range.
const MAX_BOUNCES := 8
## How far off the mirror a bounced bolt starts, so its next ray doesn't graze the same surface.
const BOUNCE_CLEARANCE := 0.02
const SPARKS_SCENE := preload("res://src/vfx/saw_sparks.tscn")
const POP_SCENE := preload("res://src/vfx/small_explosion.tscn")
const HIT_SOUND := preload("res://assets/sounds/damage/161098__braqoon__arrow_damage.wav")

@onready var _tracer: Node3D = $Tracer

var _direction := Vector3.FORWARD
var _speed := 0.0
var _range := 0.0
var _damage := 0
var _travelled := 0.0
## Distance since the muzzle or the last bounce, so the tracer regrows out of each mirror.
var _leg_travelled := 0.0
var _bounces := 0
## The mirror last bounced off, skipped by the next ray so the bolt can't strike it again at once.
var _last_mirror: RID
var _is_spent := false


func launch(origin: Vector3, direction: Vector3, speed: float, flight_range: float, damage: int) -> void:
	global_position = origin
	_set_direction(direction)
	_speed = speed
	_range = flight_range
	_damage = damage
	_update_tracer()


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
	_leg_travelled += step
	_last_mirror = RID()
	_update_tracer()
	if _travelled >= _range:
		_finish(false)


## Grows the tracer out of the muzzle instead of poking it back through the gun.
func _update_tracer() -> void:
	_tracer.scale.z = clampf(_leg_travelled / TRACER_LENGTH, 0.05, 1.0)


func _set_direction(direction: Vector3) -> void:
	# Points +Z along the flight, so the tracer, which extends along -Z, trails behind.
	global_basis = Basis.looking_at(-direction, Vector3.UP)
	_direction = direction


func _find_hit(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK)
	query.collide_with_areas = true
	if _last_mirror.is_valid():
		query.exclude = [_last_mirror]
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
	if collider is BoltMirror:
		return _can_bounce_off(collider)
	var enemy := collider as EnemyLocal
	if enemy == null:
		return false
	return enemy.is_alive()


func _can_bounce_off(mirror: BoltMirror) -> bool:
	return mirror.is_active() and _bounces < MAX_BOUNCES


func _as_fireball(collider: Object) -> Fireball:
	var area := collider as Area3D
	if area == null:
		return null
	return area.get_parent() as Fireball


func _resolve_hit(hit: Dictionary) -> void:
	var hit_position: Vector3 = hit.position
	if hit.collider is BoltMirror:
		_bounce(hit)
		return
	global_position = hit_position
	var fireball := _as_fireball(hit.collider)
	if fireball != null:
		_spawn_effect(POP_SCENE, fireball.global_position)
		fireball.queue_free()
		_finish(false)
		return
	var enemy := hit.collider as EnemyLocal
	# Damage comes from just behind the enemy, so knockback pushes along the flight.
	Health.apply_damage(enemy, _damage, enemy.global_position - _direction)
	enemy_hit.emit(enemy)
	ImpactFeedback.play_sfx(HIT_SOUND, hit_position, randf_range(1.2, 1.5), -10.0)
	_spawn_sparks(hit_position)
	_finish(true)


## Carries on from the mirror's surface in the mirrored direction, keeping the range left.
func _bounce(hit: Dictionary) -> void:
	var mirror := hit.collider as BoltMirror
	var hit_position: Vector3 = hit.position
	_travelled += global_position.distance_to(hit_position)
	_set_direction(BoltMirror.reflect(_direction, hit.normal))
	global_position = hit_position + _direction * BOUNCE_CLEARANCE
	_leg_travelled = 0.0
	_bounces += 1
	_last_mirror = hit.rid
	_update_tracer()
	mirror.deflect(hit_position)
	if _travelled >= _range:
		_finish(false)


func _spawn_sparks(at_position: Vector3) -> void:
	var sparks := _spawn_effect(SPARKS_SCENE, at_position) as GPUParticles3D
	sparks.amount_ratio = 0.4
	sparks.emitting = true


func _spawn_effect(scene: PackedScene, at_position: Vector3) -> Node3D:
	var effect := scene.instantiate() as Node3D
	get_tree().current_scene.add_child(effect)
	effect.global_position = at_position
	return effect


func _finish(hit_enemy: bool) -> void:
	if _is_spent:
		return
	_is_spent = true
	spent.emit(hit_enemy)
	queue_free()
