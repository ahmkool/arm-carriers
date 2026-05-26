extends Node3D

## Matches `Hitbox/CollisionShape3D` sphere radius when synced in `_ready`.
@export var damage_radius: float = 3.5

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
	for body in hitbox.get_overlapping_bodies():
		_apply_damage_to_body(body)


func _on_hitbox_body_entered(body: Node) -> void:
	_apply_damage_to_body(body)


func _apply_damage_to_body(body: Node) -> void:
	if body is EnemyLocal:
		(body as EnemyLocal).die(global_position)
