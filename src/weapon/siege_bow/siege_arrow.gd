class_name SiegeArrow
extends Node3D
## The origin is the arrow's tail and it points along -Z, so the arrow starts exactly where
## it sat on the string. It flies through terrain, like the bazooka's rockets, and pierces
## enemies until it has hit `pierce_hits` of them or its head reaches its range.

signal spent(head_distance: float, hit_count: int)
signal hit_enemy(enemy: Node3D)

## Tail to the base of the head. Matches siege_arrow_visual.tscn.
const LENGTH := 8.5
const SLASH_HEIGHT := 1.0
const SLASH_SCENE := preload("res://src/vfx/sword_slash.tscn")
const POP_SCENE := preload("res://src/vfx/small_explosion.tscn")
const HIT_SOUND := preload("res://assets/sounds/damage/sword_hit.wav")

@onready var _hit_area: Area3D = $HitArea

var _direction := Vector3.FORWARD
var _speed := 0.0
var _flight_range := 0.0
var _damage := 0
var _pierce_hits := 0
var _bow_position := Vector3.ZERO
var _head_distance := 0.0
var _hit_count := 0
var _is_spent := false


func _ready() -> void:
	_hit_area.body_entered.connect(_on_body_entered)


## `bow_position` is where range is measured from. Enemies behind it are never hit, because
## the shaft starts out overlapping everything between the carriers.
func launch(
	tail_position: Vector3,
	bow_position: Vector3,
	direction: Vector3,
	speed: float,
	flight_range: float,
	damage: int,
	pierce_hits: int
) -> void:
	global_position = tail_position
	global_basis = Basis.looking_at(direction, Vector3.UP)
	_bow_position = bow_position
	_direction = direction
	_speed = speed
	_flight_range = flight_range
	_damage = damage
	_pierce_hits = pierce_hits
	_head_distance = (tail_position - bow_position).dot(direction) + LENGTH


func _physics_process(delta: float) -> void:
	var step := _speed * delta
	global_position += _direction * step
	_head_distance += step
	if _head_distance >= _flight_range:
		_finish()


func _on_body_entered(body: Node3D) -> void:
	if _is_spent or _is_behind_bow(body):
		return
	# Damage comes from just behind the enemy, so knockback pushes along the arrow's flight.
	if not Health.apply_damage(body, _damage, body.global_position - _direction):
		return
	_hit_count += 1
	_play_hit_feedback(body)
	hit_enemy.emit(body)
	if _hit_count >= _pierce_hits:
		_finish()


func _is_behind_bow(body: Node3D) -> bool:
	return (body.global_position - _bow_position).dot(_direction) < 0.0


func _play_hit_feedback(body: Node3D) -> void:
	ImpactFeedback.play_sfx(HIT_SOUND, body.global_position, randf_range(0.9, 1.1), 0.0)
	ImpactFeedback.play_sword_hit()
	var slash := SLASH_SCENE.instantiate() as SwordSlash
	get_tree().current_scene.add_child(slash)
	slash.global_position = body.global_position + Vector3.UP * SLASH_HEIGHT
	slash.align_to(_direction)


func _finish() -> void:
	if _is_spent:
		return
	_is_spent = true
	var pop := POP_SCENE.instantiate() as Node3D
	get_tree().current_scene.add_child(pop)
	pop.global_position = to_global(Vector3(0.0, 0.0, -LENGTH))
	spent.emit(_head_distance, _hit_count)
	queue_free()
