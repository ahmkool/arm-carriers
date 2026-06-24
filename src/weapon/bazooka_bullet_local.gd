class_name BazookaBulletLocal
extends Node3D

const ExplosionScene := preload("res://src/vfx/explosion.tscn")
const SmallExplosionScene := preload("res://src/vfx/small_explosion.tscn")
const PARTICLE_LINGER_SECONDS := 3.0

var velocity = Vector3.ZERO
var _spent := false

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


func _physics_process(delta: float) -> void:
	global_position += velocity * delta

func _on_hit_area_body_entered(body: Node) -> void:
	if body is not EnemyLocal:
		return
	_detonate()


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
