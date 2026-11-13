extends Node3D

## Matches `Hitbox/CollisionShape3D` sphere radius when synced in `_ready`.
@export var damage_radius: float = 3.5
@export var damage: int = 9999
## Off for enemy grenades: they hurt the carriers themselves and use this only for the blast's look and sound.
@export var hurts_enemies := true
## Level geometry between the blast and an enemy shields it: a bomb striking a wall's face doesn't reach the guards
## standing on top of it.
@export var blocked_by_level := true

const LEVEL_COLLISION_MASK := 4
## Where the line of sight aims on an enemy, above its feet.
const ENEMY_AIM_HEIGHT := 1.0
## Blasts sit on the surface they struck, so a sight line can graze that surface right at the blast; a hit this
## close to the blast doesn't count as cover.
const COVER_TOLERANCE := 0.2

@onready var debris = $Debris
@onready var fire = $Fire
@onready var smoke = $Smoke
@onready var hitbox: Area3D = $Hitbox
@onready var _sfx: AudioStreamPlayer3D = $AudioStreamPlayer3D

const PITCH_MIN := 0.88
const PITCH_MAX := 1.12
const VOLUME_MIN_DB := -3.0
const VOLUME_MAX_DB := 0.0


func _ready() -> void:
	ImpactFeedback.play_explosion()
	# _randomize_explosion_sfx()
	debris.emitting = true
	fire.emitting = true
	smoke.emitting = true
	_sync_hitbox_sphere_radius()
	call_deferred("_hurt_initial_overlaps")
	get_tree().create_timer(0.2).timeout.connect(_queue_free_hitbox)
	await get_tree().create_timer(2.0).timeout
	queue_free()


func _randomize_explosion_sfx() -> void:
	_sfx.pitch_scale = randf_range(PITCH_MIN, PITCH_MAX)
	_sfx.volume_db = randf_range(VOLUME_MIN_DB, VOLUME_MAX_DB)
	_sfx.play()


func _sync_hitbox_sphere_radius() -> void:
	var cs := hitbox.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if cs == null or cs.shape == null:
		return
	var sphere := cs.shape as SphereShape3D
	if sphere != null:
		sphere.radius = damage_radius


func _queue_free_hitbox() -> void:
	if is_instance_valid(hitbox):
		hitbox.queue_free()


func _hurt_initial_overlaps() -> void:
	# Deferred, like the damage, because spawners place the explosion after adding it.
	LavaVent.explode_near(get_tree(), global_position, damage_radius)
	for body in hitbox.get_overlapping_bodies():
		_apply_damage_to_body(body)
	for area in hitbox.get_overlapping_areas():
		_extinguish_fireball_area(area)


func _on_hitbox_body_entered(body: Node) -> void:
	_apply_damage_to_body(body)


func _on_hitbox_area_entered(area: Area3D) -> void:
	_extinguish_fireball_area(area)


func _apply_damage_to_body(body: Node) -> void:
	if not hurts_enemies:
		return
	if body is not EnemyLocal:
		return
	if _is_behind_cover(body):
		return
	Health.apply_damage(body, damage, global_position)


## Casts from the enemy to the blast, not the other way: a blast sitting on a wall's face would start its ray on
## that face and could slip through it.
func _is_behind_cover(body: Node3D) -> bool:
	if not blocked_by_level:
		return false
	var from := body.global_position + Vector3.UP * ENEMY_AIM_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(from, global_position, LEVEL_COLLISION_MASK)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	return hit.position.distance_to(global_position) > COVER_TOLERANCE


func _extinguish_fireball_area(area: Area3D) -> void:
	var fireball := area.get_parent() as Fireball
	if fireball == null:
		return
	fireball.queue_free()
