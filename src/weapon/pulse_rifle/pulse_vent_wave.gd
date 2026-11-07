class_name PulseVentWave
extends MeshInstance3D
## The visible vent blast: a flat cone-shaped shockwave that sweeps out from the muzzle to
## the blast's range and fades. The mesh points along +Z with a radius of 1, and the node's
## scale grows it to the range. A half angle of 180 degrees makes a full ring.

const SWEEP_SEC := 0.2
const FADE_SEC := 0.18
const START_SCALE := 0.15
const SEGMENTS := 18
## The bright front edge, as a share of the radius.
const FRONT_INNER := 0.8
const FILL_ALPHA := 0.22
const HEIGHT_ABOVE_GROUND := 0.35

var _reach := 1.0
var _half_angle_deg := PulseVent.HALF_ANGLE_DEG
var _elapsed := 0.0
var _color := Color.WHITE
var _material: StandardMaterial3D


static func spawn(parent: Node, origin: Vector3, forward: Vector3, reach: float, color: Color, half_angle_deg := PulseVent.HALF_ANGLE_DEG) -> PulseVentWave:
	var wave := PulseVentWave.new()
	wave._half_angle_deg = half_angle_deg
	parent.add_child(wave)
	var flat_forward := Vector3(forward.x, 0.0, forward.z).normalized()
	wave.global_position = Vector3(origin.x, origin.y - HEIGHT_ABOVE_GROUND, origin.z)
	wave.global_basis = Basis.looking_at(-flat_forward, Vector3.UP)
	wave.setup(reach, color)
	return wave


func setup(reach: float, color: Color) -> void:
	_reach = reach
	_color = color
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	_material.albedo_color = color
	mesh = _build_mesh()
	material_override = _material
	_apply(0.0)


func _process(delta: float) -> void:
	_elapsed += delta
	_apply(_elapsed)
	if _elapsed >= SWEEP_SEC + FADE_SEC:
		queue_free()


func _apply(time: float) -> void:
	var sweep := clampf(time / SWEEP_SEC, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - sweep, 3.0)
	var radius := lerpf(START_SCALE, 1.0, eased) * _reach
	scale = Vector3(radius, 1.0, radius)
	var fade := 1.0 - clampf((time - SWEEP_SEC) / FADE_SEC, 0.0, 1.0)
	_material.albedo_color = Color(_color, fade)


## A fan for the faint fill plus a band along the curved front, as one triangle list.
func _build_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var half := deg_to_rad(_half_angle_deg)
	for i in SEGMENTS:
		var a0 := lerpf(-half, half, float(i) / SEGMENTS)
		var a1 := lerpf(-half, half, float(i + 1) / SEGMENTS)
		_add_fill(verts, colors, a0, a1)
		_add_front(verts, colors, a0, a1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built


func _add_fill(verts: PackedVector3Array, colors: PackedColorArray, a0: float, a1: float) -> void:
	var apex_color := Color(1, 1, 1, 0.0)
	var edge_color := Color(1, 1, 1, FILL_ALPHA)
	verts.append_array([Vector3.ZERO, _arc(a0, FRONT_INNER), _arc(a1, FRONT_INNER)])
	colors.append_array([apex_color, edge_color, edge_color])


func _add_front(verts: PackedVector3Array, colors: PackedColorArray, a0: float, a1: float) -> void:
	var inner_color := Color(1, 1, 1, FILL_ALPHA)
	var outer_color := Color(1, 1, 1, 1.0)
	var i0 := _arc(a0, FRONT_INNER)
	var i1 := _arc(a1, FRONT_INNER)
	var o0 := _arc(a0, 1.0)
	var o1 := _arc(a1, 1.0)
	verts.append_array([i0, o0, o1, i0, o1, i1])
	colors.append_array([inner_color, outer_color, outer_color, inner_color, outer_color, inner_color])


func _arc(angle: float, radius: float) -> Vector3:
	return Vector3(sin(angle), 0.0, cos(angle)) * radius
