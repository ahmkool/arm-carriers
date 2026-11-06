class_name KatanaBlinkVfx
extends Node3D
## 4GTN's rage blink. Where it leaves, a column of light streams up and shards burst out;
## where it lands, particles pull in first (the carriers' warning), then the same column.
## Each instance plays once and frees itself.

const LIFETIME := 1.2

@export var ring_radius := 2.2
@export var ring_seconds := 0.35
@export var flash_energy := 6.0
@export var flash_seconds := 0.3

@onready var _gather: GPUParticles3D = $Gather
@onready var _streaks: GPUParticles3D = $Streaks
@onready var _shards: GPUParticles3D = $Shards
@onready var _ring: MeshInstance3D = $Ring
@onready var _flash: OmniLight3D = $Flash


func _ready() -> void:
	_ring.visible = false
	_flash.light_energy = 0.0
	# Every blink fades its own ring.
	_ring.material_override = _ring.mesh.surface_get_material(0).duplicate()
	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)


## Warning at the landing spot: light pulls in toward where it will appear.
func play_gather() -> void:
	_gather.emitting = true


## Leaving or arriving: the column, the shards, the ring and the flash.
func play_burst() -> void:
	_streaks.emitting = true
	_shards.emitting = true
	_expand_ring()
	_flash_light()


func _expand_ring() -> void:
	var material := _ring.material_override as StandardMaterial3D
	_ring.visible = true
	_ring.scale = Vector3.ONE * 0.2
	var tween := create_tween().set_parallel()
	tween.tween_property(_ring, "scale", Vector3.ONE * ring_radius, ring_seconds) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, ring_seconds)


func _flash_light() -> void:
	var tween := create_tween()
	tween.tween_property(_flash, "light_energy", flash_energy, flash_seconds * 0.2)
	tween.tween_property(_flash, "light_energy", 0.0, flash_seconds * 0.8)
