class_name FrontalGuard
extends Node
## A big physical shield carried in front of its parent enemy: any hit whose source lies inside
## the guarded arc in front of the enemy is blocked. A bazooka rocket that blows up on the shield
## does nothing, so the carriers have to fly the rocket past and detonate it beside or behind him.
## Falling out of the level still kills.

const BLOCK_SOUND := preload("res://assets/sounds/metal/GridStep03.wav")
const SPARKS_SCENE := preload("res://src/vfx/small_explosion.tscn")
const RECOIL_DISTANCE := 0.18
const RECOIL_SECONDS := 0.22
## A source this close to the enemy's centre has no meaningful direction, so it isn't blocked.
const MIN_SOURCE_DISTANCE := 0.2

## Half-angle of the guarded arc, measured from the enemy's facing direction.
@export_range(0.0, 180.0) var half_angle_degrees := 60.0
## The shield's visual, kicked back a little when it blocks a hit.
@export var shield_visual: Node3D

signal blocked(source_position: Vector3)

var _enemy: Node3D
var _visual_rest_position := Vector3.ZERO
var _recoil_tween: Tween


func _ready() -> void:
	_enemy = get_parent() as Node3D
	if shield_visual != null:
		_visual_rest_position = shield_visual.position
	var health := Health.from_target(get_parent())
	if health == null:
		return
	health.guard = self


static func find_on(enemy: Node) -> FrontalGuard:
	for child in enemy.get_children():
		if child is FrontalGuard:
			return child
	return null


## For a projectile that strikes `body` at `point`: true when the body's shield is facing it, in which case the
## shield takes it and plays its feedback. The caller then bursts harmlessly: a blast stopped by a shield must not
## reach the enemies beside it either, even those it would catch from their side.
static func absorb_strike(body: Node, point: Vector3) -> bool:
	var guard := find_on(body)
	if guard == null or not guard.blocks(point):
		return false
	var enemy := body as EnemyLocal
	if enemy != null and not enemy.is_alive():
		return false
	guard.absorb(point)
	return true


## Whether a hit coming from `source_position` lands on the shield.
func blocks(source_position: Vector3) -> bool:
	if _enemy == null:
		return false
	var to_source := source_position - _enemy.global_position
	var flat := Vector3(to_source.x, 0.0, to_source.z)
	if flat.length() < MIN_SOURCE_DISTANCE:
		return false
	return get_facing().dot(flat.normalized()) >= cos(deg_to_rad(half_angle_degrees))


## Flat forward of the enemy: Godot bodies face -Z.
func get_facing() -> Vector3:
	var forward := -_enemy.global_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector3.FORWARD
	return forward.normalized()


## Called by `Health` in place of taking the damage.
func absorb(source_position: Vector3) -> void:
	var impact := _impact_point(source_position)
	ImpactFeedback.play_sfx(BLOCK_SOUND, impact, randf_range(0.7, 0.85), 0.0)
	_spawn_sparks(impact)
	_kick_visual()
	blocked.emit(source_position)


func _impact_point(source_position: Vector3) -> Vector3:
	if shield_visual == null:
		return source_position
	return shield_visual.global_position


func _spawn_sparks(at_position: Vector3) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var sparks := SPARKS_SCENE.instantiate() as Node3D
	scene_root.add_child(sparks)
	sparks.global_position = at_position


func _kick_visual() -> void:
	if shield_visual == null:
		return
	if _recoil_tween != null and _recoil_tween.is_valid():
		_recoil_tween.kill()
	# The visual's local +Z points back toward the enemy, since it sits under the 180°-turned model.
	var back := _visual_rest_position + Vector3(0.0, 0.0, -RECOIL_DISTANCE)
	shield_visual.position = back
	_recoil_tween = create_tween()
	_recoil_tween.tween_property(shield_visual, "position", _visual_rest_position, RECOIL_SECONDS) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
