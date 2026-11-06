extends Node3D
## A marked circle on the floor that erupts after a moment. Carriers have to move out together,
## so the weapon between them makes this harder to dodge than it looks.

const HIT_SOUND := preload("res://assets/sounds/explosion/Small Explosion 2_1.wav")

@export var telegraph_seconds := 1.4
@export var radius := 2.0
@export var linger_seconds := 0.8

@onready var _ring: MeshInstance3D = $Ring
@onready var _spikes: Node3D = $Spikes
@onready var _burst: GPUParticles3D = $Burst
@onready var _light: OmniLight3D = $OmniLight3D


func _ready() -> void:
	_spikes.visible = false
	_ring.scale = Vector3(radius * 0.25, 1.0, radius * 0.25)
	var tween := create_tween()
	tween.tween_property(_ring, "scale", Vector3(radius, 1.0, radius), telegraph_seconds)
	tween.tween_callback(_erupt)


func _erupt() -> void:
	_hurt_players_inside()
	_burst.emitting = true
	_play_hit_sound()
	CameraFeedback.add_trauma_hurt()
	_animate_spikes()
	var tween := create_tween()
	tween.tween_property(_light, "light_energy", 5.0, 0.05)
	tween.tween_property(_light, "light_energy", 0.0, linger_seconds)
	tween.tween_callback(queue_free)


func _hurt_players_inside() -> void:
	var players := get_tree().current_scene.get_node_or_null("Players")
	if players == null:
		return
	for child in players.get_children():
		_hurt_if_inside(child as PlayerLocal)


func _hurt_if_inside(player: PlayerLocal) -> void:
	if player == null or player.is_dead:
		return
	var offset := player.global_position - global_position
	if Vector2(offset.x, offset.z).length() > radius:
		return
	Health.apply_damage(player, 1, global_position)


func _animate_spikes() -> void:
	_spikes.visible = true
	_ring.visible = false
	_spikes.position.y = -2.2
	var tween := create_tween()
	tween.tween_property(_spikes, "position:y", 0.0, 0.1).set_ease(Tween.EASE_OUT)
	tween.tween_interval(linger_seconds * 0.4)
	tween.tween_property(_spikes, "position:y", -2.2, linger_seconds * 0.5).set_ease(Tween.EASE_IN)


func _play_hit_sound() -> void:
	var sfx := AudioStreamPlayer3D.new()
	add_child(sfx)
	sfx.bus = "SFX"
	sfx.stream = HIT_SOUND
	sfx.play()
