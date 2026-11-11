class_name EnemyShield
extends Node3D
## An energy bubble around its parent enemy that absorbs all damage until the pulse rifle's
## vent breaks it. Bolts bounce off it like a mirror (see `BoltMirror`), and they still heat the
## barrel, so firing at a shielded enemy charges the vent that pops it. Falling out of the level
## still kills.
## It only exists in pulse rifle runs: with any other weapon it removes itself, since nothing
## else could break it.

const FLASH_DECAY_PER_SEC := 5.0
const PULSE_HZ := 0.8
const PULSE_AMOUNT := 0.03
const SHATTER_SEC := 0.18
const DISSOLVE_SEC := 0.35
const SHADER := preload("res://src/enemy/shield/enemy_shield.gdshader")
const ABSORB_SOUND := preload("res://assets/sounds/metal/GridStep03.wav")
const SHATTER_SOUND := preload("res://assets/sounds/explosion/Small Explosion 2_1.wav")
const SHATTER_SCENE := preload("res://src/vfx/small_explosion.tscn")
const PULSE_RIFLE_ID := "pulse_rifle"

signal shattered

## Sized for a robot. Set before adding the shield to a bigger enemy.
@export var radius := 1.25
## Centre height above the enemy's feet.
@export var height := 1.0
## Shows the front carrier's VENT prompt nearby even once it has retired, for moments where
## the vent is the answer, such as a boss's shield.
@export var forces_vent_prompt := false

## Every shield that is up, so the rifle can tell when one nearby forces its prompt.
static var _active: Array[EnemyShield] = []

var _material: ShaderMaterial
var _bubble: MeshInstance3D
var _mirror: BoltMirror
var _is_up := true
var _flash := 0.0
var _time := 0.0


static func find_on(enemy: Node) -> EnemyShield:
	for child in enemy.get_children():
		if child is EnemyShield:
			return child
	return null


## Whether `enemy` is protected by a shield that is still up.
static func is_shielded(enemy: Node) -> bool:
	var shield := find_on(enemy)
	return shield != null and shield.is_up()


## Whether shields belong in this run: only the pulse rifle can break or bank off them, so with
## any other weapon they remove themselves.
static func applies_in(tree: SceneTree) -> bool:
	var world := tree.current_scene as WorldLocal
	if world == null:
		return true
	return world.get_active_weapon_id() == PULSE_RIFLE_ID


## Whether a shield that forces the VENT prompt is up within `distance` of `point`.
static func is_vent_prompt_forced_near(point: Vector3, distance: float) -> bool:
	for shield in _active:
		if not is_instance_valid(shield) or not shield.forces_vent_prompt or not shield.is_up():
			continue
		var offset := shield.global_position - point
		if Vector2(offset.x, offset.z).length() <= distance:
			return true
	return false


func _ready() -> void:
	if not applies_in(get_tree()):
		queue_free()
		return
	_bubble = _make_bubble()
	_active.append(self)
	var health := Health.from_target(get_parent())
	if health == null:
		return
	health.shield = self


func _exit_tree() -> void:
	_active.erase(self)


func _process(delta: float) -> void:
	if not _is_up:
		return
	_time += delta
	_flash = maxf(0.0, _flash - FLASH_DECAY_PER_SEC * delta)
	_material.set_shader_parameter("flash", _flash)
	_bubble.scale = Vector3.ONE * (1.0 + sin(_time * TAU * PULSE_HZ) * PULSE_AMOUNT)


func is_up() -> bool:
	return _is_up


## Called by `Health` in place of taking the damage.
func absorb(source_position: Vector3) -> void:
	_flash = 1.0
	ImpactFeedback.play_sfx(ABSORB_SOUND, _facing_point(source_position), randf_range(1.8, 2.2), -8.0)


## Breaks the shield: the enemy takes damage normally from now on.
func shatter() -> void:
	if not _is_up:
		return
	_is_up = false
	_mirror.deactivate()
	var pop := SHATTER_SCENE.instantiate() as Node3D
	get_tree().current_scene.add_child(pop)
	pop.global_position = _bubble.global_position
	ImpactFeedback.play_sfx(SHATTER_SOUND, _bubble.global_position, 1.6, -2.0)
	shattered.emit()
	_fade_out(1.5, SHATTER_SEC)


## Lowers the shield quietly, for an enemy that drops its own shield rather than losing it.
func dissolve() -> void:
	if not _is_up:
		return
	_is_up = false
	_mirror.deactivate()
	_fade_out(0.9, DISSOLVE_SEC)


func _fade_out(end_scale: float, seconds: float) -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(_bubble, "scale", Vector3.ONE * end_scale, seconds)
	tween.tween_method(func(f: float): _material.set_shader_parameter("fade", f), 1.0, 0.0, seconds)
	tween.chain().tween_callback(queue_free)


## The point on the bubble facing the hit, so the ping sounds from where the bolt struck.
func _facing_point(source_position: Vector3) -> Vector3:
	var centre := _bubble.global_position
	var towards := source_position - centre
	if towards.length_squared() < 0.0001:
		return centre
	return centre + towards.normalized() * radius


func _make_bubble() -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	var bubble := MeshInstance3D.new()
	bubble.mesh = sphere
	bubble.material_override = _material
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bubble.position = Vector3.UP * height
	# Internal, so a checkpoint reset's enemy snapshot doesn't copy it next to the new one.
	add_child(bubble, false, Node.INTERNAL_MODE_FRONT)
	var shape := SphereShape3D.new()
	shape.radius = radius
	_mirror = BoltMirror.create(shape)
	_mirror.deflected.connect(absorb)
	bubble.add_child(_mirror)
	return bubble
