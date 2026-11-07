class_name BowShockwave
extends RefCounted
## The siege bow's shockwave: a ring around the front carrier that chips every living enemy
## inside it, shoves them away and leaves them reeling, and pops any plasma bolt. It buys the
## back carrier the time for a full draw at the enemies it has just pushed back.

## Enemies (layer 2) and enemy projectiles such as plasma bolts (layer 4).
const HIT_MASK := 10
const RADIUS := 4.5
const DAMAGE := 1
const KNOCKBACK_SPEED := 18.0
const KNOCKBACK_SEC := 0.25
## How long hit enemies stay reeling, long enough to step back and draw fully.
const STAGGER_SEC := 1.3
## Enemy body radius, so an enemy whose edge pokes into the ring still counts.
const ENEMY_MARGIN := 0.6
const MAX_QUERY_RESULTS := 64
const POP_SCENE := preload("res://src/vfx/small_explosion.tscn")


## Returns how many enemies the shockwave hit.
static func blast(world: World3D, origin: Vector3) -> int:
	var hit_count := 0
	for collider in _find_colliders(world, origin):
		if _try_pop_plasma(collider):
			continue
		if _try_hit_enemy(collider, origin):
			hit_count += 1
	return hit_count


static func _find_colliders(world: World3D, origin: Vector3) -> Array[Object]:
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS + ENEMY_MARGIN
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


static func _try_pop_plasma(collider: Object) -> bool:
	var area := collider as Area3D
	if area == null:
		return false
	var fireball := area.get_parent() as Fireball
	if fireball == null:
		return false
	var pop := POP_SCENE.instantiate() as Node3D
	fireball.get_tree().current_scene.add_child(pop)
	pop.global_position = fireball.global_position
	fireball.queue_free()
	return true


static func _try_hit_enemy(collider: Object, origin: Vector3) -> bool:
	var enemy := collider as EnemyLocal
	if enemy == null:
		return false
	if not enemy.is_alive():
		return false
	var offset := enemy.global_position - origin
	if Vector2(offset.x, offset.z).length() > RADIUS + ENEMY_MARGIN:
		return false
	# Damage comes from the ring's centre, so the hit reaction already pushes outwards.
	Health.apply_damage(enemy, DAMAGE, origin)
	if not enemy.is_alive():
		return true
	# The hit state starts its own small knockback; this replaces it with the shockwave's shove.
	enemy.begin_knockback(KNOCKBACK_SPEED, KNOCKBACK_SEC)
	enemy.hold_stagger(STAGGER_SEC)
	return true
