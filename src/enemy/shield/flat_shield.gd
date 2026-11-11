@tool
class_name FlatShield
extends Node3D
## A standing pane of shield energy that bounces pulse bolts off both faces like a mirror, while
## enemy shots, bodies and blasts pass through it. Players can't shoot straight through it, but
## they can bank a bolt off a second, angled shield to reach whoever hides behind it.
## The origin sits at the bottom centre and the pane spans the local X/Y plane, facing ±Z:
## rotate the node to angle it. Like `EnemyShield`, it only exists in pulse rifle runs.

const THICKNESS := 0.12
const FRAME_WIDTH := 0.08
const FLASH_DECAY_PER_SEC := 5.0
const SHADER := preload("res://src/enemy/shield/enemy_shield.gdshader")
const DEFLECT_SOUND := preload("res://assets/sounds/metal/GridStep03.wav")
const FRAME_COLOR := Color(0.45, 0.9, 1.0)

## Width and height of the pane, in metres.
@export var size := Vector2(4.0, 2.5):
	set(value):
		size = value
		_rebuild()

var _material: ShaderMaterial
var _visual: Node3D
var _mirror: BoltMirror
var _flash := 0.0


func _ready() -> void:
	if not Engine.is_editor_hint() and not EnemyShield.applies_in(get_tree()):
		queue_free()
		return
	_rebuild()


func _process(delta: float) -> void:
	if _flash <= 0.0:
		return
	_flash = maxf(0.0, _flash - FLASH_DECAY_PER_SEC * delta)
	_material.set_shader_parameter("flash", _flash)


func _rebuild() -> void:
	if not is_node_ready():
		return
	if _visual != null:
		_visual.queue_free()
	if _mirror != null:
		_mirror.queue_free()
	_visual = _make_visual()
	_mirror = _make_mirror()


func _on_deflected(point: Vector3) -> void:
	_flash = 1.0
	ImpactFeedback.play_sfx(DEFLECT_SOUND, point, randf_range(1.8, 2.2), -8.0)


func _make_visual() -> Node3D:
	var visual := Node3D.new()
	visual.position = Vector3.UP * size.y * 0.5
	# Internal, so neither the editor nor a checkpoint snapshot saves the generated parts.
	add_child(visual, false, Node.INTERNAL_MODE_FRONT)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("base_alpha", 0.22)
	visual.add_child(_make_box(Vector3(size.x, size.y, THICKNESS), _material))
	var frame := StandardMaterial3D.new()
	frame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	frame.albedo_color = FRAME_COLOR
	var bar_depth := THICKNESS + 0.04
	var half := size * 0.5
	visual.add_child(_make_box(Vector3(size.x, FRAME_WIDTH, bar_depth), frame, Vector3(0.0, half.y, 0.0)))
	visual.add_child(_make_box(Vector3(size.x, FRAME_WIDTH, bar_depth), frame, Vector3(0.0, -half.y, 0.0)))
	visual.add_child(_make_box(Vector3(FRAME_WIDTH, size.y, bar_depth), frame, Vector3(half.x, 0.0, 0.0)))
	visual.add_child(_make_box(Vector3(FRAME_WIDTH, size.y, bar_depth), frame, Vector3(-half.x, 0.0, 0.0)))
	return visual


func _make_box(box_size: Vector3, material: Material, at: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.position = at
	return instance


func _make_mirror() -> BoltMirror:
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y, THICKNESS)
	var mirror := BoltMirror.create(shape)
	mirror.position = Vector3.UP * size.y * 0.5
	mirror.deflected.connect(_on_deflected)
	add_child(mirror, false, Node.INTERNAL_MODE_FRONT)
	return mirror
