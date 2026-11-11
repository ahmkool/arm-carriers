class_name PulseVent
extends RefCounted
## The pulse rifle's vent blast: a cone in front of the muzzle that damages and shoves back
## every living enemy inside it and pops any plasma bolt. It also breaks enemy shields, the
## only thing that can, and then hits the enemy as usual. A `FlatShield` between the muzzle and an
## enemy protects it, so enemies behind one must be reached from an open side. Its size, damage
## and push all scale with the heat the front carrier dumps, from 0 (barely warm) to 1 (about to overheat).

## Enemies (layer 2) and enemy projectiles such as plasma bolts (layer 4).
const HIT_MASK := 10
const MIN_RANGE := 3.5
const MAX_RANGE := 8.0
const HALF_ANGLE_DEG := 42.0
const MIN_DAMAGE := 1
const MAX_DAMAGE := 5
const MIN_KNOCKBACK_SPEED := 9.0
const MAX_KNOCKBACK_SPEED := 22.0
const KNOCKBACK_SEC := 0.22
## Enemy body radius, so an enemy whose edge pokes into the cone still counts.
const ENEMY_MARGIN := 0.6
const MAX_QUERY_RESULTS := 64
## Height above an enemy's feet that the line of sight to it is checked at, roughly its chest.
const SIGHT_HEIGHT := 1.0
## Enemy bubbles the line of sight passes through before it can reach a flat shield.
const MAX_SIGHT_RAYS := 4
const POP_SCENE := preload("res://src/vfx/small_explosion.tscn")


static func get_range(heat: float) -> float:
	return lerpf(MIN_RANGE, MAX_RANGE, heat)


static func get_damage(heat: float) -> int:
	return roundi(lerpf(MIN_DAMAGE, MAX_DAMAGE, heat))


## Returns how many enemies the blast hit.
static func blast(world: World3D, origin: Vector3, forward: Vector3, heat: float) -> int:
	var reach := get_range(heat)
	var hit_count := 0
	for collider in _find_colliders(world, origin, reach):
		if _try_pop_plasma(collider, origin, forward, reach):
			continue
		if _try_hit_enemy(collider, origin, forward, reach, heat):
			hit_count += 1
	return hit_count


static func _find_colliders(world: World3D, origin: Vector3, reach: float) -> Array[Object]:
	var sphere := SphereShape3D.new()
	sphere.radius = reach + ENEMY_MARGIN
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, origin)
	query.collision_mask = HIT_MASK
	query.collide_with_areas = true
	var found: Array[Object] = []
	for result in world.direct_space_state.intersect_shape(query, MAX_QUERY_RESULTS):
		if found.has(result.collider):
			continue
		found.append(result.collider)
	return found


static func _try_pop_plasma(collider: Object, origin: Vector3, forward: Vector3, reach: float) -> bool:
	var area := collider as Area3D
	if area == null:
		return false
	var fireball := area.get_parent() as Fireball
	if fireball == null:
		return false
	if not is_in_cone(fireball.global_position, origin, forward, reach, 0.0):
		return true
	var pop := POP_SCENE.instantiate() as Node3D
	fireball.get_tree().current_scene.add_child(pop)
	pop.global_position = fireball.global_position
	fireball.queue_free()
	return true


static func _try_hit_enemy(collider: Object, origin: Vector3, forward: Vector3, reach: float, heat: float) -> bool:
	var enemy := collider as EnemyLocal
	if enemy == null:
		return false
	if not enemy.is_alive():
		return false
	if not is_in_cone(enemy.global_position, origin, forward, reach, ENEMY_MARGIN):
		return false
	if is_behind_flat_shield(enemy, origin):
		return false
	_try_break_shield(enemy)
	# Damage comes from the muzzle, so the hit reaction already pushes away from the rifle.
	Health.apply_damage(enemy, get_damage(heat), origin)
	if not enemy.is_alive():
		return true
	# The hit state starts its own small knockback; this replaces it with the vent's shove.
	enemy.begin_knockback(lerpf(MIN_KNOCKBACK_SPEED, MAX_KNOCKBACK_SPEED, heat), KNOCKBACK_SEC, true)
	return true


## Whether a flat shield stands between `origin` and `enemy`. Enemy bubbles along the way don't count.
static func is_behind_flat_shield(enemy: EnemyLocal, origin: Vector3) -> bool:
	var target := enemy.global_position + Vector3.UP * SIGHT_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(Vector3(origin.x, target.y, origin.z), target, BoltMirror.LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var space := enemy.get_world_3d().direct_space_state
	for attempt in MAX_SIGHT_RAYS:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return false
		if hit.collider.get_parent() is FlatShield:
			return true
		var excluded := query.exclude
		excluded.append(hit.rid)
		query.exclude = excluded
	return false


static func _try_break_shield(enemy: EnemyLocal) -> void:
	var shield := EnemyShield.find_on(enemy)
	if shield == null:
		return
	shield.shatter()


static func is_in_cone(point: Vector3, origin: Vector3, forward: Vector3, reach: float, margin: float) -> bool:
	var to_point := point - origin
	to_point.y = 0.0
	var distance := to_point.length()
	if distance > reach + margin:
		return false
	if distance <= margin:
		return true
	var flat_forward := Vector3(forward.x, 0.0, forward.z).normalized()
	# Widens the cone by the margin at this distance, so a body brushing its edge counts.
	var allowed := deg_to_rad(HALF_ANGLE_DEG) + atan2(margin, distance)
	return flat_forward.angle_to(to_point) <= allowed
