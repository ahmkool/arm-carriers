class_name SpikeWall
extends Node3D
## A wooden wall studded with iron spikes that slides forward (local -Z) when its SpikeTrap pushes it.
## Anything the spikes touch dies, enemies included. Enemies steer clear of it through EnemyAvoidZone.
##
## The origin sits on the floor at the wall's front face, where the spikes start. The spikes point along -Z.

const SPIKE_SPACING := 0.55
const SPIKE_RADIUS := 0.17
## Physics layers 1 (players) and 2 (enemies).
const VICTIM_MASK := 3
## How far behind the wall still counts as "inside" it for enemies, so none path round behind a wall.
const BEHIND_REACH := 60.0
## Roughly a carrier's or skeleton's capsule radius, so a body counts once its side touches the spikes.
const BODY_RADIUS := 0.45

@export var width := 30.0
@export var height := 2.0
@export var depth := 0.7
@export var spike_length := 0.85

var _kill_area: Area3D


func _ready() -> void:
	add_to_group(EnemyAvoidZone.GROUP)
	_build_slab()
	_build_spikes()
	_build_kill_area()


func _physics_process(_delta: float) -> void:
	for body in _kill_area.get_overlapping_bodies():
		_impale(body)


## Where the spike tips are, measured along the wall's forward from its origin.
func get_reach() -> float:
	return spike_length


## The direction the wall slides in, flat.
func get_forward() -> Vector3:
	var forward := -global_basis.z
	forward.y = 0.0
	return forward.normalized()


# ---- EnemyAvoidZone ----

func keeps_out(point: Vector3, margin: float) -> bool:
	var local := to_local(point)
	if absf(local.x) > width * 0.5 + margin:
		return false
	return local.z > -(spike_length + margin) and local.z < depth + BEHIND_REACH


## The nearest point in front of the spikes, `margin` clear of them.
func push_out(point: Vector3, margin: float) -> Vector3:
	if not keeps_out(point, margin):
		return point
	var local := to_local(point)
	local.z = -(spike_length + margin)
	return to_global(local)


## Which way an enemy should walk to get away from the wall.
func get_escape_direction() -> Vector3:
	return get_forward()


# ---- Building ----

func _impale(body: Node3D) -> void:
	if body is not PlayerLocal and body is not EnemyLocal:
		return
	if not _is_in_spikes(body.global_position):
		return
	Health.apply_damage(body, 9999, global_position)


## The area's overlap list lags a physics step behind teleports: without this, carriers revived at the
## checkpoint were impaled again on arrival.
func _is_in_spikes(point: Vector3) -> bool:
	var local := to_local(point)
	if absf(local.x) > width * 0.5 + BODY_RADIUS:
		return false
	return local.z > -(spike_length + BODY_RADIUS) and local.z < depth + BODY_RADIUS


func _build_slab() -> void:
	var slab := MeshInstance3D.new()
	slab.name = "Slab"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, height, depth)
	mesh.material = _wood_material()
	slab.mesh = mesh
	slab.position = Vector3(0.0, height * 0.5, depth * 0.5)
	add_child(slab)
	_build_iron_band(height * 0.25)
	_build_iron_band(height * 0.75)


func _build_iron_band(y: float) -> void:
	var band := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width + 0.04, 0.16, 0.06)
	mesh.material = _iron_material()
	band.mesh = mesh
	band.position = Vector3(0.0, y, -0.03)
	add_child(band)


func _build_spikes() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = SPIKE_RADIUS
	cone.height = spike_length
	cone.radial_segments = 8
	cone.rings = 1
	cone.material = _iron_material()
	var rows := _spike_rows()
	var columns := int(floor(width / SPIKE_SPACING))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = cone
	multimesh.instance_count = columns * rows.size()
	# A cylinder stands along +Y; tip it forward so it points along -Z, base on the wall's face.
	var tip_forward := Basis(Vector3.RIGHT, -PI * 0.5)
	var index := 0
	for row in rows.size():
		var stagger := SPIKE_SPACING * 0.5 * (row % 2)
		for column in columns:
			var x := -width * 0.5 + SPIKE_SPACING * (column + 0.5) + stagger
			x = minf(x, width * 0.5 - SPIKE_RADIUS)
			multimesh.set_instance_transform(index, Transform3D(tip_forward, Vector3(x, rows[row], -spike_length * 0.5)))
			index += 1
	var spikes := MultiMeshInstance3D.new()
	spikes.name = "Spikes"
	spikes.multimesh = multimesh
	add_child(spikes)


## Heights of the spike rows. A low wall gets fewer, so it still reads as a wall of points.
func _spike_rows() -> Array[float]:
	var rows: Array[float] = []
	var count := maxi(1, int(round(height / 0.55)))
	for i in count:
		rows.append(height * (i + 0.5) / count)
	return rows


func _build_kill_area() -> void:
	_kill_area = Area3D.new()
	_kill_area.name = "KillArea"
	_kill_area.collision_layer = 0
	_kill_area.collision_mask = VICTIM_MASK
	_kill_area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# The spikes reach the full length; their tips are thin, so the box stops a little short of them.
	var front := spike_length * 0.85
	box.size = Vector3(width, maxf(height, 1.6), front + depth)
	shape.shape = box
	shape.position = Vector3(0.0, box.size.y * 0.5, (depth - front) * 0.5)
	_kill_area.add_child(shape)
	add_child(_kill_area)


func _wood_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = preload("res://src/world/elements/sky_decks/wood_planks.gdshader")
	material.set_shader_parameter("wood_color", Color(0.42, 0.27, 0.15))
	material.set_shader_parameter("local_space", true)
	return material


func _iron_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.37, 0.4)
	material.metallic = 0.35
	material.roughness = 0.45
	return material
