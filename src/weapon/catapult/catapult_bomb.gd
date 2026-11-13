class_name CatapultBomb
extends Node3D
## A bomb lobbed by the catapult. It follows an exact parabola, so the landing point the
## aim guide predicts with `predict_flight` is where it really lands, then it blows up.
## An enemy's catapult (SiegeCatapult) throws the same bomb made hostile with `make_hostile`: it then ignores enemy
## bodies, blows up only on the level, and hurts the carriers inside its blast instead of enemies.

signal exploded(at_position: Vector3)

const EXPLOSION_SCENE := preload("res://src/vfx/explosion.tscn")
const LEVEL_COLLISION_MASK := 4
## Seconds between the points sampled along a predicted flight.
const PREDICTION_STEP_SEC := 1.0 / 30.0
## A flight that hasn't landed by then is treated as lost.
const MAX_FLIGHT_SEC := 6.0
const SPIN_SPEED := 7.0
## A hostile blast reaches carriers this far above or below it, so not across floors.
const HOSTILE_BLAST_HEIGHT := 2.5

@onready var _model: Node3D = $Model
@onready var _hit_area: Area3D = $HitArea

var _origin := Vector3.ZERO
var _velocity := Vector3.ZERO
var _gravity := 0.0
var _floor_y := 0.0
var _elapsed := 0.0
var _spent := false
var _hostile := false
var _hostile_damage := 3
var _hostile_radius := 3.0


## Thrown by an enemy: call before adding it to the tree.
func make_hostile(damage: int, blast_radius: float) -> void:
	_hostile = true
	_hostile_damage = damage
	_hostile_radius = blast_radius
	add_to_group(Checkpoint.ENEMY_PROJECTILE_GROUP)


func is_hostile() -> bool:
	return _hostile


func _ready() -> void:
	_hit_area.body_entered.connect(_on_hit_area_body_entered)


func launch(origin: Vector3, velocity: Vector3, gravity: float, floor_y: float) -> void:
	_origin = origin
	_velocity = velocity
	_gravity = gravity
	_floor_y = floor_y
	global_position = origin


func _physics_process(delta: float) -> void:
	if _spent:
		return
	var from := global_position
	_elapsed += delta
	var to := position_at(_origin, _velocity, _gravity, _elapsed)
	_model.rotate_x(SPIN_SPEED * delta)
	var hit := _cast_level(get_world_3d().direct_space_state, from, to)
	if not hit.is_empty():
		_detonate(hit.position)
		return
	if to.y <= _floor_y or _elapsed >= MAX_FLIGHT_SEC:
		_detonate(to)
		return
	global_position = to


static func position_at(origin: Vector3, velocity: Vector3, gravity: float, time: float) -> Vector3:
	return origin + velocity * time + Vector3.DOWN * (0.5 * gravity * time * time)


## Follows a flight from `origin` until it meets the level or drops to `floor_y`.
## Returns `points` sampled along the way, the `landing` point and whether it `hit_ground`.
static func predict_flight(
	space: PhysicsDirectSpaceState3D,
	origin: Vector3,
	velocity: Vector3,
	gravity: float,
	floor_y: float
) -> Dictionary:
	var points: Array[Vector3] = [origin]
	var from := origin
	var time := 0.0
	while time < MAX_FLIGHT_SEC:
		time += PREDICTION_STEP_SEC
		var to := position_at(origin, velocity, gravity, time)
		var hit := _cast_level(space, from, to)
		if not hit.is_empty():
			points.append(hit.position)
			return {"points": points, "landing": hit.position, "hit_ground": true}
		if to.y <= floor_y:
			var below := _cross_floor(from, to, floor_y)
			points.append(below)
			return {"points": points, "landing": below, "hit_ground": false}
		points.append(to)
		from = to
	return {"points": points, "landing": from, "hit_ground": false}


static func _cast_level(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, LEVEL_COLLISION_MASK)
	return space.intersect_ray(query)


static func _cross_floor(from: Vector3, to: Vector3, floor_y: float) -> Vector3:
	var span := from.y - to.y
	if span <= 0.0001:
		return to
	return from.lerp(to, (from.y - floor_y) / span)


func _on_hit_area_body_entered(body: Node3D) -> void:
	if _hostile:
		return
	if body is not EnemyLocal:
		return
	_detonate(global_position, FrontalGuard.absorb_strike(body, global_position))


## `on_shield`: it struck a shield head on, so the blast is only for show and hurts no one.
func _detonate(at_position: Vector3, on_shield := false) -> void:
	if _spent:
		return
	_spent = true
	exploded.emit(at_position)
	_hurt_carriers(at_position)
	var explosion := EXPLOSION_SCENE.instantiate() as Node3D
	explosion.set("hurts_enemies", not on_shield and not _hostile)
	if _hostile:
		explosion.set("damage_radius", _hostile_radius)
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = at_position
	CameraFeedback.add_trauma_explosion()
	queue_free()


func _hurt_carriers(at_position: Vector3) -> void:
	if not _hostile:
		return
	var players := get_tree().current_scene.get_node_or_null(^"Players")
	if players == null:
		return
	for child in players.get_children():
		_hurt_carrier(child as PlayerLocal, at_position)


func _hurt_carrier(player: PlayerLocal, at_position: Vector3) -> void:
	if player == null or player.is_dead:
		return
	var offset := player.global_position - at_position
	if absf(offset.y) > HOSTILE_BLAST_HEIGHT:
		return
	if Vector2(offset.x, offset.z).length() > _hostile_radius:
		return
	if Health.apply_damage(player, _hostile_damage, at_position):
		CameraFeedback.add_trauma_hurt()
