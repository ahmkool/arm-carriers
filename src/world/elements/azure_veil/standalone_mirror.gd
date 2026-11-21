class_name StandaloneMirror
extends Node3D
## Fixed environmental mirror placed in a level to bounce arcane lasers around obstacles.
## Reuses `MirrorSurface` on `BoltMirror.LAYER` so `LaserEmitter`, `LaserDroneCannon`, and
## `MirrorAbsorbedBeam` reflect off both broad faces (±local X) automatically.

const SPARKS_SCENE := preload("res://src/vfx/saw_sparks.tscn")
const GLOW_DECAY_PER_SEC := 4.5
const SPARK_INTERVAL_SEC := 0.14

@onready var _glass: MeshInstance3D = $Glass
@onready var _surface: Area3D = $MirrorSurface
@onready var _glow_light: OmniLight3D = $GlowLight

var _glass_material: ShaderMaterial
var _laser_glow := 0.0
var _spark_cooldown := 0.0


func _ready() -> void:
	if _glass != null:
		var mat := _glass.get_active_material(0) as ShaderMaterial
		if mat != null:
			_glass_material = mat.duplicate() as ShaderMaterial
			_glass.material_override = _glass_material
	if _surface != null and _surface.has_signal(&"laser_reflected"):
		_surface.connect(&"laser_reflected", _on_laser_reflected)
	_update_visuals()


func _process(delta: float) -> void:
	_spark_cooldown = maxf(0.0, _spark_cooldown - delta)
	if _laser_glow <= 0.0:
		return
	_laser_glow = maxf(0.0, _laser_glow - GLOW_DECAY_PER_SEC * delta)
	_update_visuals()


func _on_laser_reflected(point: Vector3) -> void:
	_laser_glow = 1.0
	_update_visuals()
	if _spark_cooldown > 0.0:
		return
	_spark_cooldown = SPARK_INTERVAL_SEC
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var sparks := SPARKS_SCENE.instantiate() as GPUParticles3D
	sparks.amount_ratio = 0.35
	scene_root.add_child(sparks)
	sparks.global_position = point
	sparks.emitting = true


func _update_visuals() -> void:
	if _glass_material != null:
		_glass_material.set_shader_parameter("laser_glow", _laser_glow)
	if _glow_light != null:
		_glow_light.light_energy = lerpf(0.65, 2.4, _laser_glow)
