class_name BazookaBulletLocal
extends Node3D

const ExplosionScene := preload("res://src/vfx/explosion.tscn")
const SmallExplosionScene := preload("res://src/vfx/small_explosion.tscn")
const PARTICLE_LINGER_SECONDS := 3.0
## Far past what the camera shows, so it only removes rockets that have already missed.
const MAX_RANGE_METERS := 60.0
const LEVEL_COLLISION_LAYER_VALUE := 4

## Off by default: levels are designed around rockets flying through terrain.
@export var detonate_on_terrain := false

var velocity = Vector3.ZERO
var _spent := false
var _distance_travelled := 0.0

# Called when the node enters the scene tree for the first time.
func _ready():
	$SpawnExplosion.emitting = true
	if detonate_on_terrain:
		$HitArea.collision_mask |= LEVEL_COLLISION_LAYER_VALUE

func _physics_process(delta: float) -> void:
	global_position += velocity * delta
	_distance_travelled += velocity.length() * delta
	if _distance_travelled >= MAX_RANGE_METERS:
		_fizzle()

func _on_hit_area_body_entered(body: Node) -> void:
	if body is EnemyLocal or _is_terrain(body):
		_detonate()


func _is_terrain(body: Node) -> bool:
	if not detonate_on_terrain:
		return false
	if body is GridMap:
		return true
	return body is StaticBody3D or body is AnimatableBody3D


func _on_hit_area_area_entered(area: Area3D) -> void:
	var fireball := area.get_parent() as Fireball
	if fireball == null:
		return
	_spawn_small_explosion(fireball.global_position)
	fireball.queue_free()
	_detonate()


func _spawn_small_explosion(at_position: Vector3) -> void:
	var pop := SmallExplosionScene.instantiate() as Node3D
	get_tree().current_scene.add_child(pop)
	pop.global_position = at_position


## Ends a missed rocket with a harmless pop instead of a damaging, screen-shaking blast.
func _fizzle() -> void:
	if _spent:
		return
	_spent = true
	set_physics_process(false)
	_spawn_small_explosion(global_position)
	_free_non_particle_children()
	_schedule_delayed_free()


func _detonate() -> void:
	if _spent:
		return
	_spent = true
	set_physics_process(false)
	var explosion := ExplosionScene.instantiate() as Node3D
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	_free_non_particle_children()
	_schedule_delayed_free()


func _free_non_particle_children() -> void:
	for child in get_children():
		if child is GPUParticles3D:
			child.emitting = false
			continue
		child.queue_free()


func _schedule_delayed_free() -> void:
	get_tree().create_timer(PARTICLE_LINGER_SECONDS).timeout.connect(queue_free, CONNECT_ONE_SHOT)
