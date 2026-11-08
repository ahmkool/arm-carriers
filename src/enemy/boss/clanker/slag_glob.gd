class_name SlagGlob
extends Node3D
## A glob of molten slag lobbed from the Clanker's exhausts. A ring on the floor marks where it lands and fills as it
## falls. It burns any carrier inside on impact, then leaves a pool that burns whoever steps in until it cools.
## Carriers move as a pair, so a pool between them is as much in the way as one under their feet.

const IMPACT_SOUND := preload("res://assets/sounds/explosion/Small Explosion 2_1.wav")

@export var flight_seconds := 1.25
@export var arc_height := 7.0
@export var radius := 1.5
@export var pool_seconds := 4.0
## The pool burns within this share of the radius, so its glowing edge is a warning, not a trap.
@export var pool_burn_ratio := 0.8
@export var damage := 1.0

var _from := Vector3.ZERO
var _elapsed := 0.0
var _landed := false
var _pool_left := 0.0

@onready var _ring: MeshInstance3D = $Ring
@onready var _fill: MeshInstance3D = $Fill
@onready var _pool: MeshInstance3D = $Pool
@onready var _glob: MeshInstance3D = $Glob
@onready var _burst: GPUParticles3D = $Burst
@onready var _light: OmniLight3D = $Light


## Call after adding it to the tree and placing it where it lands.
func launch(from: Vector3) -> void:
	_from = from
	_glob.global_position = from


func _ready() -> void:
	_ring.scale = Vector3(radius, 1.0, radius)
	_fill.scale = Vector3(0.05, 1.0, 0.05)
	_pool.visible = false
	_light.light_energy = 0.0


func _physics_process(delta: float) -> void:
	if _landed:
		_cool(delta)
		return
	_elapsed += delta
	var progress := minf(_elapsed / flight_seconds, 1.0)
	_fly(progress)
	if progress < 1.0:
		return
	_land()


func _fly(progress: float) -> void:
	var flat := _from.lerp(global_position, progress)
	var height := arc_height * 4.0 * progress * (1.0 - progress)
	_glob.global_position = Vector3(flat.x, lerpf(_from.y, global_position.y, progress) + height, flat.z)
	var filled := radius * progress
	_fill.scale = Vector3(maxf(filled, 0.05), 1.0, maxf(filled, 0.05))


func _land() -> void:
	_landed = true
	_pool_left = pool_seconds
	_glob.visible = false
	_ring.visible = false
	_fill.visible = false
	_pool.visible = true
	_pool.scale = Vector3(radius, 1.0, radius)
	_burst.restart()
	_light.light_energy = 4.0
	CameraFeedback.add_trauma_hurt()
	_play_sound()
	_burn_players_within(radius)


func _cool(delta: float) -> void:
	_pool_left -= delta
	if _pool_left <= 0.0:
		queue_free()
		return
	var heat := clampf(_pool_left / pool_seconds, 0.0, 1.0)
	_light.light_energy = lerpf(0.6, 2.0, heat)
	var shrink := minf(_pool_left / 0.5, 1.0)
	_pool.scale = Vector3(radius * shrink, 1.0, radius * shrink)
	_burn_players_within(radius * pool_burn_ratio * shrink)


func _burn_players_within(reach: float) -> void:
	var players := get_tree().current_scene.get_node_or_null("Players")
	if players == null:
		return
	for child in players.get_children():
		_burn_if_within(child as PlayerLocal, reach)


func _burn_if_within(player: PlayerLocal, reach: float) -> void:
	if player == null or player.is_dead:
		return
	var offset := player.global_position - global_position
	if Vector2(offset.x, offset.z).length() > reach:
		return
	Health.apply_damage(player, damage, global_position)


func _play_sound() -> void:
	var sfx := AudioStreamPlayer3D.new()
	add_child(sfx)
	sfx.bus = "SFX"
	sfx.stream = IMPACT_SOUND
	sfx.finished.connect(sfx.queue_free, CONNECT_ONE_SHOT)
	sfx.play()
