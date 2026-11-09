class_name MechGrenade
extends Node3D
## A grenade fired by the grenadier mech. It leaves the barrel level and dips onto its target, bounces and rolls to a stop on the floor, and
## from its first touch of the floor a red ring shows the blast while it blinks and beeps faster and faster.
## Then it explodes: carriers inside the ring take `damage`. Enemies are not hurt.
## One that never lands (thrown over a drop) is freed after `max_airborne_seconds`.

const FLOOR_MASK := 4
## The grenade's radius, for resting on the floor.
const RADIUS := 0.16
const EXPLOSION_SCENE := preload("res://src/vfx/explosion.tscn")
## A target level with or above the barrel still gets a slight drop, so the grenade comes down past it.
const MIN_DROP := 0.4
const LAND_SOUND := preload("res://assets/sounds/metal/GridStep01.wav")

## Pull once it has landed and rolls off an edge. In flight it uses the gravity `launch_flat` picks.
@export var gravity := 20.0
## Seconds from its first touch of the floor to the blast.
@export var fuse_seconds := 1.8
@export var blast_radius := 2.6
@export var damage := 3
## Share of the speed kept by a bounce.
@export var bounce := 0.3
## How quickly it stops rolling, per second.
@export var rolling_friction := 5.0
@export var max_airborne_seconds := 6.0
## Spin while flying, in turns per second.
@export var spin_turns_per_second := 2.0

@onready var _model: Node3D = $Model
@onready var _blink: OmniLight3D = $BlinkLight
@onready var _ring: Node3D = $WarningRing
@onready var _beep: AudioStreamPlayer3D = $Beep

var velocity := Vector3.ZERO
var _flight_gravity := 20.0
var _airborne_time := 0.0
var _landed := false
var _rolling := false
## Rolled off an edge after landing: it drops, and the fuse keeps burning.
var _falling := false
var _fuse_left := 0.0
var _blink_left := 0.0
var _blink_on := false
var _ring_material: StandardMaterial3D


## Fires it level from `from` at `speed`, toward `to`: it leaves the barrel flat and, with its flight gravity chosen
## to drop it exactly the barrel's height over that distance, comes down where `to` is.
func launch_flat(from: Vector3, to: Vector3, speed: float) -> void:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var seconds := maxf(flat.length() / maxf(speed, 0.1), 0.1)
	var drop := maxf(from.y - to.y, MIN_DROP)
	velocity = flat.normalized() * speed
	_flight_gravity = 2.0 * drop / (seconds * seconds)


func _ready() -> void:
	_ring.visible = false
	_ring.scale = Vector3(blast_radius, 1.0, blast_radius)
	_blink.visible = false
	_ring_material = (_ring.get_node("Edge") as MeshInstance3D).get_active_material(0) as StandardMaterial3D


func is_armed() -> bool:
	return _landed


func fuse_left() -> float:
	return _fuse_left


func _physics_process(delta: float) -> void:
	if not _landed:
		_fly(delta)
		return
	_roll(delta)
	_fall(delta)
	_tick_fuse(delta)


func _fly(delta: float) -> void:
	_airborne_time += delta
	if _airborne_time > max_airborne_seconds:
		queue_free()
		return
	velocity.y -= _flight_gravity * delta
	_model.rotate_x(TAU * spin_turns_per_second * delta)
	var hit := _floor_hit(global_position, global_position + velocity * delta)
	if hit.is_empty():
		global_position += velocity * delta
		return
	_land(hit)


func _land(hit: Dictionary) -> void:
	global_position = (hit.position as Vector3) + Vector3.UP * RADIUS
	velocity = velocity.bounce(hit.normal as Vector3) * bounce
	velocity.y = 0.0
	_landed = true
	_rolling = true
	_fuse_left = fuse_seconds
	_ring.visible = true
	_play_land_sound()


## Rolls along the floor until it stops, dropping with it if it rolls off an edge.
func _roll(delta: float) -> void:
	if not _rolling:
		return
	velocity = velocity.move_toward(Vector3.ZERO, rolling_friction * delta)
	var step := velocity * delta
	var below := _floor_hit(global_position + step + Vector3.UP * 0.3, global_position + step + Vector3.DOWN * 0.6)
	if below.is_empty():
		_rolling = false
		_falling = true
		return
	global_position = (below.position as Vector3) + Vector3.UP * RADIUS
	_model.rotate_x(velocity.length() / RADIUS * delta)
	if velocity.length() < 0.05:
		_rolling = false


func _fall(delta: float) -> void:
	if not _falling:
		return
	velocity.y -= gravity * delta
	global_position += velocity * delta


func _floor_hit(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to + (to - from).normalized() * RADIUS, FLOOR_MASK)
	return get_world_3d().direct_space_state.intersect_ray(query)


## Blinks and beeps faster as the fuse burns down; the ring pulses with it.
func _tick_fuse(delta: float) -> void:
	_fuse_left -= delta
	if _fuse_left <= 0.0:
		_explode()
		return
	var urgency := 1.0 - _fuse_left / fuse_seconds
	_ring_material.albedo_color.a = lerpf(0.45, 0.9, urgency) * (0.75 + 0.25 * float(_blink_on))
	_blink_left -= delta
	if _blink_left > 0.0:
		return
	_blink_on = not _blink_on
	_blink.visible = _blink_on
	_blink_left = lerpf(0.22, 0.05, urgency)
	if _blink_on:
		_beep.pitch_scale = lerpf(1.0, 1.35, urgency)
		_beep.play()


func _explode() -> void:
	var scene_root := get_tree().current_scene
	_hurt_carriers(scene_root)
	_spawn_blast(scene_root)
	queue_free()


func _hurt_carriers(scene_root: Node) -> void:
	var players := scene_root.get_node_or_null(^"Players")
	if players == null:
		return
	for child in players.get_children():
		var player := child as PlayerLocal
		if player == null or player.is_dead:
			continue
		if not _in_blast(player):
			continue
		if Health.apply_damage(player, damage, global_position):
			CameraFeedback.add_trauma_hurt()


## Flat distance, so a carrier's height doesn't matter, but not across floors far above or below.
func _in_blast(player: PlayerLocal) -> bool:
	var offset := player.global_position - global_position
	if absf(offset.y) > 2.5:
		return false
	return Vector2(offset.x, offset.z).length() <= blast_radius


func _spawn_blast(scene_root: Node) -> void:
	var blast := EXPLOSION_SCENE.instantiate()
	blast.set("hurts_enemies", false)
	blast.set("damage_radius", blast_radius)
	scene_root.add_child(blast)
	blast.global_position = global_position


func _play_land_sound() -> void:
	var sfx := AudioStreamPlayer3D.new()
	get_tree().current_scene.add_child(sfx)
	sfx.global_position = global_position
	sfx.bus = "SFX"
	sfx.stream = LAND_SOUND
	sfx.pitch_scale = 0.7
	sfx.finished.connect(sfx.queue_free, CONNECT_ONE_SHOT)
	sfx.play()
