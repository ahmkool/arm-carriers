extends Node3D

@export var speed: float = 22.0
@export var lifetime_seconds: float = 20.0

var _direction: Vector3 = Vector3.FORWARD
var _time_alive: float = 0.0

@onready var _hit_area: Area3D = $Area3D


func _ready():
	if _hit_area:
		_hit_area.area_entered.connect(_on_area_entered)


func _process(delta):
	global_position += _direction * speed * delta

	_time_alive += delta
	if _time_alive >= lifetime_seconds:
		queue_free()


func setup(direction: Vector3) -> void:
	_direction = direction.normalized()


func _on_area_entered(area: Area3D) -> void:
	if area == null:
		return

	var maybe_enemy := area.get_parent() as Node
	if maybe_enemy != null and maybe_enemy.is_in_group("enemy"):
		maybe_enemy.queue_free()
		queue_free()
