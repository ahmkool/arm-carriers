extends Node3D

## Matches `Hitbox/CollisionShape3D` sphere radius when synced in `_ready`.
@export var damage_radius: float = 3.5

@onready var debris = $Debris
@onready var fire = $Fire
@onready var smoke = $Smoke
@onready var hitbox: Area3D = $Hitbox


func _ready() -> void:
	debris.emitting = true
	fire.emitting = true
	smoke.emitting = true
	_sync_hitbox_sphere_radius()
	call_deferred("_hurt_initial_overlaps")
	get_tree().create_timer(0.2).timeout.connect(_queue_free_hitbox)
	await get_tree().create_timer(2.0).timeout
	queue_free()


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
	for body in hitbox.get_overlapping_bodies():
		_apply_damage_to_body(body)


func _on_hitbox_body_entered(body: Node) -> void:
	_apply_damage_to_body(body)


func _apply_damage_to_body(body: Node) -> void:
	if body is EnemyLocal:
		(body as EnemyLocal).die()
