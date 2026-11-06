class_name CatapultAimGuide
extends Node3D
## Shows both carriers where the next bomb will land: a ring the size of the blast on the
## ground, and dots along the arc. It lives in world space, so it ignores the weapon's sway.

const ARC_DOT_COUNT := 16
const ARC_DOT_RADIUS := 0.11
const GROUND_LIFT := 0.08
const PULSE_SPEED := 5.0

const READY_COLOR := Color(1.0, 0.95, 0.75, 0.9)
const RELOADING_COLOR := Color(1.0, 0.95, 0.75, 0.3)
## Shown when the bomb would land in lava or a pit, where its blast is wasted.
const NO_GROUND_COLOR := Color(1.0, 0.3, 0.25, 0.75)

@export var blast_radius := 3.5

@onready var _ring: MeshInstance3D = $Ring
@onready var _fill: MeshInstance3D = $Fill
@onready var _center: MeshInstance3D = $Center

var _ring_material: StandardMaterial3D
var _fill_material: StandardMaterial3D
var _dot_material: StandardMaterial3D
var _dots: Array[MeshInstance3D] = []
var _pulse := 0.0


func _ready() -> void:
	top_level = true
	_ring_material = _ring.get_active_material(0) as StandardMaterial3D
	_fill_material = _fill.get_active_material(0) as StandardMaterial3D
	_dot_material = _ring_material.duplicate() as StandardMaterial3D
	_ring.scale = Vector3(blast_radius, 1.0, blast_radius)
	_fill.scale = Vector3(blast_radius, 1.0, blast_radius)
	_create_arc_dots()
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse = fmod(_pulse + delta * PULSE_SPEED, TAU)
	var pulse_scale := 0.85 + 0.15 * sin(_pulse)
	_center.scale = Vector3.ONE * pulse_scale


## `flight` comes from `CatapultBomb.predict_flight`.
func show_flight(flight: Dictionary, is_loaded: bool) -> void:
	visible = true
	var landing: Vector3 = flight.landing
	global_transform = Transform3D(Basis.IDENTITY, landing + Vector3.UP * GROUND_LIFT)
	_apply_color(_get_color(flight.hit_ground, is_loaded))
	_place_arc_dots(flight.points)


func hide_guide() -> void:
	visible = false


func _get_color(hit_ground: bool, is_loaded: bool) -> Color:
	if not hit_ground:
		return NO_GROUND_COLOR
	if not is_loaded:
		return RELOADING_COLOR
	return READY_COLOR


func _apply_color(color: Color) -> void:
	_ring_material.albedo_color = color
	_dot_material.albedo_color = color
	_fill_material.albedo_color = Color(color.r, color.g, color.b, color.a * 0.18)
	(_center.get_active_material(0) as StandardMaterial3D).albedo_color = color


func _create_arc_dots() -> void:
	var mesh := SphereMesh.new()
	mesh.radius = ARC_DOT_RADIUS
	mesh.height = ARC_DOT_RADIUS * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = _dot_material
	for index in ARC_DOT_COUNT:
		var dot := MeshInstance3D.new()
		dot.mesh = mesh
		dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dot.top_level = true
		add_child(dot)
		_dots.append(dot)


## Spreads the dots evenly along the predicted points, skipping the start and the landing.
func _place_arc_dots(points: Array[Vector3]) -> void:
	var last := points.size() - 1
	for index in _dots.size():
		var along := float(index + 1) / float(_dots.size() + 1)
		var point_index := clampi(roundi(along * last), 0, last)
		_dots[index].global_position = points[point_index]
