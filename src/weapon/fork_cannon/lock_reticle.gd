class_name LockReticle
extends Node3D
## The fork cannon's lock marker: a ring around the enemy the bolts are painting. It closes in
## and brightens with each hit, then turns hot, spins and pulses once the lock is set, so the
## front carrier can see the missile is ready to steer.

const RING_RADIUS := 1.3
const RING_THICKNESS := 0.09
## How wide the ring opens on the first hit, as a multiple of its locked size.
const OPEN_SCALE := 1.8
const PAINT_COLOR := Color(0.45, 0.95, 1.0)
const LOCK_COLOR := Color(1.0, 0.3, 0.08)
const PAINT_ALPHA := 0.45
const LOCK_ALPHA := 0.95
const SPIN_PER_SEC := 2.5
const PULSE_HZ := 4.0
const PULSE_AMOUNT := 0.08
const FOLLOW_HEIGHT := 0.15
const TICK_COUNT := 4

var _material: StandardMaterial3D
var _target: Node3D
var _progress := 0.0
var _locked := false
var _time := 0.0


func _ready() -> void:
	top_level = true
	visible = false
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.render_priority = 1
	_add_ring()
	_add_ticks()


## `progress` runs from 0 (no hits) to 1 (locked).
func show_on(target: Node3D, progress: float, locked: bool) -> void:
	_target = target
	_progress = clampf(progress, 0.0, 1.0)
	_locked = locked
	visible = is_instance_valid(target)


func clear() -> void:
	_target = null
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	if not is_instance_valid(_target):
		clear()
		return
	_time += delta
	global_position = _target.global_position + Vector3.UP * FOLLOW_HEIGHT
	var size := lerpf(OPEN_SCALE, 1.0, _progress)
	var spin := SPIN_PER_SEC if _locked else SPIN_PER_SEC * 0.3
	if _locked:
		size *= 1.0 + sin(_time * TAU * PULSE_HZ) * PULSE_AMOUNT
	scale = Vector3.ONE * size
	rotation.y = wrapf(rotation.y + spin * delta, 0.0, TAU)
	var color := LOCK_COLOR if _locked else PAINT_COLOR
	var alpha := LOCK_ALPHA if _locked else lerpf(0.2, PAINT_ALPHA, _progress)
	_material.albedo_color = Color(color, alpha)


func _add_ring() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = RING_RADIUS - RING_THICKNESS
	torus.outer_radius = RING_RADIUS + RING_THICKNESS
	torus.rings = 32
	torus.ring_segments = 6
	torus.material = _material
	_add_mesh(torus, Transform3D.IDENTITY)


## Short bars pointing in at the enemy, so the ring reads as crosshairs rather than a halo.
func _add_ticks() -> void:
	var bar := BoxMesh.new()
	bar.size = Vector3(0.12, 0.06, 0.45)
	bar.material = _material
	for index in TICK_COUNT:
		var angle := TAU * index / TICK_COUNT
		var turn := Basis(Vector3.UP, angle)
		var offset := turn * Vector3(0.0, 0.0, RING_RADIUS + 0.1)
		_add_mesh(bar, Transform3D(turn, offset))


func _add_mesh(mesh: Mesh, local_transform: Transform3D) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.transform = local_transform
	add_child(instance)
